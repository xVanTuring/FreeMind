import AppKit
import SwiftUI

/// 新建导图时的模板库窗口。
final class TemplateGalleryController: NSWindowController, NSWindowDelegate {
    static var shared: TemplateGalleryController?

    static func show() {
        if shared == nil { shared = TemplateGalleryController() }
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
    }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = L("New Map")
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 820, height: 560)
        super.init(window: window)
        let hosting = NSHostingController(rootView: TemplateGalleryView(close: { [weak window] in window?.close() }))
        hosting.sizingOptions = [.minSize]
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 940, height: 680))
        window.center()
        window.setFrameAutosaveName("TemplateGallery")
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        // 下次打开时重新加载（用户模板可能有变化）
        DispatchQueue.main.async { TemplateGalleryController.shared = nil }
    }
}

struct TemplateGalleryView: View {
    let close: () -> Void
    @State private var selectedID = "blank-mindmap"
    @State private var themeID = Preferences.shared.defaultThemeID
    @State private var userTemplates = TemplateLibrary.shared.userTemplates()
    @State private var themes = ThemeLibrary.shared.allThemes
    @State private var showOnNew = Preferences.shared.showTemplateGalleryOnNew

    private let library = TemplateLibrary.shared
    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)]

    private var allTemplates: [MapTemplate] { library.blankTemplates() + library.builtinTemplates() + userTemplates }

    private var theme: Theme { ThemeLibrary.shared.theme(id: themeID) ?? .classic }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section(L("Blank"), library.blankTemplates())
                    section(L("Templates"), library.builtinTemplates())
                    if !userTemplates.isEmpty {
                        section(L("My Templates"), userTemplates)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 36)
                .padding(.bottom, 20)
            }
            Divider()
            HStack(spacing: 12) {
                Text(L("Theme for blank maps:")).fixedSize()
                Picker("", selection: $themeID) {
                    ForEach(themes) { Text($0.displayName).tag($0.id) }
                }
                .labelsHidden()
                .fixedSize()
                Toggle(L("Show when creating a new map"), isOn: $showOnNew)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .onChange(of: showOnNew) { Preferences.shared.showTemplateGalleryOnNew = showOnNew }
                Spacer(minLength: 12)
                Button(L("Open…")) {
                    close()
                    NSDocumentController.shared.openDocument(nil)
                }
                Button(L("Cancel"), action: close).keyboardShortcut(.cancelAction)
                Button(L("Create"), action: create).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 820, idealWidth: 940, minHeight: 560, idealHeight: 680)
    }

    @ViewBuilder
    private func section(_ title: String, _ templates: [MapTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(templates) { template in
                    TemplateCard(template: template, theme: theme, selected: template.id == selectedID)
                        .onTapGesture(count: 2) {
                            selectedID = template.id
                            create()
                        }
                        .simultaneousGesture(TapGesture().onEnded { selectedID = template.id })
                        .contextMenu {
                            if template.kind == .user {
                                Button(L("Show in Finder")) {
                                    if let url = template.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                }
                                Button(L("Delete Template"), role: .destructive) {
                                    try? library.deleteUserTemplate(template)
                                    userTemplates = library.userTemplates()
                                }
                            }
                        }
                }
            }
        }
    }

    private func create() {
        guard let template = allTemplates.first(where: { $0.id == selectedID }) else { return }
        do {
            var (map, resources) = try library.load(template)
            if template.kind == .blank { map.theme = theme }
            Preferences.shared.defaultThemeID = themeID
            let title: String? = template.kind == .blank ? nil : template.name
            DocumentController.sharedController.openUntitled(map: map, resources: resources, displayName: title, markEdited: false)
            close()
        } catch {
            NSApp.presentError(error)
        }
    }
}

struct TemplateCard: View {
    let template: MapTemplate
    let theme: Theme
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(nsImage: TemplatePreviewCache.image(for: template, theme: theme))
                .resizable()
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor : Color.black.opacity(0.12), lineWidth: selected ? 3 : 1))
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            Text(template.name).font(.headline).lineLimit(1)
            Text(template.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

/// 模板预览缩略图缓存。
enum TemplatePreviewCache {
    private static var cache: [String: NSImage] = [:]

    static func image(for template: MapTemplate, theme: Theme) -> NSImage {
        let key = template.kind == .blank ? "\(template.id)|\(theme.id)" : template.id
        if let cached = cache[key] { return cached }
        var image = NSImage(size: NSSize(width: 320, height: 200))
        if let (map, resources) = try? TemplateLibrary.shared.load(template) {
            var m = map
            if template.kind == .blank { m.theme = theme }
            let layout = LayoutEngine(map: m, measurer: TopicMeasurer()).run()
            let images = Dictionary(uniqueKeysWithValues: resources.compactMap { id, file in
                NSImage(data: file.data).map { (id, $0) }
            })
            image = ImageExporter.thumbnail(layout: layout, images: { images[$0] }, size: CGSize(width: 320, height: 200))
        }
        cache[key] = image
        return image
    }
}
