import AppKit
import XCTest
@testable import FreeMind

/// 生成 README 用的示例导图（docs/samples）和拼图（主题 / 结构一览）。
/// 只有设置了环境变量 FREEMIND_SHOWCASE_DIR 才会运行（xcodebuild 里用 TEST_RUNNER_FREEMIND_SHOWCASE_DIR 传入）。
/// 文字跟随测试宿主的语言：AppleLanguages 为 zh-Hans 时生成中文版。
final class ShowcaseTests: XCTestCase {
    private func outputDir() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["FREEMIND_SHOWCASE_DIR"], !path.isEmpty else {
            throw XCTSkip("FREEMIND_SHOWCASE_DIR not set")
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testWriteShowcase() throws {
        let dir = try outputDir()

        // 示例导图：先写的排在“最近打开”后面
        try write(BuiltinTemplates.orgChart(), theme: .business, name: LT("Team", "团队架构"), to: dir)
        try write(BuiltinTemplates.bookNotes(), theme: .paper, name: LT("Book Notes", "读书笔记"), to: dir)
        var weekly = BuiltinTemplates.weeklyPlan()
        weekly.structure = .tree
        try write(weekly, theme: .fresh, name: LT("Weekly Plan", "本周计划"), to: dir)
        var plan = BuiltinTemplates.projectPlan()
        plan.structure = .logicRight
        try write(plan, theme: .ocean, name: LT("Project Plan", "项目计划"), to: dir)
        try writeLaunchPlan(to: dir)

        // 结构一览
        let structures: [(MapStructure, String)] = MapStructure.allCases.map { ($0, $0.title) }
        try grid(structures.map { s, title -> (MindMap, String) in
            var map = Self.structureSample()
            map.structure = s
            return (map, title)
        }, columns: 3, cell: CGSize(width: 420, height: 270)).write(to: dir.appendingPathComponent("structures.png"))

        // 风格一览
        let themes: [Theme] = [.classic, .rainbow, .fresh, .ocean, .sunset, .candy, .business, .paper, .midnight]
        try grid(themes.map { theme -> (MindMap, String) in
            var map = Self.structureSample()
            map.theme = theme
            return (map, theme.displayName)
        }, columns: 3, cell: CGSize(width: 420, height: 250)).write(to: dir.appendingPathComponent("themes.png"))
    }

    // MARK: - 主图：新品发布计划

    private func writeLaunchPlan(to dir: URL) throws {
        let doc = MindMapDocument()

        let budgetCSV = Data("item,amount\nads,30000\nevents,12000\ntools,3000\n".utf8)
        let budgetName = LT("budget.csv", "预算.csv")
        let budgetID = doc.attachments.add(data: budgetCSV, name: budgetName)
        let chart = Self.illustration(symbol: "chart.line.uptrend.xyaxis", from: .systemTeal, to: .systemBlue)
        let chartID = doc.attachments.add(data: chart, name: "growth.png")

        let release = Topic(title: LT("Launch — June 18", "正式发布 · 6 月 18 日"), markers: [MarkerID("task-50")])
        let press = Topic(title: LT("Press coverage", "媒体报道"), markers: [MarkerID("star-orange")])

        let goals = Topic(title: LT("Goals", "目标"), children: [
            Topic(title: LT("10k users in month one", "首月 1 万用户"),
                  image: TopicImage(id: chartID, name: "growth.png", width: 96, height: 60),
                  markers: [MarkerID("priority-1"), MarkerID("flag-red")]),
            press,
        ])
        let timeline = Topic(title: LT("Timeline", "时间安排"), children: [
            Topic(title: LT("Beta — May", "内测 · 5 月"), markers: [MarkerID("task-100")]),
            release,
            Topic(title: LT("Review — July", "复盘 · 7 月"), markers: [MarkerID("task-0")]),
        ])
        let marketing = Topic(title: LT("Marketing", "市场"), markers: [MarkerID("symbol-person")], labels: [LT("Carol", "阿杰")])
        let team = Topic(title: LT("Team", "团队"), children: [
            Topic(title: LT("Design", "设计"), markers: [MarkerID("symbol-person")], labels: [LT("Alice", "小林")]),
            Topic(title: LT("Engineering", "研发"), markers: [MarkerID("symbol-person")], labels: [LT("Bob", "老周")]),
            marketing,
        ])
        var channels = Topic(title: LT("Channels", "推广渠道"), children: [
            Topic(title: LT("Website", "官网"), link: "https://example.com"),
            Topic(title: LT("Social media", "社交媒体")),
            Topic(title: LT("Newsletter", "邮件订阅")),
        ])
        channels.style.boundary = true
        let risks = Topic(title: LT("Risks", "风险"), children: [
            Topic(title: LT("App review delay", "审核延期"),
                  note: LT("Submit for review two weeks early.", "提前两周提交审核。"),
                  markers: [MarkerID("symbol-important")]),
            Topic(title: LT("Server load", "服务器压力"), markers: [MarkerID("symbol-question")]),
        ])
        let budget = Topic(title: LT("Budget", "预算"), children: [
            Topic(title: LT("Ads", "广告")), Topic(title: LT("Events", "活动")), Topic(title: LT("Tools", "工具")),
        ], collapsed: true, attachments: [Attachment(id: budgetID, name: budgetName, size: Int64(budgetCSV.count))],
                           markers: [MarkerID("symbol-money")])

        var map = MindMap(root: Topic(title: LT("Product Launch", "新品发布"),
                                      children: [goals, timeline, team, channels, risks, budget]))
        map.relationships = [Relationship(from: marketing.id, to: channels.id, title: LT("owns", "负责"))]
        doc.editor.load(map)

        let url = dir.appendingPathComponent(LT("Product Launch", "新品发布") + ".fmind")
        try? FileManager.default.removeItem(at: url)
        try doc.write(to: url, ofType: DocumentTypes.map)
        // 打开时选中“正式发布”，格式面板有内容可看
        let content = DocumentContent(map: map, view: ViewState(zoom: 1, centerX: 0, centerY: 0, selection: [release.id]))
        try content.encoded().write(to: url.appendingPathComponent(DocumentContent.contentFileName))
    }

    private func write(_ map: MindMap, theme: Theme, name: String, to dir: URL) throws {
        var map = map
        map.theme = theme
        let doc = MindMapDocument()
        doc.editor.load(map)
        let url = dir.appendingPathComponent(name + ".fmind")
        try? FileManager.default.removeItem(at: url)
        try doc.write(to: url, ofType: DocumentTypes.map)
    }

    /// 结构 / 风格拼图用的小导图。
    private static func structureSample() -> MindMap {
        MindMap(root: Topic(title: LT("Trip to Japan", "日本旅行"), children: [
            Topic(title: LT("Tokyo", "东京"), children: [Topic(title: LT("Museums", "博物馆")), Topic(title: LT("Food", "美食"))]),
            Topic(title: LT("Kyoto", "京都"), children: [Topic(title: LT("Temples", "寺庙"))]),
            Topic(title: LT("Budget", "预算"), children: [Topic(title: LT("Hotels", "住宿")), Topic(title: LT("Rail pass", "火车通票"))]),
            Topic(title: LT("Packing", "行李"), children: [Topic(title: LT("Camera", "相机"))]),
        ]), spacing: .compact)
    }

    /// 主题图片用的小插图：渐变底 + SF Symbol。
    private static func illustration(symbol: String, from: NSColor, to: NSColor) -> Data {
        let size = NSSize(width: 192, height: 120)
        let image = NSImage(size: size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18).addClip()
            NSGradient(starting: from, ending: to)?.draw(in: rect, angle: 35)
            let config = NSImage.SymbolConfiguration(pointSize: 56, weight: .semibold)
                .applying(.init(paletteColors: [.white]))
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let s = glyph.size
                glyph.draw(in: CGRect(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2, width: s.width, height: s.height))
            }
            return true
        }
        return image.pngData!
    }

    /// 把几张导图缩略图排成网格，下面写名称。背景透明，GitHub 浅色 / 深色页面都能看。
    private func grid(_ items: [(MindMap, String)], columns: Int, cell: CGSize) throws -> Data {
        let captionHeight: CGFloat = 34, gap: CGFloat = 24, scale: CGFloat = 2
        // 四周留一点边，卡片描边不被图片边缘切掉
        let margin: CGFloat = 2
        let rows = (items.count + columns - 1) / columns
        let size = CGSize(width: CGFloat(columns) * cell.width + CGFloat(columns - 1) * gap + margin * 2,
                          height: CGFloat(rows) * (cell.height + captionHeight) + CGFloat(rows - 1) * gap + margin * 2)
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                                 pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for (index, (map, title)) in items.enumerated() {
            let column = index % columns, row = index / columns
            let top = margin + CGFloat(row) * (cell.height + captionHeight + gap)
            let rect = CGRect(x: margin + CGFloat(column) * (cell.width + gap), y: size.height - top - cell.height,
                              width: cell.width, height: cell.height)
            let layout = LayoutEngine(map: map, measurer: TopicMeasurer()).run()
            let image = ImageExporter.thumbnail(layout: layout, size: cell)
            let card = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
            NSGraphicsContext.saveGraphicsState()
            card.addClip()
            image.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
            NSColor(white: 0.5, alpha: 0.35).setStroke()
            card.lineWidth = 1
            card.stroke()
            let caption = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor(srgbRed: 0.45, green: 0.48, blue: 0.53, alpha: 1),
            ])
            let textSize = caption.size()
            caption.draw(at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.minY - 8 - textSize.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
