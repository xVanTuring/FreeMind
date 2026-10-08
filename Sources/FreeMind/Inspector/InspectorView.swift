import AppKit
import SwiftUI

enum InspectorTab: String, CaseIterable, Identifiable {
    case style, map, markers, content

    var id: String { rawValue }

    var title: String {
        switch self {
        case .style: return L("Style")
        case .map: return L("Map")
        case .markers: return L("Markers")
        case .content: return L("Content")
        }
    }
}

/// 右侧检查器（格式面板）。
struct InspectorView: View {
    @Bindable var editor: MapEditor
    @AppStorage("inspectorTab") private var tab: InspectorTab = .style

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(InspectorTab.allCases) { t in
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()
            // 用 GeometryReader 把内容宽度钉死在面板宽度，避免个别控件把内容撑宽后整体被裁掉
            GeometryReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        switch tab {
                        case .style: TopicStyleInspector(editor: editor)
                        case .map: MapInspector(editor: editor)
                        case .markers: MarkersInspector(editor: editor)
                        case .content: ContentInspector(editor: editor)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .frame(width: proxy.size.width, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 260, idealWidth: 290)
    }
}

// MARK: - 通用小组件

/// 一组设置：小标题 + 内容，底部一条分隔线。
struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// 一行设置：左边名称，右边控件。
struct InspectorRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            Text(title).lineLimit(1).fixedSize().layoutPriority(1)
            Spacer(minLength: 8)
            content
        }
        .frame(minHeight: 24)
    }
}

extension View {
    /// 检查器里的弹出菜单：隐藏名称、靠右；限制最大宽度，空间不够时缩短，不挤掉左边的名称。
    func inspectorPopUp(width: CGFloat = 170) -> some View {
        labelsHidden().frame(maxWidth: width, alignment: .trailing)
    }
}

/// 一组设置底部的按钮行。
struct InspectorFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
    }
}

struct EmptySelectionHint: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cursorarrow.click.2").font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(L("Select a topic first")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex) ?? .gray)
    }
}

// MARK: - 颜色

/// 颜色按钮：显示画布上实际的颜色，点击弹出色板。
struct ColorButton: View {
    /// 画布上实际显示的颜色，nil 表示不绘制。
    let shown: NSColor?
    /// 单独设置的值，nil 表示跟随风格。
    let current: Paint?
    var presets: [String] = ColorPalette.strong
    var allowNone = false
    var allowDefault = true
    /// 第二个参数为 true 表示来自颜色面板的连续修改，调用方应合并撤销。
    let onChange: (Paint?, Bool) -> Void
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 5) {
                ColorChip(color: shown).frame(width: 30, height: 16)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .leading) {
            ColorPalette(current: current, presets: presets, allowNone: allowNone, allowDefault: allowDefault,
                         onPick: { paint in
                             onChange(paint, false)
                             showing = false
                         },
                         onMore: {
                             showing = false
                             ColorPanelBridge.shared.show(initial: shown) { onChange(Paint(color: $0), true) }
                         })
        }
    }
}

/// 颜色小方块；nil 画成白底红斜线（无）。
struct ColorChip: View {
    let color: NSColor?

    var body: some View {
        ZStack {
            if let color {
                RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: color))
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color.white)
                GeometryReader { g in
                    Path { p in
                        p.move(to: CGPoint(x: 3, y: g.size.height - 3))
                        p.addLine(to: CGPoint(x: g.size.width - 3, y: 3))
                    }
                    .stroke(Color.red, lineWidth: 1.5)
                }
            }
            RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
        }
    }
}

/// 弹出色板：跟随风格 / 无 / 预设颜色 / 更多颜色。
struct ColorPalette: View {
    let current: Paint?
    let presets: [String]
    let allowNone: Bool
    let allowDefault: Bool
    let onPick: (Paint?) -> Void
    let onMore: () -> Void

    private static let columns = 8
    private static let swatch: CGFloat = 20
    private static let gap: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if allowDefault || allowNone {
                HStack(spacing: 6) {
                    if allowDefault {
                        option(L("Theme Default"), selected: current == nil) {
                            Image(systemName: "arrow.uturn.backward").font(.system(size: 9, weight: .bold))
                        } action: { onPick(nil) }
                    }
                    if allowNone {
                        option(L("None"), selected: current?.isNone == true) {
                            ColorChip(color: nil).frame(width: 14, height: 10)
                        } action: { onPick(Paint.none) }
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.swatch), spacing: Self.gap), count: Self.columns),
                      alignment: .leading, spacing: Self.gap) {
                ForEach(uniquePresets, id: \.self) { hex in
                    let selected = current?.rawValue.uppercased() == hex.uppercased()
                    Button { onPick(Paint(hex)) } label: {
                        Circle().fill(Color(hex: hex))
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                            .frame(width: Self.swatch, height: Self.swatch)
                            .overlay(Circle().stroke(selected ? Color.accentColor : .clear, lineWidth: 2).padding(-3))
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            Button(L("More Colors…"), action: onMore)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
        }
        .padding(12)
        .frame(width: CGFloat(Self.columns) * Self.swatch + CGFloat(Self.columns - 1) * Self.gap + 24)
    }

    /// 去掉重复的颜色（几组预设可能都含白色），重复的 id 会让 ForEach 漏画。
    private var uniquePresets: [String] {
        var seen = Set<String>()
        return presets.filter { seen.insert($0.uppercased()).inserted }
    }

    private func option<Icon: View>(_ title: String, selected: Bool, @ViewBuilder icon: () -> Icon,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                icon()
                Text(title).font(.caption).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1)))
            .overlay(Capsule().stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    static let strong = ["#1F2328", "#FFFFFF", "#E5484D", "#F76B15", "#E9A800", "#30A46C", "#12A594",
                         "#0090FF", "#3E63DD", "#8E4EC6", "#D6409F", "#8B8D98"]
    static let soft = ["#FDE2E1", "#FFE7D4", "#FFF3C4", "#DDF3E4", "#D5F2EE", "#D9EDFF", "#E6E0FA", "#FBE0EF",
                       "#F1F1F1", "#E3E8EF", "#2B2F36", "#FFFFFF"]
}

/// 把系统颜色面板的修改转给当前的颜色按钮。
/// 颜色面板关闭或切换到别的窗口后不再转发，避免改到不相干的导图。
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()

    private var handler: ((NSColor) -> Void)?
    private weak var owner: NSWindow?

    private override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.willCloseNotification, object: NSColorPanel.shared, queue: .main) { [weak self] _ in
            self?.handler = nil
        }
        center.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let window = note.object as? NSWindow, window !== self.owner else { return }
            self.handler = nil
        }
    }

    func show(initial: NSColor?, handler: @escaping (NSColor) -> Void) {
        let panel = NSColorPanel.shared
        self.handler = nil   // 先断开，设置初始颜色时不触发修改
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        if let initial { panel.color = initial }
        owner = NSApp.mainWindow
        self.handler = handler
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        handler?(sender.color)
    }
}
