import XCTest
@testable import FreeMind

/// 代码审查发现的问题的回归测试。
final class RegressionTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("FreeMindRegression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// 附件目录里多了 .DS_Store：要读到真正的附件；删除引用、保存、撤销后附件仍可找回。
    func testHiddenFilesInAttachmentFolderAreIgnored() throws {
        let doc = MindMapDocument()
        var map = MindMap.blank()
        let payload = Data("真正的附件".utf8)
        let id = doc.attachments.add(data: payload, name: "a.txt")
        map.root.children[0].attachments = [Attachment(id: id, name: "a.txt", size: Int64(payload.count))]
        doc.editor.load(map)
        let url = tempDir.appendingPathComponent("hidden.fmind")
        try doc.write(to: url, ofType: DocumentTypes.map)
        try Data("junk".utf8).write(to: url.appendingPathComponent("attachments/\(id.uuidString)/.DS_Store"))
        try Data("junk".utf8).write(to: url.appendingPathComponent("attachments/\(id.uuidString)/._a.txt"))

        let loaded = MindMapDocument()
        try loaded.read(from: url, ofType: DocumentTypes.map)
        XCTAssertEqual(loaded.attachments.data(for: id), payload)
        XCTAssertEqual(loaded.attachments.fileName(for: id), "a.txt")

        // 删掉引用后保存（附件从包里移除），内存里仍保留正确内容
        var m = loaded.editor.map
        m.root.children[0].attachments = []
        loaded.editor.load(m)
        let wrapper = try loaded.fileWrapper(ofType: DocumentTypes.map)
        XCTAssertNil(wrapper.fileWrappers?["attachments"]?.fileWrappers?[id.uuidString])
        XCTAssertEqual(loaded.attachments.data(for: id), payload)
    }

    /// 保存不结束行内编辑，且编辑中的文字会被保存。
    func testSavingDuringInlineEditKeepsEditingAndSavesText() throws {
        let doc = MindMapDocument()
        doc.editor.load(MindMap.blank(title: "Root"))
        let id = doc.editor.map.root.children[0].id
        doc.editor.select(id)
        doc.editor.beginEditing(id)
        doc.editor.editingTextDidChange("编辑中的标题")
        XCTAssertTrue(doc.isDocumentEdited, "开始输入后文档应被标记为已修改")
        let wrapper = try doc.fileWrapper(ofType: DocumentTypes.map)
        XCTAssertTrue(doc.editor.isEditing, "保存不能打断输入")
        let data = try XCTUnwrap(wrapper.fileWrappers?["content.json"]?.regularFileContents)
        XCTAssertEqual(try DocumentContent.decode(data).map.root.children[0].title, "编辑中的标题")
        doc.editor.endEditing(commit: true)
        XCTAssertEqual(doc.editor.map.root.children[0].title, "编辑中的标题")
    }

    /// 取消编辑后，编辑期间临时加的“已修改”计数要抵消。
    func testCancelledEditDoesNotLeaveDocumentEdited() {
        let doc = MindMapDocument()
        doc.editor.load(MindMap.blank(title: "Root"))
        let id = doc.editor.map.root.children[0].id
        doc.editor.beginEditing(id)
        doc.editor.editingTextDidChange("x")
        doc.editor.endEditing(commit: false)
        XCTAssertFalse(doc.isDocumentEdited)
    }

    /// 合并撤销在保存后断开：保存之后的修改会重新把文档标记为已修改。
    func testCoalescingBreaksAfterSave() throws {
        let doc = MindMapDocument()
        doc.undoManager?.groupsByEvent = false
        doc.editor.load(MindMap.blank(title: "Root"))
        let id = doc.editor.rootID
        // NSDocument 在撤销分组结束后的运行循环里更新修改计数
        func group(_ body: () -> Void) {
            doc.undoManager?.beginUndoGrouping()
            body()
            doc.undoManager?.endUndoGrouping()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        group { doc.editor.setNote(id, "a") }
        XCTAssertTrue(doc.isDocumentEdited)
        _ = try doc.fileWrapper(ofType: DocumentTypes.map)
        doc.updateChangeCount(.changeCleared)
        XCTAssertFalse(doc.isDocumentEdited)
        // 保存后的第一次修改不能并入保存前的撤销步骤；之后的连续输入照常合并
        group {
            doc.editor.setNote(id, "ab")
            doc.editor.setNote(id, "abc")
        }
        XCTAssertTrue(doc.isDocumentEdited, "保存后的修改必须让文档重新变成已修改")
        doc.undoManager?.undo()
        XCTAssertEqual(doc.editor.map.root.note, "a")
    }

    /// 撤销恢复的选中项若已被折叠隐藏，改为选中可见的祖先。
    func testUndoSelectionStaysVisible() {
        let doc = MindMapDocument()
        doc.undoManager?.groupsByEvent = false
        doc.editor.load(MindMap.blank(title: "Root"))
        let a = doc.editor.map.root.children[0].id
        doc.undoManager?.beginUndoGrouping()
        doc.editor.addChild(to: a, edit: false)
        doc.undoManager?.endUndoGrouping()
        let b = doc.editor.map.topic(a)!.children[0].id
        doc.editor.select(b)
        doc.undoManager?.beginUndoGrouping()
        doc.editor.toggleMarker(MarkerID("priority-1"))
        doc.undoManager?.endUndoGrouping()
        doc.editor.setCollapsed([a], true)
        doc.undoManager?.undo()
        XCTAssertEqual(doc.editor.selection, [a])
        doc.editor.beginEditing(b)
        XCTAssertFalse(doc.editor.isEditing, "隐藏的主题不能进入编辑")
    }

    func testMarkdownNoteLinesSurviveRoundTrip() {
        var root = Topic(title: "Root")
        var child = Topic(title: "Child")
        child.note = "- 不是子主题\n# 也不是标题\n1. 也不是列表\n---\n```\n- 代码块里原样保留\n```"
        root.children = [child, Topic(title: "Other")]
        for levels in [0, 2] {
            var options = MarkdownExportOptions()
            options.headingLevels = levels
            let md = MarkdownExporter.export(MindMap(root: root), options: options).text
            let imported = MarkdownImporter.parse(md, defaultTitle: "x").map.root
            XCTAssertEqual(imported.children.map(\.title), ["Child", "Other"], md)
            XCTAssertEqual(imported.children[0].note, child.note, md)
        }
    }

    func testMarkdownLinksWithSpacesRoundTrip() {
        var root = Topic(title: "Root")
        var child = Topic(title: "Doc")
        child.link = "/Users/me/My Documents/plan.pdf"
        root.children = [child]
        let md = MarkdownExporter.export(MindMap(root: root)).text
        let imported = MarkdownImporter.parse(md, defaultTitle: "x").map.root
        XCTAssertEqual(imported.children[0].link, child.link)
    }

    func testMarkdownImportRefusesFilesOutsideItsFolder() throws {
        let inner = tempDir.appendingPathComponent("inner")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: tempDir.appendingPathComponent("secret.txt"))
        try FileManager.default.createSymbolicLink(at: inner.appendingPathComponent("link.txt"),
                                                   withDestinationURL: tempDir.appendingPathComponent("secret.txt"))
        let md = """
        # Root
        ## A
        📎 [secret](../secret.txt)

        📎 [abs](\(tempDir.appendingPathComponent("secret.txt").path))

        📎 [link](link.txt)
        """
        let url = inner.appendingPathComponent("map.md")
        try md.write(to: url, atomically: true, encoding: .utf8)
        let result = try Importer.importFile(at: url)
        XCTAssertTrue(result.resources.isEmpty)
        XCTAssertTrue(result.map.root.children[0].attachments.isEmpty)
    }

    func testXMindArchivePathsCannotEscape() throws {
        let archive = tempDir.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: archive.appendingPathComponent("resources"), withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: archive.appendingPathComponent("resources/a.txt"))
        try Data("secret".utf8).write(to: tempDir.appendingPathComponent("secret.txt"))
        XCTAssertEqual(XMindImporter.archiveFile("resources/a.txt", in: archive), Data("ok".utf8))
        XCTAssertNil(XMindImporter.archiveFile("../secret.txt", in: archive))
        XCTAssertNil(XMindImporter.archiveFile("resources/../../secret.txt", in: archive))
    }

    func testOPMLEscapesTabsAndControlCharacters() throws {
        var root = Topic(title: "a\u{0001}b")
        root.note = "列1\t列2\r\n下一行"
        let opml = OPMLExporter.export(MindMap(root: root))
        let imported = try OPMLImporter.parse(Data(opml.utf8), defaultTitle: "x").map.root
        XCTAssertEqual(imported.title, "ab")
        XCTAssertEqual(imported.note, root.note)
    }

    func testDamagedRelationshipDoesNotDropOthers() throws {
        let a = UUID(), b = UUID()
        let json = """
        {"format":"freemind","version":1,"map":{"root":{"id":"\(a)","title":"R","children":[{"id":"\(b)","title":"C"}]},
         "relationships":[{"id":"\(UUID())","to":"\(b)"},{"id":"\(UUID())","from":"\(a)","to":"\(b)","title":"ok"}]}}
        """
        let content = try DocumentContent.decode(Data(json.utf8))
        XCTAssertEqual(content.map.relationships.map(\.title), ["ok"])
    }

    func testRemoveLabelOnlyAffectsThatLabel() {
        let doc = MindMapDocument()
        doc.editor.load(MindMap.blank())
        let a = doc.editor.map.root.children[0].id, b = doc.editor.map.root.children[1].id
        doc.editor.setLabels([a], ["x"])
        doc.editor.setLabels([b], ["y", "z"])
        doc.editor.removeLabel("z", from: [a, b])
        XCTAssertEqual(doc.editor.map.topic(a)?.labels, ["x"])
        XCTAssertEqual(doc.editor.map.topic(b)?.labels, ["y"])
    }
}
