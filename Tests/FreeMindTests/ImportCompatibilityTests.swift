import AppKit
import XCTest
@testable import FreeMind

/// 按真实软件导出文件的结构写的兼容性测试（XMind 8 / 新版 XMind / Workflowy / Logseq）。
/// 结构取自 XMind 8 Pro、XMind Zen、XMind 2026 实际保存的文件，以及 Workflowy、Logseq 导出的 OPML。
final class ImportCompatibilityTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("FreeMindCompat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// 把文件打包成 .xmind（zip）。
    private func makeXMind(_ files: [String: Data]) throws -> URL {
        let content = tempDir.appendingPathComponent("content-\(UUID().uuidString)")
        for (path, data) in files {
            let url = content.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        let xmind = tempDir.appendingPathComponent("\(UUID().uuidString).xmind")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", content.path, xmind.path]
        try p.run()
        p.waitUntilExit()
        return xmind
    }

    private var pngData: Data {
        NSImage(size: NSSize(width: 30, height: 20), flipped: false) { r in
            NSColor.systemTeal.setFill()
            r.fill()
            return true
        }.pngData!
    }

    func testXMind8Workbook() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <xmap-content xmlns="urn:xmind:xmap:xmlns:content:2.0" xmlns:fo="http://www.w3.org/1999/XSL/Format"
            xmlns:svg="http://www.w3.org/2000/svg" xmlns:xhtml="http://www.w3.org/1999/xhtml"
            xmlns:xlink="http://www.w3.org/1999/xlink" version="2.0">
          <sheet id="s1">
            <topic id="root" structure-class="org.xmind.ui.map.unbalanced">
              <title>中心</title>
              <children>
                <topics type="detached"><topic id="free"><title>自由主题</title></topic></topics>
                <topics type="attached">
                  <topic id="a" xlink:href="https://xmind.net">
                    <title>A</title>
                    <xhtml:img svg:height="40" svg:width="60" xhtml:src="xap:attachments/pic.png"/>
                    <marker-refs><marker-ref marker-id="c_simbol-right"/><marker-ref marker-id="priority-1"/></marker-refs>
                  </topic>
                  <topic id="b" branch="folded">
                    <title>B</title>
                    <notes><plain>备注</plain></notes>
                    <children><topics type="attached"><topic id="b1"><title>B1</title></topic></topics></children>
                  </topic>
                  <topic id="c" xlink:href="xap:attachments/doc.txt"><title>doc.txt</title></topic>
                </topics>
                <topics type="summary"><topic id="sum"><title>概要</title></topic></topics>
              </children>
              <boundaries><boundary id="bd" range="(1,1)"/></boundaries>
              <summaries><summary id="s" range="(0,2)" topic-id="sum"/></summaries>
            </topic>
            <title>画布 1</title>
            <relationships><relationship end1="a" end2="c" id="r1"><title>关联</title></relationship></relationships>
          </sheet>
        </xmap-content>
        """
        let comments = """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?><comments xmlns="urn:xmind:xmap:xmlns:comments:2.0" version="2.0">\
        <comment author="老王" object-id="b" time="1528439573826"><content>第一条&#13;
        换行</content></comment><comment author="老王" object-id="b" time="1528439589534"><content>第二条</content></comment></comments>
        """
        let url = try makeXMind(["content.xml": Data(xml.utf8), "comments.xml": Data(comments.utf8),
                                 "attachments/pic.png": pngData, "attachments/doc.txt": Data("附件".utf8)])
        let result = try XCTUnwrap(XMindImporter.importFile(at: url).first)
        let root = result.map.root
        XCTAssertEqual(result.title, "画布 1")
        // 普通子主题在前，概要、自由主题接在后面
        XCTAssertEqual(root.children.map(\.title), ["A", "B", "doc.txt", "概要", "自由主题"])
        let a = root.children[0], b = root.children[1], c = root.children[2]
        XCTAssertEqual(a.link, "https://xmind.net")
        XCTAssertEqual(a.image?.width, 60)
        XCTAssertEqual(a.image?.height, 40)
        XCTAssertEqual(Set(a.markers), [MarkerID("symbol-check"), MarkerID("priority-1")])
        XCTAssertTrue(b.collapsed)
        // 批注接在原有备注后面
        XCTAssertTrue(b.note.hasPrefix("备注\n\n" + L("Comments") + "\n• 老王, "), b.note)
        XCTAssertTrue(b.note.contains(": 第一条\n换行\n• 老王, "), b.note)
        XCTAssertTrue(b.note.hasSuffix(": 第二条"), b.note)
        XCTAssertEqual(b.style.boundary, true, "range (1,1) 框住第二个子主题")
        XCTAssertNil(a.style.boundary)
        XCTAssertEqual(c.attachments.map(\.name), ["doc.txt"])
        XCTAssertEqual(result.map.relationships.count, 1)
        XCTAssertEqual(result.map.relationships.first?.from, a.id)
        XCTAssertEqual(result.map.relationships.first?.to, c.id)
        XCTAssertEqual(result.map.relationships.first?.title, "关联")
        XCTAssertTrue(root.resourceIDs().isSubset(of: Set(result.resources.keys)), "引用的图片和附件都要带上数据")
    }

    func testXMindJSONSummaryCalloutAndBoundaries() throws {
        let json = """
        [{"id":"s1","class":"sheet","title":"S","rootTopic":{"id":"r","title":"R",
          "structureClass":"org.xmind.ui.map.clockwise",
          "boundaries":[{"id":"x","range":"master"},{"id":"y","range":"(0,1)"}],
          "summaries":[{"id":"z","range":"(0,2)","topicId":"su"}],
          "children":{
            "attached":[
              {"id":"a","title":"A","markers":[{"markerId":"c_symbol_like"},{"markerId":"task-oct"}],
               "image":{"src":"xap:resources/pic.png"},
               "children":{"callout":[{"id":"co","title":"标注"}]}},
              {"id":"b","title":"B"},
              {"id":"c","title":"C"}],
            "summary":[{"id":"su","title":"概要"}],
            "detached":[{"id":"f","title":"自由主题"}]}}}]
        """
        let url = try makeXMind(["content.json": Data(json.utf8), "resources/pic.png": pngData,
                                 // 新版文件里也带着一个给旧版本看的 content.xml，必须优先读 content.json
                                 "content.xml": Data("<xmap-content><sheet><topic><title>旧版提示</title></topic></sheet></xmap-content>".utf8)])
        let map = try XCTUnwrap(XMindImporter.importFile(at: url).first).map
        XCTAssertEqual(map.root.title, "R")
        XCTAssertEqual(map.root.children.map(\.title), ["A", "B", "C", "概要", "自由主题"])
        XCTAssertEqual(map.root.style.boundary, true, "master 外框框住主题本身")
        XCTAssertEqual(map.root.children.map { $0.style.boundary ?? false }, [true, true, false, false, false])
        let a = map.root.children[0]
        XCTAssertEqual(a.children.map(\.title), ["标注"])
        XCTAssertEqual(Set(a.markers), [MarkerID("symbol-like"), MarkerID("task-25")])
        XCTAssertEqual(a.image?.width, 30)
    }

    func testOPMLFromOtherOutliners() throws {
        let opml = """
        <?xml version="1.0"?>
        <opml version="2.0"><head><title>
              Page
            </title></head><body>
          <outline text="&#10;&#10;"/>
          <outline text="**Hello, everyone!**" _note="	  note line&#10;"/>
          <outline text="The &lt;b&gt;bold&lt;/b&gt; and &lt;i&gt;italic&lt;/i&gt;"/>
          <outline _complete="true" text="Done task"/>
          <outline text="a &lt; b"/>
        </body></opml>
        """
        let root = try OPMLImporter.parse(Data(opml.utf8), defaultTitle: "x").map.root
        XCTAssertEqual(root.title, "Page")
        XCTAssertEqual(root.children.map(\.title), ["Hello, everyone!", "The bold and italic", "Done task", "a < b"])
        XCTAssertEqual(root.children[0].style.bold, true)
        XCTAssertEqual(root.children[0].note, "note line")
        XCTAssertEqual(root.children[2].markers, [MarkerID("task-100")])
        XCTAssertNil(root.children[1].style.bold)
    }

    func testDamagedOPMLExplainsWhere() {
        let opml = "<?xml version=\"1.0\"?>\n<opml version=\"2.0\">\n<body>\n<outline text=\"a\">\n</body>\n</opml>"
        XCTAssertThrowsError(try OPMLImporter.parse(Data(opml.utf8), defaultTitle: "x")) { error in
            let e = error as NSError
            XCTAssertEqual(e.localizedDescription, L("This OPML file is damaged and could not be read."))
            // 第 5 行的 </body> 和第 4 行的 <outline> 对不上；解析器发现错误时可能已经读到下一行
            XCTAssertTrue([5, 6].map { LF("The problem is near line %d.", $0) }.contains(e.localizedRecoverySuggestion ?? ""),
                          e.localizedRecoverySuggestion ?? "")
        }
    }
}
