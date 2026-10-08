import XCTest
@testable import FreeMind

/// 简单检查数据是不是 PDF（以 %PDF- 开头）。
enum PDFDocumentHeader {
    static func check(_ data: Data) -> Bool? {
        data.prefix(5) == Data("%PDF-".utf8) ? true : nil
    }
}

/// `.fmind` 包格式读写。
final class DocumentPackageTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("FreeMindTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func sampleDocument() -> (MindMapDocument, attachmentID: UUID, imageID: UUID) {
        let doc = MindMapDocument()
        var map = MindMap.blank(title: "测试导图")
        let attachmentData = Data("hello attachment".utf8)
        let attachmentID = doc.attachments.add(data: attachmentData, name: "说明 文档.txt")
        let png = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { r in
            NSColor.red.setFill(); r.fill(); return true
        }.pngData!
        let imageID = doc.attachments.add(data: png, name: "red.png")
        map.root.children[0].attachments = [Attachment(id: attachmentID, name: "说明 文档.txt", size: Int64(attachmentData.count))]
        map.root.children[0].image = TopicImage(id: imageID, name: "red.png", width: 8, height: 8)
        map.root.children[1].children = [Topic(title: "深层"), Topic(title: "Deep")]
        map.root.children[1].collapsed = true
        map.root.children[2].note = "备注\n第二行"
        map.root.children[2].link = "https://example.com"
        map.root.children[2].markers = [MarkerID("priority-1"), MarkerID("task-50")]
        map.root.children[2].labels = ["A", "标签"]
        map.root.children[3].style.fill = "#FF0000"
        map.root.children[3].style.boundary = true
        map.structure = .logicRight
        map.theme = .midnight
        map.spacing = .loose
        doc.editor.load(map)
        return (doc, attachmentID, imageID)
    }

    func testRoundTripPreservesEverything() throws {
        let (doc, attachmentID, imageID) = sampleDocument()
        let url = tempDir.appendingPathComponent("map.fmind")
        try doc.write(to: url, ofType: DocumentTypes.map)

        // 包结构
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathComponent("content.json").path))
        let attachmentFile = url.appendingPathComponent("attachments/\(attachmentID.uuidString)/说明 文档.txt")
        XCTAssertEqual(try String(contentsOf: attachmentFile, encoding: .utf8), "hello attachment")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathComponent("attachments/\(imageID.uuidString)/red.png").path))

        // 读回
        let loaded = MindMapDocument()
        try loaded.read(from: url, ofType: DocumentTypes.map)
        XCTAssertEqual(loaded.editor.map, doc.editor.map)
        XCTAssertTrue(loaded.editor.map.root.children[1].collapsed, "折叠状态要随文件保存")
        XCTAssertEqual(loaded.attachments.data(for: attachmentID), Data("hello attachment".utf8))
        XCTAssertNotNil(loaded.attachments.image(for: imageID))
    }

    func testUnreferencedAttachmentsArePrunedButKeptInMemory() throws {
        let (doc, attachmentID, _) = sampleDocument()
        let url = tempDir.appendingPathComponent("prune.fmind")
        try doc.write(to: url, ofType: DocumentTypes.map)

        // 删除引用附件的主题后再保存：文件从包里移除
        var map = doc.editor.map
        map.root.children[0].attachments = []
        doc.editor.load(map)
        let wrapper = try doc.fileWrapper(ofType: DocumentTypes.map)
        try wrapper.write(to: tempDir.appendingPathComponent("prune2.fmind"), options: .atomic, originalContentsURL: nil)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("prune2.fmind/attachments/\(attachmentID.uuidString)").path))
        // 但内存里还在（撤销后还能恢复）
        XCTAssertEqual(doc.attachments.data(for: attachmentID), Data("hello attachment".utf8))
    }

    func testContentJSONIsReadable() throws {
        let (doc, _, _) = sampleDocument()
        let url = tempDir.appendingPathComponent("json.fmind")
        try doc.write(to: url, ofType: DocumentTypes.map)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url.appendingPathComponent("content.json"))) as! [String: Any]
        XCTAssertEqual(json["format"] as? String, "freemind")
        XCTAssertEqual(json["version"] as? Int, 1)
        let map = json["map"] as! [String: Any]
        XCTAssertEqual(map["structure"] as? String, "logic-right")
        let root = map["root"] as! [String: Any]
        XCTAssertEqual(root["title"] as? String, "测试导图")
    }

    /// 导出 Markdown（含附件文件夹）再导入，附件和图片都能找回来。
    func testMarkdownExportWithAssetsRoundTrip() throws {
        let (doc, attachmentID, _) = sampleDocument()
        let url = tempDir.appendingPathComponent("导出.md")
        try doc.writeMarkdown(to: url, options: MarkdownExportOptions(), exportAssets: true)
        let assets = tempDir.appendingPathComponent("导出.assets")
        XCTAssertTrue(FileManager.default.fileExists(atPath: assets.appendingPathComponent("说明 文档.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: assets.appendingPathComponent("red.png").path))

        let imported = try Importer.importFile(at: url)
        let topic = imported.map.root.children[0]
        XCTAssertEqual(topic.attachments.map(\.name), ["说明 文档.txt"])
        XCTAssertNotNil(topic.image)
        let newAttachmentID = try XCTUnwrap(topic.attachments.first?.id)
        XCTAssertEqual(imported.resources[newAttachmentID]?.data, doc.attachments.data(for: attachmentID))
        XCTAssertEqual(imported.map.root.children[2].link, "https://example.com")
        XCTAssertEqual(imported.map.root.children[2].note, "备注\n第二行")
    }

    func testImageExportAndPrinting() throws {
        let (doc, _, _) = sampleDocument()
        let layout = doc.editor.layout
        let png = try XCTUnwrap(ImageExporter.pngData(layout: layout, images: { doc.attachments.image(for: $0) }, scale: 2))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(rep.pixelsWide, Int((ceil(layout.bounds.width + 80) * 2)))
        let pdf = ImageExporter.pdfData(layout: layout, images: { _ in nil })
        XCTAssertGreaterThan(pdf.count, 1000)
        XCTAssertNotNil(PDFDocumentHeader.check(pdf))
        let op = try doc.printOperation(withSettings: [:])
        XCTAssertGreaterThan(op.view?.bounds.width ?? 0, 100)
        XCTAssertEqual(op.printInfo.horizontalPagination, .fit)
    }

    func testRejectsNewerVersion() throws {
        let data = Data(#"{"format":"freemind","version":99,"map":{"root":{"title":"x"}}}"#.utf8)
        XCTAssertThrowsError(try DocumentContent.decode(data))
    }

    func testToleratesMissingOptionalFields() throws {
        let data = Data(#"{"format":"freemind","version":1,"map":{"root":{"title":"Root","children":[{"title":"A"}]}}}"#.utf8)
        let content = try DocumentContent.decode(data)
        XCTAssertEqual(content.map.root.children.first?.title, "A")
        XCTAssertEqual(content.map.structure, .mindMap)
        XCTAssertEqual(content.map.theme.id, Theme.classic.id)
    }
}
