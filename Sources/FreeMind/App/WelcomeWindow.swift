import AppKit
import SwiftUI

/// 欢迎窗口：启动时没有打开的导图就显示，左边是新建 / 打开 / 快速上手，右边是最近打开的导图。
/// 打开或新建任何导图后自动关闭（见 `DocumentController.addDocument`）。
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: WelcomeWindowController?

    static var isVisible: Bool { shared?.window?.isVisible ?? false }

    static func show() {
        if shared == nil { shared = WelcomeWindowController() }
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
    }

    static func close() {
        shared?.window?.close()
    }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 480),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = L("Welcome to FreeMind")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: window)
        let hosting = NSHostingController(rootView: WelcomeView(
            recents: RecentMaps.urls,
            close: { [weak window] in window?.close() }))
        // 内容铺到透明标题栏下面；不让 SwiftUI 按“内容 + 标题栏”去撑大窗口
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 800, height: 480))
        window.center()
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        // 下次显示时重新读取最近列表
        DispatchQueue.main.async { WelcomeWindowController.shared = nil }
    }
}

/// 最近打开的导图（来自 NSDocumentController，系统负责记录）。
enum RecentMaps {
    static var urls: [URL] {
        NSDocumentController.shared.recentDocumentURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// NSDocumentController 没有删除单个条目的接口：清空后按原顺序重新登记其余条目。
    static func remove(_ url: URL) {
        let controller = NSDocumentController.shared
        let remaining = controller.recentDocumentURLs.filter { $0 != url }
        controller.clearRecentDocuments(nil)
        for u in remaining.reversed() { controller.noteNewRecentDocumentURL(u) }
    }

    static func clear() {
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    static func open(_ url: URL, then: @escaping () -> Void) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
            if let error {
                NSApp.presentError(error)
            } else if document != nil {
                then()
            }
        }
    }

    private static var thumbnails: [String: NSImage] = [:]

    /// 导图缩略图，按路径 + 修改时间缓存；不是 .fmind 或读不出来时返回 nil。
    static func thumbnail(for url: URL, modified: Date?) -> NSImage? {
        guard url.pathExtension.lowercased() == DocumentTypes.fileExtension else { return nil }
        let key = "\(url.path)|\(modified?.timeIntervalSince1970 ?? 0)"
        if let cached = thumbnails[key] { return cached }
        guard let preview = try? MapPreviewLoader.load(url) else { return nil }
        let images = preview.images
        let image = ImageExporter.thumbnail(layout: preview.layout, images: { images[$0] }, size: CGSize(width: 240, height: 150))
        thumbnails[key] = image
        return image
    }
}

struct WelcomeView: View {
    @State var recents: [URL]
    let close: () -> Void
    @State private var showOnLaunch = Preferences.shared.showWelcomeOnLaunch

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        HStack(spacing: 0) {
            actions.frame(width: 340)
            Divider()
            recentList.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 800, height: 480)
        // 标题栏透明，内容一直铺到窗口顶部
        .ignoresSafeArea()
        // 打开窗口时键盘焦点会落在第一个按钮上，不显示焦点框（悬停时已有高亮）
        .focusEffectDisabled()
    }

    // MARK: 左边

    private var actions: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 104, height: 104)
            Text("FreeMind")
                .font(.system(size: 30, weight: .bold))
                .padding(.top, 6)
            Text(LF("Version %@", version))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(spacing: 6) {
                WelcomeAction(symbol: "plus.square", title: L("New Map…"),
                              detail: L("Start from a blank map or a template")) {
                    NSDocumentController.shared.newDocument(nil)
                }
                WelcomeAction(symbol: "folder", title: L("Open…"),
                              detail: L("Open maps, Markdown, OPML or XMind")) {
                    NSDocumentController.shared.openDocument(nil)
                }
                WelcomeAction(symbol: "book", title: L("Getting Started"),
                              detail: L("Learn the basics in a few minutes")) {
                    (NSApp.delegate as? AppDelegate)?.openGettingStarted(nil)
                }
            }
            .padding(.top, 28)
            .padding(.horizontal, 24)
            Spacer(minLength: 16)
            Toggle(L("Show this window when FreeMind starts"), isOn: $showOnLaunch)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .onChange(of: showOnLaunch) { Preferences.shared.showWelcomeOnLaunch = showOnLaunch }
                .padding(.bottom, 18)
        }
    }

    // MARK: 右边

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Recent Maps"))
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 36)
                .padding(.bottom, 10)
            if recents.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock").font(.system(size: 30)).foregroundStyle(.tertiary)
                    Text(L("No recent maps")).foregroundStyle(.secondary)
                    Text(L("Maps you open will appear here."))
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(recents, id: \.self) { url in
                            RecentMapRow(url: url,
                                         open: { RecentMaps.open(url, then: close) },
                                         remove: {
                                             RecentMaps.remove(url)
                                             recents.removeAll { $0 == url }
                                         },
                                         clearAll: {
                                             RecentMaps.clear()
                                             recents = []
                                         })
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color.primary.opacity(0.03))
    }
}

/// 左边的大按钮：图标 + 标题 + 说明。
private struct WelcomeAction: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(hovering ? 0.1 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 最近导图的一行：缩略图、名称、所在文件夹、修改时间。单击打开。
private struct RecentMapRow: View {
    let url: URL
    let open: () -> Void
    let remove: () -> Void
    let clearAll: () -> Void
    @State private var hovering = false
    @State private var thumbnail: NSImage?

    private var modified: Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private var folder: String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        let date = modified
        Button(action: open) {
            HStack(spacing: 12) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit).padding(6)
                    }
                }
                .frame(width: 80, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(folder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if let date {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.primary.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(url.path)
        .contextMenu {
            Button(L("Open"), action: open)
            Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button(L("Remove from Recent Maps"), action: remove)
            Button(L("Clear Recent Maps"), action: clearAll)
        }
        .task(id: date) { thumbnail = RecentMaps.thumbnail(for: url, modified: date) }
    }
}
