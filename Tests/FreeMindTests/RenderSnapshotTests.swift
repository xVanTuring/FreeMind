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
        try snapshot(TemplateGalleryView(close: {}), size: CGSize(width: 940, height: 680), name: "gallery.png")
        try snapshot(SettingsView(), size: CGSize(width: 560, height: 440), name: "settings.png")
        try snapshot(KeyboardShortcutsView(), size: CGSize(width: 560, height: 900), name: "shortcuts.png")
    }

    func testRenderTemplates() throws {
        let dir = try outputDir()
        for template in TemplateLibrary.shared.builtinTemplates() {
            try render(template.make!(), to: dir.appendingPathComponent("template-\(template.id).png"))
        }
    }
}
