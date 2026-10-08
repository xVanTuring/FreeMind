import AppKit
import SwiftUI

/// 设置窗口：工具栏图标切换页面，窗口高度随页面内容变化。
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(Self.tab(GeneralSettings(), title: L("General"), symbol: "gearshape"))
        tabs.addTabViewItem(Self.tab(ExportSettings(), title: L("Export"), symbol: "square.and.arrow.up"))
        tabs.addTabViewItem(Self.tab(LibrarySettings(), title: L("Templates & Themes"), symbol: "square.grid.2x2"))
        tabs.addTabViewItem(Self.tab(AgentSettings(), title: L("Agent"), symbol: "network"))
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private static func tab<V: View>(_ view: V, title: String, symbol: String) -> NSTabViewItem {
        let hosting = NSHostingController(rootView: view)
        // 每页按内容给出窗口大小，切换页面时窗口跟着变
        hosting.sizingOptions = [.preferredContentSize]
        hosting.title = title
        let item = NSTabViewItem(viewController: hosting)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}

// MARK: - 页面

struct GeneralSettings: View {
    @Bindable private var prefs = Preferences.shared
    @State private var themes = ThemeLibrary.shared

    var body: some View {
        SettingsPane {
            SettingsGroup(title: L("Startup")) {
                SettingsRow(title: L("Show the welcome window when FreeMind starts"),
                            detail: L("The welcome window lists recent maps. When it is off, FreeMind starts with a new map.")) {
                    SettingsSwitch(isOn: $prefs.showWelcomeOnLaunch)
                }
            }
            SettingsGroup(title: L("New Maps")) {
                SettingsRow(title: L("Show the template gallery when creating a new map")) {
                    SettingsSwitch(isOn: $prefs.showTemplateGalleryOnNew)
                }
                SettingsDivider()
                SettingsRow(title: L("Default structure")) {
                    Picker(L("Default structure"), selection: $prefs.defaultStructure) {
                        ForEach(MapStructure.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(title: L("Default theme")) {
                    Picker(L("Default theme"), selection: $prefs.defaultThemeID) {
                        ForEach(themes.allThemes) { Text($0.displayName).tag($0.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(title: L("Default spacing")) {
                    Picker(L("Default spacing"), selection: $prefs.defaultSpacing) {
                        ForEach(MapSpacing.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingsGroup(title: L("Opening Maps")) {
                SettingsRow(title: L("Restore zoom level and position"),
                            detail: L("Collapsed branches are always saved in the file and restored.")) {
                    SettingsSwitch(isOn: $prefs.restoreViewState)
                }
            }
        }
    }
}

struct ExportSettings: View {
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        SettingsPane {
            SettingsGroup(title: L("Markdown")) {
                SettingsRow(title: L("Use headings for"), detail: L("Deeper levels are exported as nested lists.")) {
                    Picker(L("Use headings for"), selection: $prefs.markdownHeadingLevels) {
                        Text(L("None (lists only)")).tag(0)
                        ForEach(1...6, id: \.self) { Text(LF("%d levels", $0)).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(title: L("Include notes")) { SettingsSwitch(isOn: $prefs.markdownIncludeNotes) }
                SettingsDivider()
                SettingsRow(title: L("Include labels")) { SettingsSwitch(isOn: $prefs.markdownIncludeLabels) }
                SettingsDivider()
                SettingsRow(title: L("Export attachments and images to a folder")) {
                    SettingsSwitch(isOn: $prefs.markdownExportAttachments)
                }
            }
            SettingsGroup(title: L("Image")) {
                SettingsRow(title: L("PNG resolution")) {
                    Picker(L("PNG resolution"), selection: $prefs.pngScale) {
                        ForEach(1...4, id: \.self) { Text("\($0)×").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }
}

struct LibrarySettings: View {
    @State private var templates = TemplateLibrary.shared.userTemplates()
    @State private var themes = ThemeLibrary.shared

    var body: some View {
        SettingsPane {
            SettingsGroup(title: L("My Templates")) {
                if templates.isEmpty {
                    SettingsEmptyRow(text: L("No templates yet. Use File ▸ Save as Template to create one."))
                }
                ForEach(templates) { template in
                    SettingsRow(title: template.name) {
                        Button {
                            if let url = template.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        } label: { Image(systemName: "folder") }
                            .buttonStyle(.borderless)
                            .help(L("Show in Finder"))
                        Button {
                            try? TemplateLibrary.shared.deleteUserTemplate(template)
                            templates = TemplateLibrary.shared.userTemplates()
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help(L("Delete"))
                    }
                    SettingsDivider()
                }
                HStack {
                    Spacer()
                    Button(L("Open Templates Folder")) { NSWorkspace.shared.open(AppDirectories.templates) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            SettingsGroup(title: L("Custom Themes")) {
                if themes.customThemes.isEmpty {
                    SettingsEmptyRow(text: L("No custom themes yet. Adjust a theme in the format panel, then choose Save as Custom Theme."))
                }
                ForEach(Array(themes.customThemes.enumerated()), id: \.element.id) { index, theme in
                    if index > 0 { SettingsDivider() }
                    HStack(spacing: 10) {
                        Image(nsImage: ThemePreview.image(for: theme, size: CGSize(width: 100, height: 60)))
                            .resizable()
                            .frame(width: 50, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(theme.displayName)
                        Spacer()
                        Button { themes.delete(id: theme.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help(L("Delete"))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .onAppear { templates = TemplateLibrary.shared.userTemplates() }
    }
}

/// MCP 服务：开关、写入权限、端口，以及给 Agent 用的接入命令和口令。
struct AgentSettings: View {
    @Bindable private var prefs = Preferences.shared
    private let server = MCPServer.shared
    @State private var port = Preferences.shared.mcpPort
    /// 刚拷贝的是哪一项，按钮上短暂显示“已拷贝”。
    @State private var copied: String?

    var body: some View {
        SettingsPane {
            SettingsGroup(title: L("MCP Server")) {
                SettingsRow(title: L("Let AI agents use FreeMind"), detail: status) {
                    SettingsSwitch(isOn: Binding(get: { prefs.mcpEnabled }, set: { on in
                        prefs.mcpEnabled = on
                        if on { server.start() } else { server.stop() }
                    }))
                }
                SettingsDivider()
                SettingsRow(title: L("Allow agents to edit maps"),
                            detail: L("When this is off, agents can only read. Each change an agent makes is one step you can undo with ⌘Z.")) {
                    SettingsSwitch(isOn: $prefs.mcpAllowWrite)
                }
                SettingsDivider()
                SettingsRow(title: L("Port"), detail: L("Only programs on this Mac can connect.")) {
                    TextField(L("Port"), value: $port, format: .number.grouping(.never))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        .onChange(of: port) { applyPort() }
                }
            }
            SettingsGroup(title: L("Connect an Agent")) {
                SettingsRow(title: L("Claude Code"), detail: L("Run the copied command once in Terminal.")) {
                    copyButton("cli", L("Copy Command"), cliCommand)
                }
                SettingsDivider()
                SettingsRow(title: L("Other agents"), detail: L("Add the copied JSON to the agent's MCP server settings.")) {
                    copyButton("json", L("Copy JSON"), jsonConfig)
                }
                SettingsDivider()
                SettingsRow(title: L("Access token"),
                            detail: L("Agents must send this token. After you create a new one, set up your agents again.")) {
                    copyButton("token", L("Copy"), prefs.mcpToken)
                    Button(L("New Token")) {
                        prefs.regenerateMCPToken()
                        copied = nil
                    }
                }
            }
        }
    }

    private var status: String {
        if let error = server.lastError { return error }
        if server.isRunning { return LF("Running at %@", server.endpointURL) }
        return prefs.mcpEnabled ? L("Starting…") : L("Off")
    }

    private var endpoint: String { "http://127.0.0.1:\(prefs.mcpPort)/mcp" }

    private var cliCommand: String {
        "claude mcp add --transport http freemind \(endpoint) --header \"Authorization: Bearer \(prefs.mcpToken)\""
    }

    private var jsonConfig: String {
        let server: MCPObject = ["type": "http", "url": endpoint, "headers": ["Authorization": "Bearer \(prefs.mcpToken)"]]
        return MCPJSON.string(["mcpServers": ["freemind": server]], pretty: true)
    }

    private func copyButton(_ id: String, _ title: String, _ text: String) -> some View {
        Button(copied == id ? L("Copied") : title) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copied == id { copied = nil } }
        }
    }

    /// 端口改了就重启服务；不合法的值退回原来的端口。
    private func applyPort() {
        guard (1024...65535).contains(port) else {
            port = prefs.mcpPort
            return
        }
        guard port != prefs.mcpPort else { return }
        prefs.mcpPort = port
        server.restartIfRunning()
    }
}

// MARK: - 通用组件

/// 一页设置：固定宽度，高度随内容。
struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) { content }
            .padding(20)
            .frame(width: 500, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            // 打开窗口 / 切换页面时键盘焦点落在第一个控件上，不显示焦点框
            .focusEffectDisabled()
    }
}

/// 一组设置：小标题 + 圆角底板。组内各行之间用 `SettingsDivider` 分隔。
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
        }
    }
}

/// 一行设置：左边名称（可带说明），右边控件。
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 40)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 12)
    }
}

struct SettingsSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
    }
}

/// 组里没有内容时的提示行。
struct SettingsEmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }
}

/// 快捷键一览。
struct KeyboardShortcutsView: View {
    private struct Group: Identifiable {
        let id = UUID()
        let title: String
        let items: [(String, String)]
    }

    private var groups: [Group] {
        [
            Group(title: L("Add Topics"), items: [
                ("⇥", L("Insert subtopic")), ("↩", L("Insert sibling topic")), ("⇧↩", L("Insert topic before")),
                ("⌘↩", L("Insert parent topic")), ("⌘D", L("Duplicate topic")),
            ]),
            Group(title: L("Edit"), items: [
                (L("Space / F2"), L("Edit topic text")), (L("Type"), L("Replace topic text")),
                ("⇧↩", L("New line while editing")), ("⎋", L("Cancel editing")), ("⌫", L("Delete topic")),
                ("⌥⌫", L("Delete topic but keep its subtopics")), ("⌘Z / ⇧⌘Z", L("Undo / Redo")),
            ]),
            Group(title: L("Navigate & Organize"), items: [
                ("← → ↑ ↓", L("Move selection")), ("⇧ + ← → ↑ ↓", L("Extend selection")),
                ("⌥↑ / ⌥↓", L("Move topic up / down")), ("⌥← / ⌥→", L("Promote / demote topic")),
                ("⌘/", L("Collapse or expand branch")), ("⌥⌘/", L("Expand all")), ("⌃⌘/", L("Collapse all")),
                ("⌘A / ⇧⌘A", L("Select all / select siblings")), ("⌘Home", L("Select central topic")),
                (L("Drag"), L("Move topic; hold ⌥ to copy")), (L("⌥ + drag blank space"), L("Pan the map")),
            ]),
            Group(title: L("Topic Content"), items: [
                ("⌥⌘N", L("Note")), ("⌘K", L("Hyperlink")), ("⌥⌘A", L("Attach file")), ("⇧⌘I", L("Insert image")),
                ("⇧⌘L", L("Labels")), ("⌘1 … ⌘6", L("Priority 1 to 6")), ("⌥⌘B", L("Boundary")),
                ("⌘L", L("Connect two topics")),
                ("⌘B / ⌘I", L("Bold / italic")), ("⌥⌘C / ⌥⌘V", L("Copy / paste style")),
            ]),
            Group(title: L("View"), items: [
                ("⌘+ / ⌘-", L("Zoom in / out")), ("⌘0", L("Actual size")), ("⌘9", L("Zoom to fit")),
                (L("⌘ + scroll"), L("Zoom with the mouse wheel")), ("⌘F / ⌘G", L("Find / find next")),
                ("⌥⌘I", L("Show or hide the format panel")),
            ]),
            Group(title: L("Maps"), items: [
                ("⌘N", L("New map (opens the template gallery)")), ("⌘O", L("Open a map")),
                ("⇧⌘1", L("Welcome window with recent maps")),
            ]),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title).font(.headline)
                        ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.0)
                                    .font(.system(.body, design: .rounded).weight(.medium))
                                    .frame(width: 150, alignment: .leading)
                                Text(item.1).foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 480, minHeight: 400)
    }
}
