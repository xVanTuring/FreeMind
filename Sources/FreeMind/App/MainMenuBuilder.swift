import AppKit
import Sparkle

/// 用代码构建主菜单（不依赖 xib），所有标题都本地化。
/// 快捷键与 XMind 保持一致：Tab 子主题、Return 同级主题、⇧Return 前插、⌘Return 父主题、⌘/ 折叠。
enum MainMenuBuilder {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(insertMenu()))
        main.addItem(submenu(modifyMenu()))
        main.addItem(submenu(viewMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        let help = helpMenu()
        main.addItem(submenu(help))
        NSApp.windowsMenu = window
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                            _ modifiers: NSEvent.ModifierFlags = [.command], tag: Int = 0, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.tag = tag
        item.target = target
        menu.addItem(item)
        return item
    }

    private static func key(_ scalar: Int) -> String { String(Character(UnicodeScalar(scalar)!)) }

    // MARK: 应用

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "FreeMind")
        add(menu, L("About FreeMind"), #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        add(menu, L("Check for Updates…"), #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            target: UpdaterService.shared.controller)
        menu.addItem(.separator())
        add(menu, L("Settings…"), #selector(AppDelegate.showSettings(_:)), ",")
        menu.addItem(.separator())
        let services = NSMenuItem(title: L("Services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: L("Services"))
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())
        add(menu, L("Hide FreeMind"), #selector(NSApplication.hide(_:)), "h")
        add(menu, L("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(menu, L("Show All"), #selector(NSApplication.unhideAllApplications(_:)))
        menu.addItem(.separator())
        add(menu, L("Quit FreeMind"), #selector(NSApplication.terminate(_:)), "q")
        return menu
    }

    // MARK: 文件

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: L("File"))
        add(menu, L("New"), #selector(NSDocumentController.newDocument(_:)), "n")
        add(menu, L("New from Template…"), #selector(AppDelegate.newFromTemplate(_:)), "n", [.command, .shift])
        add(menu, L("Open…"), #selector(NSDocumentController.openDocument(_:)), "o")
        // “打开最近使用”由 NSDocumentController 自动插在“打开…”后面（带最近文件列表和“清除菜单”），这里不再手动添加
        menu.addItem(.separator())
        add(menu, L("Close"), #selector(NSWindow.performClose(_:)), "w")
        add(menu, L("Save…"), #selector(NSDocument.save(_:)), "s")
        add(menu, L("Duplicate"), #selector(NSDocument.duplicate(_:)), "s", [.command, .shift])
        add(menu, L("Rename…"), #selector(NSDocument.rename(_:)))
        add(menu, L("Move To…"), #selector(NSDocument.move(_:)))
        let revert = NSMenuItem(title: L("Revert To"), action: nil, keyEquivalent: "")
        let revertMenu = NSMenu(title: L("Revert To"))
        add(revertMenu, L("Last Saved Version"), #selector(NSDocument.revertToSaved(_:)))
        add(revertMenu, L("Browse All Versions…"), #selector(NSDocument.browseVersions(_:)))
        revert.submenu = revertMenu
        menu.addItem(revert)
        menu.addItem(.separator())
        add(menu, L("Import…"), #selector(AppDelegate.importDocument(_:)), "i", [.command, .option, .shift])
        let export = NSMenuItem(title: L("Export"), action: nil, keyEquivalent: "")
        export.submenu = exportMenu()
        menu.addItem(export)
        add(menu, L("Save as Template…"), #selector(MindMapDocument.saveAsTemplate(_:)))
        menu.addItem(.separator())
        add(menu, L("Page Setup…"), #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift])
        add(menu, L("Print…"), #selector(NSDocument.printDocument(_:)), "p")
        return menu
    }

    static func exportMenu() -> NSMenu {
        let menu = NSMenu(title: L("Export"))
        add(menu, L("Markdown…"), #selector(MindMapDocument.exportMarkdown(_:)), "e", [.command, .shift])
        add(menu, L("OPML…"), #selector(MindMapDocument.exportOPML(_:)))
        menu.addItem(.separator())
        add(menu, L("PNG Image…"), #selector(MindMapDocument.exportPNG(_:)))
        add(menu, L("PDF…"), #selector(MindMapDocument.exportPDF(_:)))
        menu.addItem(.separator())
        add(menu, L("Copy as Markdown"), #selector(MindMapDocument.copyAsMarkdown(_:)))
        return menu
    }

    // MARK: 编辑

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: L("Edit"))
        add(menu, L("Undo"), Selector(("undo:")), "z")
        add(menu, L("Redo"), Selector(("redo:")), "z", [.command, .shift])
        menu.addItem(.separator())
        add(menu, L("Cut"), #selector(NSText.cut(_:)), "x")
        add(menu, L("Copy"), #selector(NSText.copy(_:)), "c")
        add(menu, L("Paste"), #selector(NSText.paste(_:)), "v")
        add(menu, L("Duplicate"), #selector(MindMapCanvasView.duplicate(_:)), "d")
        add(menu, L("Delete"), #selector(NSText.delete(_:)), key(8), [])
        add(menu, L("Delete Topic Only"), #selector(MindMapCanvasView.deleteTopicOnly(_:)), key(8), [.option])
        add(menu, L("Select All"), #selector(NSText.selectAll(_:)), "a")
        add(menu, L("Select Siblings"), #selector(MindMapCanvasView.selectSiblings(_:)), "a", [.command, .shift])
        add(menu, L("Select Children"), #selector(MindMapCanvasView.selectChildren(_:)))
        add(menu, L("Select Central Topic"), #selector(MindMapCanvasView.selectCentralTopic(_:)), key(NSHomeFunctionKey))
        menu.addItem(.separator())
        add(menu, L("Copy Style"), #selector(MindMapCanvasView.copyStyle(_:)), "c", [.command, .option])
        add(menu, L("Paste Style"), #selector(MindMapCanvasView.pasteStyle(_:)), "v", [.command, .option])
        menu.addItem(.separator())
        let find = NSMenuItem(title: L("Find"), action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: L("Find"))
        add(findMenu, L("Find…"), #selector(MapViewController.showFindBar(_:)), "f")
        add(findMenu, L("Find Next"), #selector(MapViewController.findNextMatch(_:)), "g")
        add(findMenu, L("Find Previous"), #selector(MapViewController.findPreviousMatch(_:)), "g", [.command, .shift])
        add(findMenu, L("Use Selection for Find"), #selector(MapViewController.useSelectionForFind(_:)), "e")
        find.submenu = findMenu
        menu.addItem(find)
        return menu
    }

    // MARK: 插入

    private static func insertMenu() -> NSMenu {
        let menu = NSMenu(title: L("Insert"))
        add(menu, L("Topic"), #selector(MindMapCanvasView.insertTopic(_:)), "\r", [])
        add(menu, L("Subtopic"), #selector(MindMapCanvasView.insertSubtopic(_:)), "\t", [])
        add(menu, L("Topic Before"), #selector(MindMapCanvasView.insertTopicBefore(_:)), "\r", [.shift])
        add(menu, L("Parent Topic"), #selector(MindMapCanvasView.insertParentTopic(_:)), "\r", [.command])
        menu.addItem(.separator())
        add(menu, L("Note…"), #selector(MindMapCanvasView.editNote(_:)), "n", [.command, .option])
        add(menu, L("Hyperlink…"), #selector(MindMapCanvasView.editHyperlink(_:)), "k")
        add(menu, L("Labels…"), #selector(MindMapCanvasView.editLabels(_:)), "l", [.command, .shift])
        add(menu, L("Attach File…"), #selector(MindMapCanvasView.attachFile(_:)), "a", [.command, .option])
        add(menu, L("Image…"), #selector(MindMapCanvasView.insertImage(_:)), "i", [.command, .shift])
        menu.addItem(.separator())
        let markers = NSMenuItem(title: L("Marker"), action: nil, keyEquivalent: "")
        markers.submenu = markerMenu(withShortcuts: true)
        menu.addItem(markers)
        add(menu, L("Boundary"), #selector(MindMapCanvasView.toggleBoundary(_:)), "b", [.command, .option])
        add(menu, L("Relationship"), #selector(MindMapCanvasView.insertRelationship(_:)), "l")
        menu.addItem(.separator())
        add(menu, L("Open Hyperlink"), #selector(MindMapCanvasView.openHyperlink(_:)), "o", [.command, .option])
        add(menu, L("Remove Hyperlink"), #selector(MindMapCanvasView.removeHyperlink(_:)))
        add(menu, L("Remove Image"), #selector(MindMapCanvasView.removeImage(_:)))
        return menu
    }

    static func markerMenu(withShortcuts: Bool = false) -> NSMenu {
        let menu = NSMenu(title: L("Marker"))
        for group in MarkerGroup.allCases {
            let groupItem = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: group.title)
            for marker in MarkerCatalog.markers(in: group) {
                let item: NSMenuItem
                if group == .priority, withShortcuts, let n = Int(marker.suffix) {
                    item = NSMenuItem(title: MarkerCatalog.title(for: marker), action: #selector(MindMapCanvasView.togglePriority(_:)),
                                      keyEquivalent: "\(n)")
                    item.keyEquivalentModifierMask = [.command]
                    item.tag = n
                } else {
                    item = NSMenuItem(title: MarkerCatalog.title(for: marker), action: #selector(MindMapCanvasView.toggleMarker(_:)),
                                      keyEquivalent: "")
                    item.representedObject = marker.rawValue
                }
                item.image = MarkerRenderer.image(for: marker, size: 16)
                sub.addItem(item)
            }
            groupItem.submenu = sub
            menu.addItem(groupItem)
        }
        menu.addItem(.separator())
        add(menu, L("Clear Markers"), #selector(MindMapCanvasView.clearMarkers(_:)))
        return menu
    }

    // MARK: 修改

    private static func modifyMenu() -> NSMenu {
        let menu = NSMenu(title: L("Modify"))
        add(menu, L("Edit Text"), #selector(MindMapCanvasView.editTopic(_:)), " ", [])
        menu.addItem(.separator())
        add(menu, L("Move Up"), #selector(MindMapCanvasView.moveTopicUp(_:)), key(NSUpArrowFunctionKey), [.option])
        add(menu, L("Move Down"), #selector(MindMapCanvasView.moveTopicDown(_:)), key(NSDownArrowFunctionKey), [.option])
        add(menu, L("Promote"), #selector(MindMapCanvasView.promoteTopic(_:)), key(NSLeftArrowFunctionKey), [.option])
        add(menu, L("Demote"), #selector(MindMapCanvasView.demoteTopic(_:)), key(NSRightArrowFunctionKey), [.option])
        menu.addItem(.separator())
        add(menu, L("Collapse Branch"), #selector(MindMapCanvasView.toggleFold(_:)), "/")
        add(menu, L("Expand All"), #selector(MindMapCanvasView.expandAll(_:)), "/", [.command, .option])
        add(menu, L("Collapse All"), #selector(MindMapCanvasView.collapseAll(_:)), "/", [.command, .control])
        let level = NSMenuItem(title: L("Show Levels"), action: nil, keyEquivalent: "")
        let levelMenu = NSMenu(title: L("Show Levels"))
        for n in 1...4 {
            add(levelMenu, LF("Level %d", n), #selector(MindMapCanvasView.showToLevel(_:)), tag: n)
        }
        level.submenu = levelMenu
        menu.addItem(level)
        menu.addItem(.separator())
        add(menu, L("Bold"), #selector(MindMapCanvasView.toggleTopicBold(_:)), "b")
        add(menu, L("Italic"), #selector(MindMapCanvasView.toggleTopicItalic(_:)), "i")
        add(menu, L("Reset Style"), #selector(MindMapCanvasView.resetStyle(_:)))
        menu.addItem(.separator())
        let structure = NSMenuItem(title: L("Structure"), action: nil, keyEquivalent: "")
        structure.submenu = structureMenu()
        menu.addItem(structure)
        let theme = NSMenuItem(title: L("Theme"), action: nil, keyEquivalent: "")
        theme.submenu = themeMenu()
        menu.addItem(theme)
        return menu
    }

    static func structureMenu() -> NSMenu {
        let menu = NSMenu(title: L("Structure"))
        for s in MapStructure.allCases {
            let item = add(menu, s.title, #selector(MapWindowController.setStructureFromMenu(_:)))
            item.representedObject = s.rawValue
            item.image = NSImage(systemSymbolName: s.symbolName, accessibilityDescription: nil)
        }
        return menu
    }

    static func themeMenu(withPreviews: Bool = false) -> NSMenu {
        let menu = ThemeMenu(title: L("Theme"))
        menu.withPreviews = withPreviews
        menu.rebuild()
        return menu
    }

    // MARK: 显示

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: L("View"))
        add(menu, L("Zoom In"), #selector(MapViewController.zoomIn(_:)), "=")
        add(menu, L("Zoom Out"), #selector(MapViewController.zoomOut(_:)), "-")
        add(menu, L("Actual Size"), #selector(MapViewController.actualSize(_:)), "0")
        add(menu, L("Zoom to Fit"), #selector(MapViewController.zoomToFit(_:)), "9")
        add(menu, L("Center Map"), #selector(MapViewController.centerMap(_:)), "8")
        menu.addItem(.separator())
        add(menu, L("Show Format Panel"), #selector(MapWindowController.toggleFormatPanel(_:)), "i", [.command, .option])
        add(menu, L("Show Toolbar"), #selector(NSWindow.toggleToolbarShown(_:)), "t", [.command, .option])
        add(menu, L("Customize Toolbar…"), #selector(NSWindow.runToolbarCustomizationPalette(_:)))
        menu.addItem(.separator())
        add(menu, L("Enter Full Screen"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        return menu
    }

    // MARK: 窗口 / 帮助

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: L("Window"))
        add(menu, L("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m")
        add(menu, L("Zoom"), #selector(NSWindow.performZoom(_:)))
        menu.addItem(.separator())
        add(menu, L("Welcome to FreeMind"), #selector(AppDelegate.showWelcome(_:)), "1", [.command, .shift])
        menu.addItem(.separator())
        add(menu, L("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:)))
        return menu
    }

    private static func helpMenu() -> NSMenu {
        let menu = NSMenu(title: L("Help"))
        add(menu, L("Getting Started"), #selector(AppDelegate.openGettingStarted(_:)))
        add(menu, L("Keyboard Shortcuts"), #selector(AppDelegate.showKeyboardShortcuts(_:)), "k", [.command, .shift])
        return menu
    }
}

/// 主题菜单：每次打开时刷新（自定义主题可能有增删）。
final class ThemeMenu: NSMenu, NSMenuDelegate {
    var withPreviews = false

    override init(title: String) {
        super.init(title: title)
        delegate = self
    }

    required init(coder: NSCoder) { fatalError() }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }

    func rebuild() {
        removeAllItems()
        let custom = ThemeLibrary.shared.customThemes
        for theme in Theme.builtins { addItem(item(for: theme)) }
        if !custom.isEmpty {
            addItem(.separator())
            for theme in custom { addItem(item(for: theme)) }
        }
    }

    private func item(for theme: Theme) -> NSMenuItem {
        let item = NSMenuItem(title: theme.displayName, action: #selector(MapWindowController.setThemeFromMenu(_:)), keyEquivalent: "")
        item.representedObject = theme.id
        if withPreviews {
            let image = ThemePreview.image(for: theme)
            image.size = NSSize(width: 60, height: 36)
            item.image = image
        } else {
            let swatch = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
                theme.backgroundColor.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3).fill()
                theme.branchColor(at: 0).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 3.5, dy: 3.5)).fill()
                NSColor.black.withAlphaComponent(0.2).setStroke()
                NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3).stroke()
                return true
            }
            item.image = swatch
        }
        return item
    }
}
