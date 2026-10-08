import AppKit
import Quartz

/// 菜单命令。主菜单、右键菜单、工具栏都走响应链把这些 action 发到画布。
extension MindMapCanvasView: NSMenuItemValidation {
    // MARK: 新建 / 编辑

    @objc func insertTopic(_ sender: Any?) { editor.addSibling() }
    @objc func insertSubtopic(_ sender: Any?) { editor.addChild() }
    @objc func insertTopicBefore(_ sender: Any?) { editor.addSibling(before: true) }
    @objc func insertParentTopic(_ sender: Any?) { editor.insertParent() }
    @objc func editTopic(_ sender: Any?) { editor.beginEditing(selectAll: true) }
    @objc func delete(_ sender: Any?) {
        if let rel = editor.selectedRelationship {
            editor.deleteRelationship(rel)
        } else {
            editor.deleteSelection()
        }
    }

    // MARK: 联系线

    /// ⌘L：选中两个主题时直接连线；选中一个时进入连线模式，再点目标主题。
    @objc func insertRelationship(_ sender: Any?) {
        if editor.selection.count == 2 {
            editor.addRelationship(from: editor.selection[0], to: editor.selection[1])
        } else if let source = editor.primaryID {
            beginRelationship(from: source)
        }
    }

    @objc func editRelationshipLabel(_ sender: Any?) {
        guard let id = editor.selectedRelationship else { return }
        showRelationshipLabelPopover(for: id)
    }

    @objc func resetRelationshipShape(_ sender: Any?) {
        guard let id = editor.selectedRelationship else { return }
        editor.resetRelationshipShape(id)
    }

    @objc func reverseRelationship(_ sender: Any?) {
        guard let id = editor.selectedRelationship else { return }
        editor.updateRelationship(id, actionName: L("Reverse Relationship")) { r in
            swap(&r.from, &r.to)
            swap(&r.control1, &r.control2)
            // 曲线方向反过来，标签留在原处
            r.labelPosition = r.labelPosition.map { 1 - $0 }
        }
    }

    /// ⌥⌘L：显示 / 隐藏全部联系线（菜单项带勾选状态）。
    @objc func toggleRelationships(_ sender: Any?) {
        editor.setRelationshipsHidden(!editor.map.relationshipsHidden)
    }

    @objc func hideRelationships(_ sender: Any?) {
        editor.setRelationshipsHidden(true)
    }

    func showRelationshipLabelPopover(for id: UUID) {
        guard let r = mapLayout.relationship(id) else { return }
        let mid = r.point(at: r.labelT)
        let anchor = viewRect(CGRect(x: mid.x - 4, y: mid.y - 4, width: 8, height: 8))
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = HostingPopoverController(
            rootView: RelationshipLabelPopoverView(editor: editor, relationshipID: id, close: { [weak popover] in popover?.close() }))
        popover.show(relativeTo: anchor, of: self, preferredEdge: .maxY)
    }

