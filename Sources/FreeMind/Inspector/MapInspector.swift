import AppKit
import SwiftUI

/// 导图页：布局、风格、连线。
struct MapInspector: View {
    let editor: MapEditor
    @State private var themeLibrary = ThemeLibrary.shared
    @State private var showingThemes = false
    @State private var savingTheme = false
    @State private var newThemeName = ""

    private static let fontFamilies: [(String, String?)] = {
        let candidates: [(String, String?)] = [
            (L("System"), nil), ("PingFang SC", "PingFang SC"), ("Songti SC", "Songti SC"), ("Kaiti SC", "Kaiti SC"),
            ("Hiragino Sans GB", "Hiragino Sans GB"), ("Helvetica Neue", "Helvetica Neue"), ("Avenir Next", "Avenir Next"),
            ("Georgia", "Georgia"), ("Baskerville", "Baskerville"), ("Menlo", "Menlo"), ("Chalkboard SE", "Chalkboard SE"),
        ]
        let available = Set(NSFontManager.shared.availableFontFamilies)
        return candidates.filter { $0.1 == nil || available.contains($0.1!) }
    }()

    private static let backgrounds = ["#FFFFFF", "#FAF7F0", "#F5F5F4", "#F1F5F9", "#EEF6FF", "#F0FAF4", "#FFF7ED", "#FDF2F8",
                                      "#E5E7EB", "#94A3B8", "#475569", "#2B2F36", "#1F2328", "#111827", "#0F172A", "#000000"]

