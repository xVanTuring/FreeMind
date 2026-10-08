import XCTest
@testable import FreeMind

final class ImportExportTests: XCTestCase {
    private func sampleMap() -> MindMap {
        var root = Topic(title: "中心主题")
        var a = Topic(title: "分支 A")
        a.note = "A 的备注\n\n第二段"
        var a1 = Topic(title: "子主题 A1")
        a1.link = "https://example.com/a1"
        var a11 = Topic(title: "第三层")
        a11.children = [Topic(title: "第四层 #1"), Topic(title: "- 不是列表")]
        a11.markers = [MarkerID("task-100")]
        a1.children = [a11]
        a.children = [a1, Topic(title: "子主题 A2")]
        root.children = [a, Topic(title: "分支 B", children: [Topic(title: "1. 不是有序列表")])]
        return MindMap(root: root)
    }

    private func titles(_ t: Topic) -> [String] {
        var out: [String] = []
        t.forEach { out.append($0.title) }
        return out
    }

    func testMarkdownRoundTrip() {
        let map = sampleMap()
        for levels in 0...4 {
            var options = MarkdownExportOptions()
            options.headingLevels = levels
            let md = MarkdownExporter.export(map, options: options).text
            let imported = MarkdownImporter.parse(md, defaultTitle: "中心主题").map
            XCTAssertEqual(titles(imported.root), titles(map.root), "headingLevels=\(levels)\n\(md)")
            let a1 = imported.root.children[0].children[0]
            XCTAssertEqual(a1.link, "https://example.com/a1", "levels=\(levels)")
            if levels > 0 {
                XCTAssertEqual(imported.root.children[0].note, "A 的备注\n\n第二段", "levels=\(levels)\n\(md)")
            }
        }
    }

    func testMarkdownTaskCheckboxes() {
        let md = """
        # 待办
        - [x] 完成
        - [ ] 未完成
          - 普通
        """
        let root = MarkdownImporter.parse(md, defaultTitle: "x").map.root
        XCTAssertEqual(root.title, "待办")
        XCTAssertEqual(root.children[0].markers, [MarkerID("task-100")])
        XCTAssertEqual(root.children[1].markers, [MarkerID("task-0")])
        XCTAssertEqual(root.children[1].children[0].title, "普通")
    }