    func relationshipContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: L("Edit Label…"), action: #selector(editRelationshipLabel(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Reverse Direction"), action: #selector(reverseRelationship(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Reset Shape"), action: #selector(resetRelationshipShape(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Hide All Relationships"), action: #selector(hideRelationships(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Delete Relationship"), action: #selector(delete(_:)), keyEquivalent: "")
        return menu
    }
    @objc func deleteTopicOnly(_ sender: Any?) { editor.deleteKeepingChildren() }
    @objc func moveTopicUp(_ sender: Any?) { editor.moveSelection(up: true) }
    @objc func moveTopicDown(_ sender: Any?) { editor.moveSelection(up: false) }
    @objc func promoteTopic(_ sender: Any?) { editor.promoteSelection() }
    @objc func demoteTopic(_ sender: Any?) { editor.demoteSelection() }

    // MARK: 折叠

    @objc func toggleFold(_ sender: Any?) { editor.toggleFold() }
    @objc func expandAll(_ sender: Any?) { editor.expandAll() }
    @objc func collapseAll(_ sender: Any?) { editor.collapseAll() }
    @objc func showToLevel(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        editor.expand(toLevel: item.tag)
    }

    // MARK: 选择

    override func selectAll(_ sender: Any?) { editor.selectAll() }
    @objc func selectSiblings(_ sender: Any?) { editor.selectSiblings() }
    @objc func selectChildren(_ sender: Any?) { editor.selectChildren() }
    @objc func selectCentralTopic(_ sender: Any?) {
        editor.select(editor.rootID)
        scrollTopicVisible(editor.rootID)
    }

    // MARK: 主题元素

    @objc func editNote(_ sender: Any?) {
        guard let id = editor.primaryID else { return }
        showNotePopover(for: id)
    }

    @objc func editHyperlink(_ sender: Any?) {
        guard let id = editor.primaryID else { return }
        showLinkPopover(for: id)
    }

    @objc func openHyperlink(_ sender: Any?) {
        guard let link = editor.selectedTopic?.link else { return }
        Self.open(link: link)
    }

    @objc func removeHyperlink(_ sender: Any?) {
        guard let id = editor.primaryID else { return }
        editor.setLink(id, nil)
    }

    @objc func editLabels(_ sender: Any?) {
        guard let id = editor.primaryID else { return }
        showLabelsPopover(for: id)
    }

    @objc func attachFile(_ sender: Any?) {
        guard let id = editor.primaryID, let window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = L("Choose files to attach to the topic. They are copied into the map file.")
        panel.prompt = L("Attach")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            do { try self.editor.addAttachments(panel.urls, to: id) } catch { self.presentErrorSheet(error) }
        }
    }

    @objc func insertImage(_ sender: Any?) {
        guard let id = editor.primaryID, let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.prompt = L("Insert")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do { try self.editor.setImage(fileAt: url, for: id) } catch { self.presentErrorSheet(error) }
        }
    }

    @objc func removeImage(_ sender: Any?) {
        guard let id = editor.primaryID else { return }
        editor.removeImage(from: id)
    }

    @objc func toggleMarker(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let raw = item.representedObject as? String else { return }
        editor.toggleMarker(MarkerID(raw))
    }

    /// ⌘1…⌘6：优先级标记。
    @objc func togglePriority(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, (1...6).contains(item.tag) else { return }
        editor.toggleMarker(MarkerID("priority-\(item.tag)"))
    }

    @objc func clearMarkers(_ sender: Any?) { editor.clearMarkers() }

    @objc func toggleBoundary(_ sender: Any?) { editor.toggleBoundary() }

    @objc func toggleTopicBold(_ sender: Any?) {
        let bold = !(editor.selectedTopics.first.map { isBold($0) } ?? false)
        editor.updateStyle(actionName: L("Bold")) { $0.bold = bold }
    }

    @objc func toggleTopicItalic(_ sender: Any?) {
        let italic = !(editor.selectedTopic?.style.italic ?? false)
        editor.updateStyle(actionName: L("Italic")) { $0.italic = italic ? true : nil }
    }

    private func isBold(_ topic: Topic) -> Bool {
        guard let node = mapLayout.nodes[topic.id] else { return topic.style.bold ?? false }
        return NSFontManager.shared.traits(of: node.style.font).contains(.boldFontMask)
    }

    @objc func resetStyle(_ sender: Any?) { editor.clearStyle() }

    @objc func copyStyle(_ sender: Any?) {
        MapEditor.styleClipboard = editor.selectedTopic?.style
    }

    @objc func pasteStyle(_ sender: Any?) {
        guard var style = MapEditor.styleClipboard else { return }
        style.boundary = nil
        editor.updateStyle(actionName: L("Paste Style")) { s in
            let boundary = s.boundary
            s = style
            s.boundary = boundary
        }
    }

    // MARK: 剪贴板

    @objc func copy(_ sender: Any?) { editor.copySelection(to: .general) }

    @objc func cut(_ sender: Any?) {
        editor.copySelection(to: .general)
        editor.deleteSelection()
    }

    @objc func paste(_ sender: Any?) {
        do { try editor.paste(from: .general) } catch { presentErrorSheet(error) }
    }

    @objc func duplicate(_ sender: Any?) { editor.duplicateSelection() }

    // MARK: 附件

    @objc func openAttachmentItem(_ sender: Any?) {
        guard let ref = (sender as? NSMenuItem)?.representedObject as? AttachmentRef else { return }
        openAttachment(ref.attachmentID)
    }

    @objc func quickLookAttachmentItem(_ sender: Any?) {
        guard let ref = (sender as? NSMenuItem)?.representedObject as? AttachmentRef else { return }
        quickLook(ref.attachmentID)
    }

    func openAttachment(_ id: UUID) {
        guard let store = editor.attachments else { return }
        do {
            NSWorkspace.shared.open(try store.temporaryURL(for: id))
        } catch {
            presentErrorSheet(error)
        }
    }

    func saveAttachment(_ id: UUID) {
        guard let store = editor.attachments, let window, let name = store.fileName(for: id) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                guard let data = store.data(for: id) else { throw CocoaError(.fileReadNoSuchFile) }
                try data.write(to: url)
            } catch {
                self?.presentErrorSheet(error)
            }
        }
    }

    // MARK: 校验

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let hasSelection = editor.primaryID != nil
        let single = editor.selection.count == 1
        let topic = editor.selectedTopic
        let notRoot = editor.selection.contains { $0 != editor.rootID }
        switch item.action {
        case #selector(insertTopic(_:)), #selector(insertSubtopic(_:)), #selector(editTopic(_:)),
             #selector(editNote(_:)), #selector(editHyperlink(_:)), #selector(editLabels(_:)),
             #selector(attachFile(_:)), #selector(insertImage(_:)):
            return hasSelection
        case #selector(insertTopicBefore(_:)), #selector(insertParentTopic(_:)), #selector(moveTopicUp(_:)),
             #selector(moveTopicDown(_:)), #selector(demoteTopic(_:)):
            return hasSelection && editor.primaryID != editor.rootID
        case #selector(promoteTopic(_:)):
            guard let id = editor.primaryID, let parent = editor.map.parentID(of: id) else { return false }
            return parent != editor.rootID
        case #selector(delete(_:)):
            return notRoot || editor.selectedRelationship != nil
        case #selector(cut(_:)), #selector(duplicate(_:)):
            return notRoot
        case #selector(insertRelationship(_:)):
            return hasSelection && editor.selection.count <= 2
        case #selector(editRelationshipLabel(_:)), #selector(resetRelationshipShape(_:)), #selector(reverseRelationship(_:)):
            return editor.selectedRelationship != nil
        case #selector(toggleRelationships(_:)):
            item.state = editor.map.relationshipsHidden ? .off : .on
            return !editor.map.relationships.isEmpty
        case #selector(hideRelationships(_:)):
            return !editor.map.relationshipsHidden
        case #selector(deleteTopicOnly(_:)):
            return single && notRoot
        case #selector(copy(_:)):
            return hasSelection
        case #selector(paste(_:)):
            return hasSelection && editor.canPaste(from: .general)
        case #selector(toggleFold(_:)):
            let foldable = editor.selection.contains { id in
                id != editor.rootID && !(editor.map.topic(id)?.children.isEmpty ?? true)
            }
            item.title = (topic?.collapsed ?? false) ? L("Expand Branch") : L("Collapse Branch")
            return foldable
        case #selector(openHyperlink(_:)), #selector(removeHyperlink(_:)):
            return topic?.hasLink ?? false
        case #selector(removeImage(_:)):
            return topic?.image != nil
        case #selector(toggleMarker(_:)):
            if let raw = item.representedObject as? String {
                item.state = (topic?.markers.contains(MarkerID(raw)) ?? false) ? .on : .off
            }
            return hasSelection
        case #selector(togglePriority(_:)):
            item.state = (topic?.markers.contains(MarkerID("priority-\(item.tag)")) ?? false) ? .on : .off
            return hasSelection
        case #selector(clearMarkers(_:)):
            return editor.selectedTopics.contains { !$0.markers.isEmpty }
        case #selector(toggleBoundary(_:)):
            item.state = (topic?.style.boundary ?? false) ? .on : .off
            return hasSelection
        case #selector(toggleTopicBold(_:)):
            item.state = (topic.map(isBold) ?? false) ? .on : .off
            return hasSelection
        case #selector(toggleTopicItalic(_:)):
            item.state = (topic?.style.italic ?? false) ? .on : .off
            return hasSelection
        case #selector(resetStyle(_:)):
            return editor.selectedTopics.contains { !$0.style.isEmpty }
        case #selector(copyStyle(_:)):
            return single
        case #selector(pasteStyle(_:)):
            return hasSelection && MapEditor.styleClipboard != nil
        case #selector(selectSiblings(_:)):
            return hasSelection && editor.primaryID != editor.rootID
        case #selector(selectChildren(_:)):
            return !(topic?.children.isEmpty ?? true) && !(topic?.collapsed ?? true)
        default:
            return true
        }
    }

    // MARK: 右键菜单

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        cancelRelationship()
        let p = layoutPoint(for: event)
        if let id = mapLayout.topic(at: p) {
            if !editor.selection.contains(id) { editor.select(id) }
            return topicContextMenu()
        }
        if let rel = mapLayout.relationship(at: p) {
            editor.selectRelationship(rel)
            return relationshipContextMenu()
        }
        return canvasContextMenu()
    }

    func topicContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: L("Insert Subtopic"), action: #selector(insertSubtopic(_:)), keyEquivalent: "")
        if editor.primaryID != editor.rootID {
            menu.addItem(withTitle: L("Insert Topic"), action: #selector(insertTopic(_:)), keyEquivalent: "")
            menu.addItem(withTitle: L("Insert Parent Topic"), action: #selector(insertParentTopic(_:)), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Edit Text"), action: #selector(editTopic(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Note…"), action: #selector(editNote(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Hyperlink…"), action: #selector(editHyperlink(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Labels…"), action: #selector(editLabels(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Attach File…"), action: #selector(attachFile(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Insert Image…"), action: #selector(insertImage(_:)), keyEquivalent: "")
        if editor.selectedTopic?.image != nil {
            menu.addItem(withTitle: L("Remove Image"), action: #selector(removeImage(_:)), keyEquivalent: "")
        }
        let markers = NSMenuItem(title: L("Marker"), action: nil, keyEquivalent: "")
        markers.submenu = MainMenuBuilder.markerMenu()
        menu.addItem(markers)
        menu.addItem(withTitle: L("Add Relationship"), action: #selector(insertRelationship(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        if let topic = editor.selectedTopic, !topic.children.isEmpty, topic.id != editor.rootID {
            menu.addItem(withTitle: topic.collapsed ? L("Expand Branch") : L("Collapse Branch"),
                         action: #selector(toggleFold(_:)), keyEquivalent: "")
        }
        menu.addItem(withTitle: L("Boundary"), action: #selector(toggleBoundary(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Copy Style"), action: #selector(copyStyle(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Paste Style"), action: #selector(pasteStyle(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Reset Style"), action: #selector(resetStyle(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Cut"), action: #selector(cut(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Copy"), action: #selector(copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Paste"), action: #selector(paste(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Duplicate"), action: #selector(duplicate(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Delete"), action: #selector(delete(_:)), keyEquivalent: "")
        if editor.selection.count == 1, !(editor.selectedTopic?.children.isEmpty ?? true) {
            menu.addItem(withTitle: L("Delete Topic Only"), action: #selector(deleteTopicOnly(_:)), keyEquivalent: "")
        }
        return menu
    }

    func canvasContextMenu() -> NSMenu {
        let menu = NSMenu()
        let add = menu.addItem(withTitle: L("Insert Main Topic"), action: #selector(insertMainTopic(_:)), keyEquivalent: "")
        add.target = self
        menu.addItem(withTitle: L("Paste"), action: #selector(pasteToCentral(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let structure = NSMenuItem(title: L("Structure"), action: nil, keyEquivalent: "")
        structure.submenu = MainMenuBuilder.structureMenu()
        menu.addItem(structure)
        let theme = NSMenuItem(title: L("Theme"), action: nil, keyEquivalent: "")
        theme.submenu = MainMenuBuilder.themeMenu()
        menu.addItem(theme)
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Expand All"), action: #selector(expandAll(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Collapse All"), action: #selector(collapseAll(_:)), keyEquivalent: "")
        if !editor.map.relationships.isEmpty {
            menu.addItem(withTitle: L("Show Relationships"), action: #selector(toggleRelationships(_:)), keyEquivalent: "")
        }
        menu.addItem(withTitle: L("Zoom to Fit"), action: #selector(MapViewController.zoomToFit(_:)), keyEquivalent: "")
        return menu
    }

    @objc func insertMainTopic(_ sender: Any?) { editor.addChild(to: editor.rootID) }

    @objc func pasteToCentral(_ sender: Any?) {
        editor.select(editor.rootID)
        paste(sender)
    }

    // MARK: 指示图标点击

    func handleIndicatorClick(_ indicator: Indicator, topic id: UUID, rect: CGRect) {
        switch indicator {
        case .note:
            showNotePopover(for: id)
        case .link:
            if NSEvent.modifierFlags.contains(.option) {
                showLinkPopover(for: id)
            } else if let link = editor.map.topic(id)?.link {
                Self.open(link: link)
            }
        case .attachments:
            guard let topic = editor.map.topic(id) else { return }
            let menu = attachmentsMenu(for: topic)
            menu.popUp(positioning: nil, at: CGPoint(x: rect.minX, y: rect.maxY + 4), in: self)
        }
    }

    func attachmentsMenu(for topic: Topic) -> NSMenu {
        let menu = NSMenu()
        let formatter = ByteCountFormatter()
        for attachment in topic.attachments {
            let ref = AttachmentRef(topicID: topic.id, attachmentID: attachment.id)
            let icon = NSWorkspace.shared.icon(for: .init(filenameExtension: (attachment.name as NSString).pathExtension) ?? .data)
            icon.size = NSSize(width: 16, height: 16)
            let size = formatter.string(fromByteCount: attachment.size)
            // 单击打开；按住 ⌥ 变成“快速查看”
            let item = NSMenuItem(title: "\(attachment.name)  (\(size))", action: #selector(openAttachmentItem(_:)), keyEquivalent: "")
            item.representedObject = ref
            item.target = self
            item.image = icon
            menu.addItem(item)
            let alternate = NSMenuItem(title: LF("Quick Look “%@”", attachment.name), action: #selector(quickLookAttachmentItem(_:)),
                                       keyEquivalent: "")
            alternate.representedObject = ref
            alternate.target = self
            alternate.image = icon
            alternate.isAlternate = true
            alternate.keyEquivalentModifierMask = [.option]
            menu.addItem(alternate)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Attach File…"), action: #selector(attachFile(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Manage Attachments…"), action: #selector(showAttachmentsPanel(_:)), keyEquivalent: "").target = self
        return menu
    }

    @objc func showAttachmentsPanel(_ sender: Any?) {
        (window?.windowController as? MapWindowController)?.showInspector(tab: .content)
    }

    static func open(link: String) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        var url = URL(string: trimmed)
        if url?.scheme == nil {
            if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
                url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
            } else {
                url = URL(string: "https://" + trimmed)
            }
        }
        if let url { NSWorkspace.shared.open(url) }
    }

    func presentErrorSheet(_ error: Error) {
        if let window { presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil) } else { presentError(error) }
    }

    // MARK: 弹出框

    func popoverAnchor(for id: UUID) -> CGRect {
        guard let node = mapLayout.nodes[id] else { return .zero }
        return viewRect(node.frame)
    }

    func showNotePopover(for id: UUID) {
        guard mapLayout.nodes[id] != nil else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = HostingPopoverController(rootView: NotePopoverView(editor: editor, topicID: id))
        popover.show(relativeTo: popoverAnchor(for: id), of: self, preferredEdge: .maxY)
    }

    func showLinkPopover(for id: UUID) {
        guard mapLayout.nodes[id] != nil else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = HostingPopoverController(
            rootView: LinkPopoverView(editor: editor, topicID: id, close: { [weak popover] in popover?.close() }))
        popover.show(relativeTo: popoverAnchor(for: id), of: self, preferredEdge: .maxY)
    }

    func showLabelsPopover(for id: UUID) {
        guard mapLayout.nodes[id] != nil else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = HostingPopoverController(
            rootView: LabelsPopoverView(editor: editor, topicID: id, close: { [weak popover] in popover?.close() }))
        popover.show(relativeTo: popoverAnchor(for: id), of: self, preferredEdge: .maxY)
    }
}

/// 附件菜单项携带的引用。
final class AttachmentRef: NSObject {
    let topicID: UUID
    let attachmentID: UUID

    init(topicID: UUID, attachmentID: UUID) {
        self.topicID = topicID
        self.attachmentID = attachmentID
    }
}

// MARK: - 快速查看

extension MindMapCanvasView: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private static var previewURL: URL?

    func quickLook(_ id: UUID) {
        guard let store = editor.attachments, let url = try? store.temporaryURL(for: id) else { return }
        Self.previewURL = url
        // 预览面板通过响应链找数据源，画布必须是第一响应者
        window?.makeFirstResponder(self)
        if let panel = QLPreviewPanel.shared() {
            if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
                panel.reloadData()
            } else {
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { Self.previewURL != nil }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { Self.previewURL == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        Self.previewURL as NSURL?
    }
}