    var body: some View {
        let map = editor.map
        let theme = map.theme

        InspectorSection(title: L("Layout")) {
            InspectorRow(title: L("Structure")) {
                Picker(L("Structure"), selection: Binding(get: { map.structure }, set: { editor.setStructure($0) })) {
                    ForEach(MapStructure.allCases) { s in
                        Label(s.title, systemImage: s.symbolName).tag(s)
                    }
                }
                .inspectorPopUp()
            }
            InspectorRow(title: L("Spacing")) {
                Picker(L("Spacing"), selection: Binding(get: { map.spacing }, set: { editor.setSpacing($0) })) {
                    ForEach(MapSpacing.allCases) { Text($0.title).tag($0) }
                }
                .inspectorPopUp()
            }
            InspectorRow(title: L("Topic Width")) {
                Slider(value: Binding(get: { map.topicMaxWidth }, set: { editor.setTopicMaxWidth($0.rounded()) }),
                       in: 120...600, step: 10)
                Text("\(Int(map.topicMaxWidth))").monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
        }

        InspectorSection(title: L("Theme")) {
            Button { showingThemes = true } label: {
                HStack(spacing: 10) {
                    Image(nsImage: ThemePreview.image(for: theme))
                        .resizable()
                        .aspectRatio(5 / 3, contentMode: .fit)
                        .frame(width: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(theme.displayName).lineLimit(1)
                        Text(L("Change Theme…")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingThemes, arrowEdge: .leading) {
                ScrollView {
                    ThemeGrid(selectedID: theme.id, themes: themeLibrary.allThemes, columns: 2,
                              onSelect: { editor.setTheme($0) },
                              onDelete: { themeLibrary.delete(id: $0.id) })
                        .padding(12)
                }
                .frame(width: 340, height: 460)
            }

            InspectorRow(title: L("Branch Colors")) {
                PaletteButton(current: theme.branchColors.map(\.rawValue)) { colors in
                    update { $0.branchColors = colors.map { Paint($0) } }
                }
            }
            InspectorRow(title: L("Background")) {
                ColorButton(shown: theme.backgroundColor, current: theme.background, presets: Self.backgrounds,
                            allowDefault: false) { paint, live in
                    guard let paint else { return }
                    update(coalesce: live ? "background" : nil) { $0.background = paint }
                }
            }
            InspectorRow(title: L("Font")) {
                Picker(L("Font"), selection: Binding(
                    get: { theme.fontFamily ?? "" },
                    set: { v in update { $0.fontFamily = v.isEmpty ? nil : v } })) {
                    ForEach(Self.fontFamilies, id: \.0) { title, family in
                        Text(title).tag(family ?? "")
                    }
                }
                .inspectorPopUp()
            }
        }

        InspectorSection(title: L("Lines")) {
            InspectorRow(title: L("Line Style")) {
                Picker(L("Line Style"), selection: Binding(
                    get: { map.lineStyle?.rawValue ?? "theme" },
                    set: { editor.setLineStyle(LineStyle(rawValue: $0)) })) {
                    Text(L("Theme Default")).tag("theme")
                    Divider()
                    ForEach(LineStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .inspectorPopUp()
            }
            InspectorRow(title: L("Line Width")) {
                Slider(value: Binding(
                    get: { theme.lineWidth },
                    set: { v in update(coalesce: "line-width") { $0.lineWidth = v; $0.mainLineWidth = v + 1 } }),
                       in: 0.5...5, step: 0.5)
                Text(String(format: "%.1f", theme.lineWidth)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
            InspectorRow(title: L("Relationships")) {
                Toggle(L("Show Relationships"), isOn: Binding(
                    get: { !map.relationshipsHidden },
                    set: { editor.setRelationshipsHidden(!$0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .help(L("Show or hide relationships (⌥⌘L)"))
            }
        }

        InspectorFooter {
            Button(L("Save as Custom Theme…")) {
                newThemeName = LF("%@ Copy", map.theme.displayName)
                savingTheme = true
            }
            Button(L("Reset All Topic Styles")) { editor.clearAllTopicStyles() }
                .help(L("Remove individual formatting so every topic follows the theme."))
        }
        .alert(L("Save Custom Theme"), isPresented: $savingTheme) {
            TextField(L("Theme Name"), text: $newThemeName)
            Button(L("Save")) {
                let name = newThemeName.trimmingCharacters(in: .whitespaces)
                let saved = themeLibrary.add(editor.map.theme, name: name.isEmpty ? L("My Theme") : name)
                editor.setTheme(saved)
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("The theme will be available for all your maps."))
        }
    }

    /// 修改当前导图内嵌的主题。
    private func update(coalesce: String? = nil, _ body: (inout Theme) -> Void) {
        var theme = editor.map.theme
        body(&theme)
        editor.updateTheme(theme, coalesce: coalesce)
    }
}

/// 分支配色按钮：显示当前配色，点击弹出可选配色。
struct PaletteButton: View {
    let current: [String]
    let onPick: ([String]) -> Void
    @State private var showing = false

    static let palettes: [(String, [String])] = [
        ("Rainbow", ["#E5484D", "#F76B15", "#E9A800", "#30A46C", "#12A594", "#0090FF", "#6E56CF", "#D6409F"]),
        ("Calm", ["#3B82F6", "#F59E0B", "#10B981", "#8B5CF6", "#EF4444", "#06B6D4"]),
        ("Ocean", ["#1E6FD9", "#0E9AA7", "#3D5A80", "#2A9D8F", "#4361EE", "#118AB2"]),
        ("Earth", ["#2D6A4F", "#BC6C25", "#588157", "#7F5539", "#386641", "#9C6644"]),
        ("Warm", ["#E76F51", "#D62828", "#F77F00", "#C9184A", "#9D4EDD", "#E9A800"]),
        ("Pastel", ["#F28AB2", "#6CC5F0", "#9D8DF1", "#5FCF92", "#F7B267", "#F4845F"]),
        ("Mono", ["#3A3A3A"]),
    ]

    var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 5) {
                PaletteStrip(colors: current).frame(width: 64, height: 14)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
            .padding(.trailing, 6)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Self.palettes, id: \.0) { name, colors in
                    let selected = current.map { $0.uppercased() } == colors
                    Button {
                        onPick(colors)
                        showing = false
                    } label: {
                        HStack(spacing: 10) {
                            PaletteStrip(colors: colors).frame(width: 110, height: 14)
                            Text(L(name))
                            Spacer(minLength: 0)
                            if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.15) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .frame(width: 230)
        }
    }
}

/// 一排颜色条。
struct PaletteStrip: View {
    let colors: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, hex in Rectangle().fill(Color(hex: hex)) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.15), lineWidth: 1))
    }
}

/// 主题缩略图网格。
struct ThemeGrid: View {
    let selectedID: String
    let themes: [Theme]
    var columns = 2
    let onSelect: (Theme) -> Void
    var onDelete: ((Theme) -> Void)?

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
            ForEach(themes) { theme in
                let selected = theme.id == selectedID
                Button { onSelect(theme) } label: {
                    VStack(spacing: 4) {
                        Image(nsImage: ThemePreview.image(for: theme))
                            .resizable()
                            .aspectRatio(5 / 3, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(selected ? Color.accentColor : Color.black.opacity(0.12), lineWidth: selected ? 2.5 : 1))
                        Text(theme.displayName).font(.caption).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if let onDelete, ThemeLibrary.shared.isCustom(theme.id) {
                        Button(L("Delete Theme"), role: .destructive) { onDelete(theme) }
                    }
                }
            }
        }
    }
}

/// 主题预览图（示例小导图），按主题内容缓存。
enum ThemePreview {
    private static var cache: [String: NSImage] = [:]

    static func image(for theme: Theme, structure: MapStructure = .mindMap, size: CGSize = CGSize(width: 250, height: 150)) -> NSImage {
        let key = (try? JSONEncoder().encode(theme)).map { "\($0.hashValue)" } ?? theme.id
        let cacheKey = "\(key)|\(structure.rawValue)|\(size.width)"
        if let cached = cache[cacheKey] { return cached }
        let root = Topic(title: L("Theme"), children: [
            Topic(title: L("Idea"), children: [Topic(title: L("Detail")), Topic(title: L("Detail"))]),
            Topic(title: L("Plan"), children: [Topic(title: L("Step"))]),
            Topic(title: L("Goal"), children: [Topic(title: L("Detail"))]),
            Topic(title: L("Notes"), children: [Topic(title: L("Step")), Topic(title: L("Step"))]),
        ])
        let map = MindMap(root: root, structure: structure, theme: theme, spacing: .compact)
        let layout = LayoutEngine(map: map, measurer: TopicMeasurer()).run()
        let image = ImageExporter.thumbnail(layout: layout, size: size)
        cache[cacheKey] = image
        return image
    }
}