    func testMarkdownMultipleTopLevelHeadingsGetSyntheticRoot() {
        let md = """
        前言文字

        # 第一章
        内容
        ## 1.1
        # 第二章
        * 要点
        """
        let root = MarkdownImporter.parse(md, defaultTitle: "书名").map.root
        XCTAssertEqual(root.title, "书名")
        XCTAssertEqual(root.note, "前言文字")
        XCTAssertEqual(root.children.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(root.children[0].note, "内容")
        XCTAssertEqual(root.children[0].children.map(\.title), ["1.1"])
        XCTAssertEqual(root.children[1].children.map(\.title), ["要点"])
    }

    func testMarkdownSetextAndCodeBlocks() {
        let md = """
        Title
        =====

        Section
        -------
        ```
        # not a heading
        - not a list
        ```
        """
        let root = MarkdownImporter.parse(md, defaultTitle: "x").map.root
        XCTAssertEqual(root.title, "Title")
        XCTAssertEqual(root.children.map(\.title), ["Section"])
        XCTAssertTrue(root.children[0].note.contains("# not a heading"))
        XCTAssertTrue(root.children[0].children.isEmpty)
    }

    func testPlainIndentedOutline() {
        let text = "项目\n\t需求\n\t\t调研\n\t开发\n"
        let topics = MarkdownImporter.parseFragment(text)
        XCTAssertEqual(topics.count, 1)
        XCTAssertEqual(topics[0].title, "项目")
        XCTAssertEqual(topics[0].children.map(\.title), ["需求", "开发"])
        XCTAssertEqual(topics[0].children[0].children.map(\.title), ["调研"])
    }

    func testMarkdownExportWithAssets() {
        var map = sampleMap()
        let id = UUID()
        map.root.children[1].attachments = [Attachment(id: id, name: "报告.pdf", size: 10)]
        var options = MarkdownExportOptions()
        options.assetsFolder = "导图.assets"
        let result = MarkdownExporter.export(map, options: options)
        XCTAssertEqual(result.assets[id], "导图.assets/报告.pdf")
        XCTAssertTrue(result.text.contains("📎 [报告.pdf]("), result.text)
    }

    func testMarkdownImportResolvesLocalResources() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("md-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("assets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = NSImage(size: NSSize(width: 10, height: 6), flipped: false) { r in NSColor.blue.setFill(); r.fill(); return true }.pngData!
        try png.write(to: dir.appendingPathComponent("assets/pic.png"))
        try Data("pdf".utf8).write(to: dir.appendingPathComponent("assets/doc file.pdf"))
        let md = """
        # Root
        ## Topic
        ![pic](assets/pic.png)

        📎 [doc file.pdf](assets/doc%20file.pdf)
        """
        let mdURL = dir.appendingPathComponent("map.md")
        try md.write(to: mdURL, atomically: true, encoding: .utf8)
        let result = try Importer.importFile(at: mdURL)
        let topic = result.map.root.children[0]
        XCTAssertNotNil(topic.image)
        XCTAssertEqual(topic.attachments.map(\.name), ["doc file.pdf"])
        XCTAssertEqual(result.resources.count, 2)
        XCTAssertEqual(topic.note, "")
    }

    func testOPMLRoundTrip() throws {
        var map = sampleMap()
        map.root.children[0].collapsed = true
        let opml = OPMLExporter.export(map)
        let imported = try OPMLImporter.parse(Data(opml.utf8), defaultTitle: "x").map
        XCTAssertEqual(titles(imported.root), titles(map.root))
        XCTAssertEqual(imported.root.children[0].note, map.root.children[0].note)
        XCTAssertTrue(imported.root.children[0].collapsed)
        XCTAssertEqual(imported.root.children[0].children[0].link, "https://example.com/a1")
    }

    func testXMindImport() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xmind-\(UUID().uuidString)")
        let content = dir.appendingPathComponent("content")
        try FileManager.default.createDirectory(at: content.appendingPathComponent("resources"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("file".utf8).write(to: content.appendingPathComponent("resources/abc.txt"))
        let json = """
        [{"id":"s1","class":"sheet","title":"画布 1","rootTopic":{"id":"r","title":"中心","structureClass":"org.xmind.ui.logic.right",
          "children":{"attached":[
            {"id":"a","title":"分支","branch":"folded","notes":{"plain":{"content":"备注"}},
             "markers":[{"markerId":"priority-2"},{"markerId":"task-half"},{"markerId":"flag-red"}],
             "labels":["L1"],
             "children":{"attached":[{"id":"a1","title":"子"}]}},
            {"id":"b","title":"链接","href":"https://xmind.app"},
            {"id":"c","title":"abc.txt","href":"xap:resources/abc.txt"}
          ]}},
          "relationships":[{"id":"rel1","end1Id":"a","end2Id":"b","title":"关联"}]}]
        """
        try json.write(to: content.appendingPathComponent("content.json"), atomically: true, encoding: .utf8)
        let xmind = dir.appendingPathComponent("test.xmind")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", content.path, xmind.path]
        try p.run()
        p.waitUntilExit()

        let results = try XMindImporter.importFile(at: xmind)
        XCTAssertEqual(results.count, 1)
        let map = results[0].map
        XCTAssertEqual(map.structure, .logicRight)
        XCTAssertEqual(map.root.title, "中心")
        let a = map.root.children[0]
        XCTAssertTrue(a.collapsed)
        XCTAssertEqual(a.note, "备注")
        XCTAssertEqual(Set(a.markers), [MarkerID("priority-2"), MarkerID("task-50"), MarkerID("flag-red")])
        XCTAssertEqual(a.labels, ["L1"])
        XCTAssertEqual(a.children.map(\.title), ["子"])
        XCTAssertEqual(map.root.children[1].link, "https://xmind.app")
        XCTAssertEqual(map.root.children[2].attachments.count, 1)
        XCTAssertEqual(results[0].resources.values.first?.data, Data("file".utf8))
        XCTAssertEqual(map.relationships.count, 1)
        XCTAssertEqual(map.relationships.first?.from, a.id)
        XCTAssertEqual(map.relationships.first?.to, map.root.children[1].id)
        XCTAssertEqual(map.relationships.first?.title, "关联")
    }

    func testMarkdownEscaping() {
        XCTAssertEqual(MarkdownExporter.escape("# hash", atLineStart: true), "\\# hash")
        XCTAssertEqual(MarkdownExporter.escape("1. item", atLineStart: true), "1\\. item")
        XCTAssertEqual(MarkdownExporter.escape("2026.10", atLineStart: true), "2026.10")
        XCTAssertEqual(MarkdownImporter.cleanInline("1\\. item"), "1. item")
        XCTAssertEqual(MarkdownImporter.cleanInline("**粗体** 文字"), "粗体 文字")
    }
}
