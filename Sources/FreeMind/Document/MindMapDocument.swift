import AppKit

/// `.fmind` 文档。专属格式是一个 package（目录包）：
///
/// ```
/// 我的导图.fmind/
///   content.json            导图结构、主题、折叠状态、视图状态
///   attachments/<uuid>/<文件名>   附件和主题图片
/// ```
final class MindMapDocument: NSDocument {
    let editor: MapEditor
    let attachments = AttachmentStore()
    /// 读取时拿到的包结构，保存时在它上面增量修改，未改动的附件不会被重写。
    private var packageWrapper: FileWrapper?
    /// 打开文档时要恢复的视图状态。
    private(set) var restoredViewState: ViewState?
    /// MCP 工具里指代这份文档的编号（`m1`、`m2`…），只在本次运行内有效。
    let agentID: String = {
        agentCounter += 1
        return "m\(agentCounter)"
    }()
    private static var agentCounter = 0

    override init() {
        let prefs = Preferences.shared
        editor = MapEditor(map: .blank(structure: prefs.defaultStructure, theme: prefs.defaultTheme))
        super.init()
        editor.document = self
    }

    override class var autosavesInPlace: Bool { true }

    override class var readableTypes: [String] {
        [DocumentTypes.map, DocumentTypes.markdown, DocumentTypes.opml, DocumentTypes.xmind]
    }

    override class var writableTypes: [String] { [DocumentTypes.map] }

    override class func isNativeType(_ type: String) -> Bool { type == DocumentTypes.map }

    override func makeWindowControllers() {
        addWindowController(MapWindowController())
    }

    // MARK: 读取

    override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        guard typeName == DocumentTypes.map else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard fileWrapper.isDirectory,
              let data = fileWrapper.fileWrappers?[DocumentContent.contentFileName]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let content = try DocumentContent.decode(data)
        attachments.load(from: fileWrapper.fileWrappers?[AttachmentStore.directoryName])
        attachments.packageURL = fileURL
        packageWrapper = fileWrapper
        restoredViewState = content.view
        editor.load(content.map)
    }

    override func read(from url: URL, ofType typeName: String) throws {
        if typeName == DocumentTypes.map {
            try super.read(from: url, ofType: typeName)
            attachments.packageURL = url
            return
        }
        // Markdown / OPML / XMind：作为导入处理（DocumentController 会把它变成未命名文档）。
        let imported = try Importer.importFile(at: url)
        attachments.load(from: nil)
        for (id, file) in imported.resources {
            attachments.add(data: file.data, name: file.name, id: id)
        }
        editor.load(imported.map)
    }

    override var fileURL: URL? {
        didSet { attachments.packageURL = fileURL }
    }

    // MARK: 保存

    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        // 正在行内编辑的文字一起保存，但不结束编辑（自动保存不能打断输入）
        let map = editor.mapForSaving
        editor.breakCoalescing()
        let content = DocumentContent(map: map, view: currentViewState())
        let data = try content.encoded()

        let root = packageWrapper ?? FileWrapper(directoryWithFileWrappers: [:])
        if let old = root.fileWrappers?[DocumentContent.contentFileName] {
            root.removeFileWrapper(old)
        }
        root.addRegularFile(withContents: data, preferredFilename: DocumentContent.contentFileName)
        attachments.sync(into: root, referenced: map.referencedResourceIDs)
        packageWrapper = root
        return root
    }

    /// 关闭前先提交行内编辑，避免输入了一半的标题丢失。
    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?,
                           contextInfo: UnsafeMutableRawPointer?) {
        editor.commitEditingIfNeeded()
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }

    private func currentViewState() -> ViewState? {
        (windowControllers.first as? MapWindowController)?.currentViewState()
    }

    /// 导入、模板创建的新文档：直接替换内容和资源。
    func setInitialContent(_ map: MindMap, resources: [UUID: ResourceFile] = [:]) {
        for (id, file) in resources {
            attachments.add(data: file.data, name: file.name, id: id)
        }
        editor.load(map)
    }

    // MARK: 打印

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let view = MapExportView(layout: editor.layout, images: { [weak self] in self?.attachments.image(for: $0) })
        let info = printInfo.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        info.orientation = view.bounds.width > view.bounds.height ? .landscape : .portrait
        for (key, value) in printSettings { info.dictionary()[key] = value }
        return NSPrintOperation(view: view, printInfo: info)
    }
}
