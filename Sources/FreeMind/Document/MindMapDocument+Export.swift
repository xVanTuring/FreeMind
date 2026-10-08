import AppKit
import UniformTypeIdentifiers

/// 导出：Markdown / OPML / PNG / PDF，以及“存为模板”。
extension MindMapDocument {
    private var exportBaseName: String {
        let name = displayName.map { ($0 as NSString).deletingPathExtension } ?? ""
        return name.isEmpty ? editor.map.root.title : name
    }

    private var exportWindow: NSWindow? { windowForSheet }

    private func runSavePanel(type: UTType, name: String, accessory: NSView? = nil,
                              completion: @escaping (URL) throws -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.accessoryView = accessory
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try completion(url)
            } catch {
                self?.presentErrorSafely(error)
            }
        }
        if let window = exportWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    private func presentErrorSafely(_ error: Error) {
        if let window = exportWindow {
            presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
        } else {
            presentError(error)
        }
    }

    // MARK: Markdown

    @IBAction func exportMarkdown(_ sender: Any?) {
        editor.commitEditingIfNeeded()
        let prefs = Preferences.shared
        let accessory = MarkdownExportAccessory()
        let markdownType = UTType(filenameExtension: "md") ?? .plainText
        runSavePanel(type: markdownType, name: exportBaseName + ".md", accessory: accessory.view) { [weak self] url in
            guard let self else { return }
            accessory.persist()
            try self.writeMarkdown(to: url, options: prefs.markdownOptions, exportAssets: prefs.markdownExportAttachments)
        }
    }

    /// 写出 Markdown；exportAssets 时附件和图片放到同目录的 `<文件名>.assets/` 里，并在正文中用相对路径引用。
    func writeMarkdown(to url: URL, options: MarkdownExportOptions, exportAssets: Bool) throws {
        var options = options
        if exportAssets, !editor.map.referencedResourceIDs.isEmpty {
            options.assetsFolder = url.deletingPathExtension().lastPathComponent + ".assets"
        }
        let result = MarkdownExporter.export(editor.map, options: options)
        try result.text.write(to: url, atomically: true, encoding: .utf8)
        guard let folder = options.assetsFolder, !result.assets.isEmpty else { return }
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(folder), withIntermediateDirectories: true)
        for (id, relative) in result.assets {
            guard let data = attachments.data(for: id) else { continue }
            try data.write(to: dir.appendingPathComponent(relative))
        }
    }

    @IBAction func copyAsMarkdown(_ sender: Any?) {
        editor.commitEditingIfNeeded()
        let text = MarkdownExporter.export(editor.map, options: Preferences.shared.markdownOptions).text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: OPML

    @IBAction func exportOPML(_ sender: Any?) {
        editor.commitEditingIfNeeded()
        let type = UTType(filenameExtension: "opml") ?? .xml
        runSavePanel(type: type, name: exportBaseName + ".opml") { [weak self] url in
            guard let self else { return }
            try OPMLExporter.export(self.editor.map).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: 图片 / PDF

    @IBAction func exportPNG(_ sender: Any?) {
        editor.commitEditingIfNeeded()
        let layout = editor.layout
        runSavePanel(type: .png, name: exportBaseName + ".png") { [weak self] url in
            guard let self else { return }
            let scale = CGFloat(Preferences.shared.pngScale)
            guard let data = ImageExporter.pngData(layout: layout, images: { self.attachments.image(for: $0) }, scale: scale) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: url)
        }
    }

    @IBAction func exportPDF(_ sender: Any?) {
        editor.commitEditingIfNeeded()
        let layout = editor.layout
        runSavePanel(type: .pdf, name: exportBaseName + ".pdf") { [weak self] url in
            guard let self else { return }
            try ImageExporter.pdfData(layout: layout, images: { self.attachments.image(for: $0) }).write(to: url)
        }
    }

    // MARK: 模板

    @IBAction func saveAsTemplate(_ sender: Any?) {
        editor.commitEditingIfNeeded()
        let alert = NSAlert()
        alert.messageText = L("Save as Template")
        alert.informativeText = L("The template will appear in the template gallery when you create a new map.")
        let field = NSTextField(string: exportBaseName)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            do {
                try TemplateLibrary.shared.saveTemplate(from: self, name: name.isEmpty ? self.exportBaseName : name)
            } catch {
                self.presentErrorSafely(error)
            }
        }
        if let window = exportWindow {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    /// 生成完整的包结构（不影响当前文档的保存状态），用于存模板。
    func packageSnapshot() throws -> FileWrapper {
        let map = editor.mapForSaving
        let content = DocumentContent(map: map, view: nil)
        let root = FileWrapper(directoryWithFileWrappers: [:])
        root.addRegularFile(withContents: try content.encoded(), preferredFilename: DocumentContent.contentFileName)
        let referenced = map.referencedResourceIDs
        if !referenced.isEmpty {
            let dir = FileWrapper(directoryWithFileWrappers: [:])
            dir.preferredFilename = AttachmentStore.directoryName
            for id in referenced {
                guard let data = attachments.data(for: id), let name = attachments.fileName(for: id) else { continue }
                let file = FileWrapper(regularFileWithContents: data)
                file.preferredFilename = name
                let entry = FileWrapper(directoryWithFileWrappers: [name: file])
                entry.preferredFilename = id.uuidString
                dir.addFileWrapper(entry)
            }
            root.addFileWrapper(dir)
        }
        return root
    }
}

/// Markdown 导出面板上的选项。
final class MarkdownExportAccessory {
    let view: NSView
    private let levels = NSPopUpButton()
    private let notes = NSButton(checkboxWithTitle: L("Include notes"), target: nil, action: nil)
    private let attachments = NSButton(checkboxWithTitle: L("Export attachments and images to a folder"), target: nil, action: nil)

    init() {
        let prefs = Preferences.shared
        for n in 0...6 {
            levels.addItem(withTitle: n == 0 ? L("None (lists only)") : LF("%d levels", n))
        }
        levels.selectItem(at: prefs.markdownHeadingLevels)
        notes.state = prefs.markdownIncludeNotes ? .on : .off
        attachments.state = prefs.markdownExportAttachments ? .on : .off

        let label = NSTextField(labelWithString: L("Headings for:"))
        let row = NSStackView(views: [label, levels])
        row.spacing = 8
        let stack = NSStackView(views: [row, notes, attachments])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        view = stack
    }

    func persist() {
        let prefs = Preferences.shared
        prefs.markdownHeadingLevels = max(0, levels.indexOfSelectedItem)
        prefs.markdownIncludeNotes = notes.state == .on
        prefs.markdownExportAttachments = attachments.state == .on
    }
}
