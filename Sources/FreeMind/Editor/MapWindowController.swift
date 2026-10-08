import AppKit
import SwiftUI

/// 文档窗口：工具栏 + 画布 + 右侧检查器。
final class MapWindowController: NSWindowController, NSToolbarDelegate, NSMenuItemValidation {
    private(set) var mapViewController: MapViewController!
    private var splitViewController: NSSplitViewController!
    private var inspectorItem: NSSplitViewItem!

    private var mapDocument: MindMapDocument? { document as? MindMapDocument }
    private var editor: MapEditor? { mapDocument?.editor }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 680, height: 440)
        window.tabbingMode = .preferred
        window.titlebarSeparatorStyle = .line
        super.init(window: window)
        shouldCascadeWindows = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var document: AnyObject? {
        didSet {
            if mapViewController == nil, let doc = document as? MindMapDocument { setUp(doc) }
        }
    }

    private func setUp(_ doc: MindMapDocument) {
        guard let window else { return }
        let mapVC = MapViewController(editor: doc.editor, images: { [weak doc] in doc?.attachments.image(for: $0) })
        mapVC.restore(doc.restoredViewState)
        mapViewController = mapVC

        let split = NSSplitViewController()
        let main = NSSplitViewItem(viewController: mapVC)
        main.minimumThickness = 400
        split.addSplitViewItem(main)

        let inspectorVC = NSHostingController(rootView: InspectorView(editor: doc.editor))
        let inspector = NSSplitViewItem(inspectorWithViewController: inspectorVC)
        inspector.minimumThickness = 260
        inspector.maximumThickness = 420
        inspector.preferredThicknessFraction = 0.22
        inspector.canCollapse = true
        inspector.isCollapsed = !UserDefaults.standard.bool(forKey: "inspectorVisible")
        split.addSplitViewItem(inspector)
        split.splitView.autosaveName = "MapSplitView"
        inspectorItem = inspector
        splitViewController = split

        window.contentViewController = split
        window.setContentSize(NSSize(width: 1240, height: 800))
        window.center()

        let toolbar = NSToolbar(identifier: "MapToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        window.makeFirstResponder(mapVC.canvas)
    }

    func currentViewState() -> ViewState? { mapViewController?.currentViewState() }

    override func windowTitle(forDocumentDisplayName displayName: String) -> String { displayName }

    // MARK: - 检查器

    @IBAction func toggleFormatPanel(_ sender: Any?) {
        guard let inspectorItem else { return }
        let collapse = !inspectorItem.isCollapsed
        inspectorItem.animator().isCollapsed = collapse
        UserDefaults.standard.set(!collapse, forKey: "inspectorVisible")
    }

    func showInspector(tab: InspectorTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: "inspectorTab")
        if inspectorItem.isCollapsed { toggleFormatPanel(nil) }
    }

    // MARK: - 结构 / 主题（菜单）

    @objc func setStructureFromMenu(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String, let s = MapStructure(rawValue: raw) else { return }
        editor?.setStructure(s)
    }

    @objc func setThemeFromMenu(_ sender: Any?) {
        guard let id = (sender as? NSMenuItem)?.representedObject as? String,
              let theme = ThemeLibrary.shared.theme(id: id) else { return }
        editor?.setTheme(theme)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(setStructureFromMenu(_:)):
            item.state = (item.representedObject as? String) == editor?.map.structure.rawValue ? .on : .off
        case #selector(setThemeFromMenu(_:)):
            item.state = (item.representedObject as? String) == editor?.map.theme.id ? .on : .off
        case #selector(toggleFormatPanel(_:)):
            item.title = (inspectorItem?.isCollapsed ?? true) ? L("Show Format Panel") : L("Hide Format Panel")
        default: break
        }
        return true
    }

    // MARK: - 工具栏

    private enum ItemID {
        static let topic = NSToolbarItem.Identifier("topic")
        static let subtopic = NSToolbarItem.Identifier("subtopic")
        static let relationship = NSToolbarItem.Identifier("relationship")
        static let note = NSToolbarItem.Identifier("note")
        static let link = NSToolbarItem.Identifier("link")
        static let attach = NSToolbarItem.Identifier("attach")
        static let image = NSToolbarItem.Identifier("image")
        static let marker = NSToolbarItem.Identifier("marker")
        static let fold = NSToolbarItem.Identifier("fold")
        static let structure = NSToolbarItem.Identifier("structure")
        static let theme = NSToolbarItem.Identifier("theme")
        static let zoom = NSToolbarItem.Identifier("zoom")
        static let find = NSToolbarItem.Identifier("find")
        static let export = NSToolbarItem.Identifier("export")
        static let inspector = NSToolbarItem.Identifier("inspector")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ItemID.topic, ItemID.subtopic, ItemID.relationship, .space, ItemID.note, ItemID.link, ItemID.attach, ItemID.marker,
         .flexibleSpace, ItemID.structure, ItemID.theme, .flexibleSpace,
         ItemID.zoom, ItemID.export, .inspectorTrackingSeparator, ItemID.inspector]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ItemID.topic, ItemID.subtopic, ItemID.relationship, ItemID.note, ItemID.link, ItemID.attach, ItemID.image, ItemID.marker,
         ItemID.fold, ItemID.structure, ItemID.theme, ItemID.zoom, ItemID.find, ItemID.export, ItemID.inspector,
         .space, .flexibleSpace, .inspectorTrackingSeparator]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let canvas = mapViewController?.canvas
        func button(_ label: String, _ symbol: String, _ action: Selector, tip: String, target: AnyObject? = nil) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = label
            item.paletteLabel = label
            item.toolTip = tip
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            item.action = action
            item.target = target ?? canvas
            item.isBordered = true
            return item
        }
        func menuItem(_ label: String, _ symbol: String, menu: NSMenu, tip: String) -> NSToolbarItem {
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = label
            item.paletteLabel = label
            item.toolTip = tip
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            item.menu = menu
            item.showsIndicator = true
            return item
        }

        switch id {
        case ItemID.topic:
            return button(L("Topic"), "plus.rectangle", #selector(MindMapCanvasView.insertTopic(_:)),
                          tip: L("Insert a sibling topic (Return)"))
        case ItemID.subtopic:
            return button(L("Subtopic"), "arrow.turn.down.right", #selector(MindMapCanvasView.insertSubtopic(_:)),
                          tip: L("Insert a subtopic (Tab)"))
        case ItemID.relationship:
            return button(L("Relationship"), "point.topleft.down.to.point.bottomright.curvepath",
                          #selector(MindMapCanvasView.insertRelationship(_:)),
                          tip: L("Connect two topics with a relationship line (⌘L)"))
        case ItemID.note:
            return button(L("Note"), "note.text", #selector(MindMapCanvasView.editNote(_:)), tip: L("Add or edit a note (⌥⌘N)"))
        case ItemID.link:
            return button(L("Link"), "link", #selector(MindMapCanvasView.editHyperlink(_:)), tip: L("Add a hyperlink (⌘K)"))
        case ItemID.attach:
            return button(L("Attachment"), "paperclip", #selector(MindMapCanvasView.attachFile(_:)),
                          tip: L("Attach files to the topic (⌥⌘A)"))
        case ItemID.image:
            return button(L("Image"), "photo", #selector(MindMapCanvasView.insertImage(_:)), tip: L("Insert an image (⇧⌘I)"))
        case ItemID.fold:
            return button(L("Fold"), "arrow.down.right.and.arrow.up.left", #selector(MindMapCanvasView.toggleFold(_:)),
                          tip: L("Collapse or expand the branch (⌘/)"))
        case ItemID.find:
            return button(L("Find"), "magnifyingglass", #selector(MapViewController.showFindBar(_:)),
                          tip: L("Find topics (⌘F)"), target: mapViewController)
        case ItemID.marker:
            let menu = MainMenuBuilder.markerMenu()
            menu.items.forEach { $0.submenu?.items.forEach { $0.target = canvas } }
            return menuItem(L("Marker"), "flag", menu: menu, tip: L("Add priority, progress and other markers"))
        case ItemID.structure:
            return menuItem(L("Structure"), "point.3.connected.trianglepath.dotted", menu: MainMenuBuilder.structureMenu(),
                            tip: L("Change how the map is laid out"))
        case ItemID.theme:
            return menuItem(L("Theme"), "paintpalette", menu: MainMenuBuilder.themeMenu(withPreviews: true),
                            tip: L("Change the colors and style of the whole map"))
        case ItemID.export:
            return menuItem(L("Export"), "square.and.arrow.up", menu: MainMenuBuilder.exportMenu(),
                            tip: L("Export as Markdown, OPML, PNG or PDF"))
        case ItemID.zoom:
            let group = NSToolbarItemGroup(itemIdentifier: id, images: [
                NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: L("Zoom Out"))!,
                NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: L("Zoom In"))!,
            ], selectionMode: .momentary, labels: [L("Zoom Out"), L("Zoom In")], target: self,
               action: #selector(zoomSegment(_:)))
            group.label = L("Zoom")
            group.paletteLabel = L("Zoom")
            group.toolTip = L("Zoom out (⌘-) / zoom in (⌘+)")
            return group
        case ItemID.inspector:
            let item = button(L("Format"), "sidebar.right", #selector(toggleFormatPanel(_:)),
                              tip: L("Show or hide the format panel (⌥⌘I)"), target: self)
            return item
        default:
            return nil
        }
    }

    @objc private func zoomSegment(_ sender: NSToolbarItemGroup) {
        if sender.selectedIndex == 0 { mapViewController.zoomOut(nil) } else { mapViewController.zoomIn(nil) }
    }
}

extension MindMapCanvasView: NSToolbarItemValidation {
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard let action = item.action else { return true }
        return validateMenuItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
    }
}
