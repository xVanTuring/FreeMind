import SwiftUI
import XCTest
@testable import FreeMind

/// 把各种结构 / 主题 / 模板渲染成 PNG，供人工目检。
/// 只有设置了环境变量 FREEMIND_RENDER_DIR 才会运行（xcodebuild 里用 TEST_RUNNER_FREEMIND_RENDER_DIR 传入）。
final class RenderSnapshotTests: XCTestCase {
    private func outputDir() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["FREEMIND_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("FREEMIND_RENDER_DIR not set")
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func render(_ map: MindMap, to url: URL) throws {
        let layout = LayoutEngine(map: map, measurer: TopicMeasurer()).run()
        let data = try XCTUnwrap(ImageExporter.pngData(layout: layout, images: { _ in nil }, scale: 1))
        try data.write(to: url)
    }

    func testRenderStructures() throws {
        let dir = try outputDir()
        for structure in MapStructure.allCases {
            var map = BuiltinTemplates.gettingStarted()
            map.structure = structure
            try render(map, to: dir.appendingPathComponent("structure-\(structure.rawValue).png"))
        }
    }

    func testRenderThemes() throws {
        let dir = try outputDir()
        for theme in Theme.builtins {
            var map = BuiltinTemplates.meetingNotes()
            map.theme = theme
            map.structure = .mindMap
            map.root.children[0].collapsed = true
            map.root.children[1].style.boundary = true
            map.root.children[2].children[0].labels = ["label", "标签"]
            map.root.children[2].children[0].note = "note"
            map.root.children[2].children[0].link = "https://example.com"
            try render(map, to: dir.appendingPathComponent("theme-\(theme.id).png"))
        }
    }

    /// 联系线标签密集的情况：左右分支之间连很多条带标签的联系线。
    /// relationship-labels.png 是自动避让的效果，relationship-labels-midpoint.png 是全部放在中点（避让前）的对照。
    func testRenderRelationshipLabels() throws {
        let dir = try outputDir()
        var map = MindMap(root: Topic(title: "软件质量", children: [
            Topic(title: "质量属性", children: ["正确性", "可靠性", "效率", "可维护性"].map { Topic(title: $0) }),
            Topic(title: "评审与测试", children: ["需求评审", "设计评审", "单元测试", "覆盖测试"].map { Topic(title: $0) }),
            Topic(title: "度量", children: ["复杂性", "模块性", "规模"].map { Topic(title: $0) }),
            Topic(title: "过程", children: ["原型", "迭代", "维护"].map { Topic(title: $0) }),
        ]))
        let topic = { (title: String) in map.allTopics.first { $0.title == title }!.id }
        let pairs = [("正确性", "原型", "建立原型可减少完善性维护"), ("可靠性", "迭代", "独立测试小组"),
                     ("效率", "复杂性", "MBT 常用状态图生成用例"), ("可维护性", "模块性", "做覆盖测试先画流程图"),
                     ("单元测试", "维护", "单元测试以详细设计文档为指导"), ("需求评审", "规模", "评审发现的问题"),
                     // 两端相同的几条线，标签默认会叠在同一个位置
                     ("效率", "复杂性", "复杂度影响效率"), ("效率", "复杂性", "状态图")]
        map.relationships = pairs.map { Relationship(from: topic($0.0), to: topic($0.1), title: $0.2) }
        try render(map, to: dir.appendingPathComponent("relationship-labels.png"))
        for i in map.relationships.indices { map.relationships[i].labelPosition = 0.5 }
        try render(map, to: dir.appendingPathComponent("relationship-labels-midpoint.png"))
    }

    /// 生成一份带附件、图片、折叠分支的示例文档，供手工打开测试。
    func testWriteSampleDocument() throws {
        let dir = try outputDir()
        let doc = MindMapDocument()
        var map = BuiltinTemplates.gettingStarted()
        let attachmentID = doc.attachments.add(data: Data("示例附件内容".utf8), name: "示例附件.txt")
        map.root.children[0].attachments = [Attachment(id: attachmentID, name: "示例附件.txt", size: 18)]
        let png = NSImage(size: NSSize(width: 120, height: 80), flipped: false) { r in
            NSGradient(starting: .systemTeal, ending: .systemIndigo)?.draw(in: r, angle: 30)
            return true
        }.pngData!
        let imageID = doc.attachments.add(data: png, name: "示例图片.png")
        map.root.children[1].image = TopicImage(id: imageID, name: "示例图片.png", width: 120, height: 80)
        doc.editor.load(map)
        let url = dir.appendingPathComponent("sample.fmind")
        try? FileManager.default.removeItem(at: url)
        try doc.write(to: url, ofType: DocumentTypes.map)
    }

    /// 检查器各页、模板库、设置窗口的离屏截图。
    func testRenderPanels() throws {
        let dir = try outputDir()
        let doc = MindMapDocument()
        var map = BuiltinTemplates.gettingStarted()
        map.relationships = [Relationship(from: map.root.children[0].id, to: map.root.children[1].id, title: "示例")]
        doc.editor.load(map)
        doc.editor.select(map.root.children[3].children[5].id)

        func snapshot<V: View>(_ view: V, size: CGSize, name: String, dark: Bool = false) throws {
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
            hosting.frame = CGRect(origin: .zero, size: size)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent(name))
        }

        for tab in InspectorTab.allCases {
            UserDefaults.standard.set(tab.rawValue, forKey: "inspectorTab")
            try snapshot(InspectorView(editor: doc.editor), size: CGSize(width: 290, height: 1100), name: "inspector-\(tab.rawValue).png")
            try snapshot(InspectorView(editor: doc.editor), size: CGSize(width: 260, height: 1100),
                         name: "inspector-\(tab.rawValue)-dark.png", dark: true)
        }
        doc.editor.selectRelationship(map.relationships[0].id)
        UserDefaults.standard.set(InspectorTab.style.rawValue, forKey: "inspectorTab")
        try snapshot(InspectorView(editor: doc.editor), size: CGSize(width: 290, height: 700), name: "inspector-relationship.png")
        try snapshot(ColorPalette(current: Paint("#E5484D"), presets: ColorPalette.soft + ColorPalette.strong,
                                  allowNone: true, allowDefault: true, onPick: { _ in }, onMore: {}),
                     size: CGSize(width: 226, height: 190), name: "popover-colors.png", dark: true)
        try snapshot(ScrollView { ThemeGrid(selectedID: "classic", themes: ThemeLibrary.shared.allThemes, onSelect: { _ in }).padding(12) }
                        .frame(width: 340, height: 460),
                     size: CGSize(width: 340, height: 460), name: "popover-themes.png")
        var recents: [URL] = []
        for (name, make) in [("项目计划", BuiltinTemplates.projectPlan), ("Weekly Plan", BuiltinTemplates.weeklyPlan)] {
            let recentDoc = MindMapDocument()
            recentDoc.editor.load(make())
            let url = dir.appendingPathComponent("\(name).fmind")
            try? FileManager.default.removeItem(at: url)
            try recentDoc.write(to: url, ofType: DocumentTypes.map)
            recents.append(url)
        }
        try snapshot(WelcomeView(recents: recents, close: {}), size: CGSize(width: 800, height: 480), name: "welcome.png")
        try snapshot(WelcomeView(recents: [], close: {}), size: CGSize(width: 800, height: 480), name: "welcome-empty-dark.png", dark: true)
        try snapshot(TemplateGalleryView(close: {}), size: CGSize(width: 940, height: 680), name: "gallery.png")
        try snapshot(GeneralSettings(), size: CGSize(width: 500, height: 680), name: "settings-general.png", dark: true)
        try snapshot(ExportSettings(), size: CGSize(width: 500, height: 420), name: "settings-export.png")
        try snapshot(LibrarySettings(), size: CGSize(width: 500, height: 360), name: "settings-library.png")
        try snapshot(AgentSettings(), size: CGSize(width: 500, height: 440), name: "settings-agent.png")
        try snapshot(AgentSettings(), size: CGSize(width: 500, height: 440), name: "settings-agent-dark.png", dark: true)
        try snapshot(KeyboardShortcutsView(), size: CGSize(width: 560, height: 900), name: "shortcuts.png")
    }

    func testRenderTemplates() throws {
        let dir = try outputDir()
        for template in TemplateLibrary.shared.builtinTemplates() {
            try render(template.make!(), to: dir.appendingPathComponent("template-\(template.id).png"))
        }
    }
}
