import AppKit
import Observation

/// 画布需要响应的编辑器事件。
protocol MapEditorDelegate: AnyObject {
    func editorLayoutDidChange(_ editor: MapEditor)
    func editorSelectionDidChange(_ editor: MapEditor)
    func editor(_ editor: MapEditor, beginEditing id: UUID, selectAll: Bool)
    func editorEndEditing(_ editor: MapEditor)
    func editor(_ editor: MapEditor, reveal id: UUID)
}

/// 一张导图的编辑核心：持有模型、选中状态、布局结果，所有修改都经过这里（带撤销）。
@Observable
final class MapEditor {
    private(set) var map: MindMap
    private(set) var layout = MapLayout()
    private(set) var selection: [UUID] = []
    /// 选中的联系线（与主题选择互斥）。
    private(set) var selectedRelationship: UUID?
    private(set) var editingID: UUID?
    /// 每次模型变化递增，SwiftUI 视图据此刷新。
    private(set) var revision = 0
    /// 当前缩放比例（由画布同步过来，状态栏显示）。
    var zoom: CGFloat = 1

    // 查找
    var findQuery = "" { didSet { if findQuery != oldValue { updateFindResults() } } }
    var findInNotes = true { didSet { updateFindResults() } }
    private(set) var findResults: [UUID] = []
    private(set) var findIndex: Int?

    @ObservationIgnored weak var document: MindMapDocument?
    @ObservationIgnored weak var delegate: MapEditorDelegate?
    @ObservationIgnored let measurer = TopicMeasurer()
    @ObservationIgnored private var editingText: String?
    @ObservationIgnored private var editingMarkedDirty = false
    @ObservationIgnored private var lastVisitedChild: [UUID: UUID] = [:]
    @ObservationIgnored private var coalesceKey: String?
    @ObservationIgnored private var registrationCount = 0
    @ObservationIgnored private var coalesceToken: (key: String, count: Int)?

    init(map: MindMap) {
        self.map = map
        relayout()
    }

    var undoManager: UndoManager? { document?.undoManager }
    var attachments: AttachmentStore? { document?.attachments }

    // MARK: - 读取

    func load(_ newMap: MindMap) {
        map = newMap
        selection = [map.root.id]
        editingID = nil
        editingText = nil
        modelDidChange()
    }

    // MARK: - 选中

    var primaryID: UUID? { selection.last }

    var selectedTopic: Topic? { primaryID.flatMap { map.topic($0) } }

    var selectedTopics: [Topic] { selection.compactMap { map.topic($0) } }

    var rootID: UUID { map.root.id }

    func select(_ id: UUID?, extend: Bool = false) {
        guard let id else {
            setSelection([])
            return
        }
        if extend {
            var s = selection
            if let i = s.firstIndex(of: id) {
                s.remove(at: i)
            } else {
                s.append(id)
            }
            setSelection(s)
        } else {
            setSelection([id])
        }
    }

    func setSelection(_ ids: [UUID]) {
        // 选主题（包括清空选择）时取消联系线的选中
        if selectedRelationship != nil {
            selectedRelationship = nil
            delegate?.editorSelectionDidChange(self)
        }
        // 只允许选中可见的主题（被折叠隐藏的不算）。
        var seen = Set<UUID>()
        let unique = ids.filter { layout.nodes[$0] != nil && seen.insert($0).inserted }
        guard unique != selection else { return }
        if let p = unique.last, let parent = map.parentID(of: p) { lastVisitedChild[parent] = p }
        selection = unique
        delegate?.editorSelectionDidChange(self)
    }

    func selectAll() {
        setSelection(layout.order)
    }

    func selectSiblings() {
        guard let id = primaryID, let parent = map.parentID(of: id), let p = map.topic(parent) else { return }
        setSelection(p.children.map(\.id).filter { layout.nodes[$0] != nil })
    }

    func selectChildren() {
        guard let id = primaryID, let t = map.topic(id), !t.collapsed else { return }
        setSelection(t.children.map(\.id))
    }

    func navigate(_ direction: NavigationDirection, extend: Bool = false) {
        guard let current = primaryID else {
            select(rootID)
            delegate?.editor(self, reveal: rootID)
            return
        }
        guard let next = layout.neighbor(of: current, direction: direction,
                                         preferredChild: lastVisitedChild[current]) else { return }
        if extend {
            var s = selection
            s.removeAll { $0 == next }
            s.append(next)
            setSelection(s)
        } else {
            select(next)
        }
        delegate?.editor(self, reveal: next)
    }

    // MARK: - 修改（撤销）

    private struct Snapshot {
        var map: MindMap
        var selection: [UUID]
    }

    /// 所有可撤销修改的唯一入口。
    /// - Parameters:
    ///   - coalesce: 相同 key 的连续修改合并成一步撤销（例如连续输入备注）。
    func perform(_ actionName: String, select newSelection: [UUID]? = nil, coalesce: String? = nil,
                 _ change: (inout MindMap) -> Void) {
        commitEditingIfNeeded()
        let before = Snapshot(map: map, selection: selection)
        var updated = map
        change(&updated)
        let index = updated.buildIndex()
        // 端点主题被删掉的联系线一并移除
        updated.relationships.removeAll { index[$0.from] == nil || index[$0.to] == nil }
        guard updated != map else {
            if let newSelection { setSelection(newSelection) }
            return
        }
        map = updated
        selection = (newSelection ?? selection).filter { index[$0] != nil }
        if let rel = selectedRelationship, !map.relationships.contains(where: { $0.id == rel }) { selectedRelationship = nil }

        let canCoalesce: Bool = {
            guard let coalesce, let token = coalesceToken else { return false }
            return token.key == coalesce && token.count == registrationCount && (undoManager?.canUndo ?? false)
                && !(undoManager?.isUndoing ?? false) && !(undoManager?.isRedoing ?? false)
        }()
        if !canCoalesce {
            registerUndo(restoring: before, actionName: actionName)
            if let coalesce { coalesceToken = (coalesce, registrationCount) } else { coalesceToken = nil }
        }
        modelDidChange()
        delegate?.editorSelectionDidChange(self)
    }

    private func registerUndo(restoring snapshot: Snapshot, actionName: String) {
        guard let undoManager else { return }
        registrationCount += 1
        undoManager.registerUndo(withTarget: self) { editor in
            editor.restore(snapshot, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    private func restore(_ snapshot: Snapshot, actionName: String) {
        commitEditingIfNeeded(registerUndo: false)
        let current = Snapshot(map: map, selection: selection)
        var target = snapshot.map
        // 折叠不进入撤销栈：恢复快照时保留当前的折叠状态。
        var folded: [UUID: Bool] = [:]
        map.root.forEach { folded[$0.id] = $0.collapsed }
        target.root.mutateAll { t in
            if let c = folded[t.id] { t.collapsed = c }
        }
        // 联系线的显示 / 隐藏同样不进入撤销栈
        target.relationshipsHidden = map.relationshipsHidden
        map = target
        let index = map.buildIndex()
        selection = snapshot.selection.filter { index[$0] != nil }
        if let rel = selectedRelationship, !map.relationships.contains(where: { $0.id == rel }) { selectedRelationship = nil }
        coalesceToken = nil
        registerUndo(restoring: current, actionName: actionName)
        modelDidChange()
        delegate?.editorSelectionDidChange(self)
    }

    /// 不进入撤销栈的修改（折叠/展开）：直接改并标记文档已修改。
    private func performWithoutUndo(_ change: (inout MindMap) -> Void) {
        var updated = map
        change(&updated)
        guard updated != map else { return }
        map = updated
        document?.updateChangeCount(.changeDone)
        modelDidChange()
    }

    private func modelDidChange() {
        revision &+= 1
        relayout()
        keepSelectionVisible()
        if !findQuery.isEmpty { updateFindResults(keepIndex: true) }
    }

    /// 选中项落在被折叠隐藏的主题上时（例如撤销恢复了旧的选中项，但分支已被折叠），改为选中最近的可见祖先。
    private func keepSelectionVisible() {
        guard selection.contains(where: { layout.nodes[$0] == nil }) else { return }
        var result: [UUID] = []
        for id in selection {
            var current: UUID? = id
            while let c = current, layout.nodes[c] == nil { current = map.parentID(of: c) }
            if let c = current, !result.contains(c) { result.append(c) }
        }
        selection = result
    }

    /// 保存用的导图：正在行内编辑的文字也包含进去，但不结束编辑（自动保存不能打断输入）。
    var mapForSaving: MindMap {
        guard let editingID, let editingText else { return map }
        var m = map
        m.update(editingID) { $0.title = editingText }
        return m
    }

    /// 保存后断开撤销合并：保存之后的下一次修改必须重新注册撤销，文档才会再次被标记为已修改。
    func breakCoalescing() {
        coalesceToken = nil
    }

    func relayout() {
        var engine = LayoutEngine(map: map, measurer: measurer)
        if let editingID, let editingText { engine.titleOverride = (editingID, editingText) }
        layout = engine.run()
        delegate?.editorLayoutDidChange(self)
    }

    // MARK: - 行内编辑

    func beginEditing(_ id: UUID? = nil, selectAll: Bool = true) {
        // 只能编辑看得见的主题（折叠隐藏的主题没有输入框位置）
        guard let id = id ?? primaryID, map.contains(id), layout.nodes[id] != nil else { return }
        if editingID != nil, editingID != id { commitEditingIfNeeded() }
        if selection != [id] { setSelection([id]) }
        editingID = id
        editingText = map.topic(id)?.title
        editingMarkedDirty = false
        delegate?.editor(self, beginEditing: id, selectAll: selectAll)
    }

    /// 输入框文字变化：实时重排，但不写入模型（不产生撤销步骤）。
    /// 第一次变化时把文档标记为已修改，这样关闭窗口、退出应用时编辑中的文字会被保存。
    func editingTextDidChange(_ text: String) {
        guard editingID != nil else { return }
        editingText = text
        if !editingMarkedDirty {
            editingMarkedDirty = true
            document?.updateChangeCount(.changeDone)
        }
        relayout()
    }

    /// 结束编辑并写回标题。
    func endEditing(commit: Bool) {
        guard let id = editingID else { return }
        let text = editingText
        finishEditingSession()
        if commit, let text, map.topic(id)?.title != text {
            perform(L("Edit Topic")) { $0.update(id) { $0.title = text } }
        } else {
            relayout()
        }
    }

    func commitEditingIfNeeded(registerUndo: Bool = true) {
        guard editingID != nil else { return }
        if registerUndo {
            endEditing(commit: true)
        } else {
            finishEditingSession()
        }
    }

    private func finishEditingSession() {
        editingID = nil
        editingText = nil
        // 编辑期间临时加的“已修改”计数抵消掉；真正的修改由撤销注册重新计数
        if editingMarkedDirty {
            editingMarkedDirty = false
            document?.updateChangeCount(.changeUndone)
        }
        delegate?.editorEndEditing(self)
    }

    var isEditing: Bool { editingID != nil }

    // MARK: - 新建主题

    func defaultTitle(forDepth depth: Int) -> String {
        depth <= 1 ? L("Main Topic") : L("Subtopic")
    }

    /// 插入子主题（Tab）。
    func addChild(to parent: UUID? = nil, title: String? = nil, edit: Bool = true) {
        guard let parentID = parent ?? primaryID ?? Optional(rootID),
              let depth = map.path(of: parentID)?.count else { return }
        let topic = Topic(title: title ?? defaultTitle(forDepth: depth + 1))
        perform(L("Insert Subtopic"), select: [topic.id]) { m in
            m.update(parentID) { p in
                p.collapsed = false
                p.children.append(topic)
            }
        }
        delegate?.editor(self, reveal: topic.id)
        if edit { beginEditing(topic.id) }
    }

    /// 插入同级主题（Return / Shift-Return）。
    func addSibling(before: Bool = false, edit: Bool = true) {
        guard let id = primaryID else { addChild(to: rootID); return }
        guard let path = map.path(of: id), let index = path.last, let parentID = map.parentID(of: id) else {
            addChild(to: id)
            return
        }
        let topic = Topic(title: defaultTitle(forDepth: path.count))
        perform(before ? L("Insert Topic Before") : L("Insert Topic"), select: [topic.id]) { m in
            m.insert(topic, into: parentID, at: before ? index : index + 1)
        }
        delegate?.editor(self, reveal: topic.id)
        if edit { beginEditing(topic.id) }
    }

    /// 插入父主题（⌘Return）：新主题占据原位置，原主题（以及一起选中的兄弟主题）成为它的子主题。
    func insertParent() {
        guard let id = primaryID, let parentID = map.parentID(of: id), let parent = map.topic(parentID) else { return }
        let siblings = map.topmost(selection).filter { map.parentID(of: $0) == parentID }
        let moving = parent.children.filter { siblings.contains($0.id) }
        guard let firstIndex = parent.children.firstIndex(where: { siblings.contains($0.id) }),
              let depth = map.path(of: id)?.count else { return }
        var newTopic = Topic(title: defaultTitle(forDepth: depth))
        newTopic.children = moving
        perform(L("Insert Parent Topic"), select: [newTopic.id]) { m in
            m.update(parentID) { p in
                p.children.removeAll { siblings.contains($0.id) }
                p.children.insert(newTopic, at: min(firstIndex, p.children.count))
            }
        }
        delegate?.editor(self, reveal: newTopic.id)
        beginEditing(newTopic.id)
    }

    /// 插入一个带指定标题的子主题（拖入文件等场景）。
    @discardableResult
    func insertTopics(_ topics: [Topic], into parentID: UUID, at index: Int? = nil, actionName: String) -> [UUID] {
        guard !topics.isEmpty else { return [] }
        perform(actionName, select: topics.map(\.id)) { m in
            m.update(parentID) { p in
                p.collapsed = false
                let i = min(max(index ?? p.children.count, 0), p.children.count)
                p.children.insert(contentsOf: topics, at: i)
            }
        }
        if let last = topics.last { delegate?.editor(self, reveal: last.id) }
        return topics.map(\.id)
    }

    // MARK: - 删除 / 移动

    var canDeleteSelection: Bool { selection.contains { $0 != rootID } }

    func deleteSelection() {
        let ids = map.topmost(selection).filter { $0 != rootID }
        guard let primary = ids.last ?? ids.first,
              let parentID = map.parentID(of: primary),
              let parent = map.topic(parentID),
              let index = parent.children.firstIndex(where: { $0.id == primary }) else { return }
        // 删除后选中：后一个兄弟 → 前一个兄弟 → 父主题
        let removed = Set(ids)
        let remaining = parent.children.enumerated().filter { !removed.contains($0.element.id) }
        let next = remaining.first { $0.offset > index }?.element.id
            ?? remaining.last { $0.offset < index }?.element.id
            ?? parentID
        perform(L("Delete"), select: [next]) { m in
            for id in ids { m.remove(id) }
        }
    }

    /// 只删除主题本身，子主题上移一级。
    func deleteKeepingChildren() {
        guard let id = primaryID, id != rootID, let parentID = map.parentID(of: id),
              let topic = map.topic(id), let index = map.path(of: id)?.last else { return }
        let select = topic.children.first?.id ?? parentID
        perform(L("Delete Topic Only"), select: [select]) { m in
            m.remove(id)
            m.update(parentID) { p in p.children.insert(contentsOf: topic.children, at: min(index, p.children.count)) }
        }
    }

    /// 上移 / 下移（按视觉方向）。
    func moveSelection(up: Bool) {
        guard let id = primaryID, let parentID = map.parentID(of: id),
              let parent = map.topic(parentID), let index = parent.children.firstIndex(where: { $0.id == id }) else { return }
        var delta = up ? -1 : 1
        // 思维导图左侧分支从下往上排列，视觉上的“上移”是数组里往后移。
        if layout.nodes[id]?.side == .left && map.structure == .mindMap && parentID == rootID { delta = -delta }
        if map.structure == .orgChart { delta = up ? -1 : 1 }
        let target = index + delta
        guard target >= 0, target < parent.children.count else { return }
        perform(up ? L("Move Up") : L("Move Down"), select: selection) { m in
            m.update(parentID) { p in p.children.swapAt(index, target) }
        }
        delegate?.editor(self, reveal: id)
    }

    /// 升级（⇧Tab）：成为父主题的下一个兄弟。
    func promoteSelection() {
        guard let id = primaryID, let parentID = map.parentID(of: id), parentID != rootID,
              let grandID = map.parentID(of: parentID),
              let parentIndex = map.path(of: parentID)?.last else { return }
        perform(L("Promote"), select: [id]) { m in
            guard let removed = m.remove(id) else { return }
            m.insert(removed.topic, into: grandID, at: parentIndex + 1)
        }
        delegate?.editor(self, reveal: id)
    }

    /// 降级：成为前一个兄弟的最后一个子主题。
    func demoteSelection() {
        guard let id = primaryID, let parentID = map.parentID(of: id),
              let parent = map.topic(parentID), let index = parent.children.firstIndex(where: { $0.id == id }),
              index > 0 else { return }
        let newParent = parent.children[index - 1].id
        perform(L("Demote"), select: [id]) { m in
            guard let removed = m.remove(id) else { return }
            m.update(newParent) { p in
                p.collapsed = false
                p.children.append(removed.topic)
            }
        }
        delegate?.editor(self, reveal: id)
    }

    /// 拖放移动：把 ids 移到 parentID 的 index 位置。
    func move(_ ids: [UUID], to parentID: UUID, at index: Int?, copy: Bool = false) {
        let moving = map.topmost(ids).filter { $0 != rootID }
        guard !moving.isEmpty else { return }
        if !copy, moving.contains(where: { map.isAncestor($0, of: parentID) }) { return }
        if copy {
            let topics = moving.compactMap { map.topic($0)?.withFreshIDs() }
            insertTopics(topics, into: parentID, at: index, actionName: L("Copy Topics"))
            return
        }
        perform(L("Move Topics"), select: moving) { m in
            // 计算插入位置时要扣掉从同一父主题前面移走的主题
            var insertIndex = index
            var topics: [Topic] = []
            for id in moving {
                if let removed = m.remove(id) {
                    if removed.parentID == parentID, let i = insertIndex, removed.index < i { insertIndex = i - 1 }
                    topics.append(removed.topic)
                }
            }
            m.update(parentID) { p in
                p.collapsed = false
                let i = min(max(insertIndex ?? p.children.count, 0), p.children.count)
                p.children.insert(contentsOf: topics, at: i)
            }
        }
        if let last = moving.last { delegate?.editor(self, reveal: last) }
    }

    // MARK: - 折叠

    func toggleFold(_ ids: [UUID]? = nil) {
        let targets = (ids ?? selection).filter { id in
            guard id != rootID, let t = map.topic(id) else { return false }
            return !t.children.isEmpty
        }
        guard !targets.isEmpty else { return }
        let collapse = !(map.topic(targets[0])?.collapsed ?? false)
        setCollapsed(targets, collapse)
    }

    func setCollapsed(_ ids: [UUID], _ collapsed: Bool) {
        performWithoutUndo { m in
            for id in ids where id != m.root.id {
                m.update(id) { t in if !t.children.isEmpty { t.collapsed = collapsed } }
            }
        }
        // 折叠后，被隐藏的选中项转移到折叠的那个主题上
        if collapsed {
            let visible = selection.filter { layout.nodes[$0] != nil }
            if visible != selection { setSelection(visible.isEmpty ? Array(ids.prefix(1)) : visible) }
        }
    }

    func expandAll() {
        performWithoutUndo { m in m.root.mutateAll { $0.collapsed = false } }
    }

    /// 折叠所有分支，只露出分支主题。
    func collapseAll() {
        performWithoutUndo { m in
            for i in m.root.children.indices {
                m.root.children[i].mutateAll { if !$0.children.isEmpty { $0.collapsed = true } }
            }
        }
        let visible = selection.filter { layout.nodes[$0] != nil }
        setSelection(visible.isEmpty ? [rootID] : visible)
    }

    /// 展开到第 level 层（1 = 只显示分支主题）。
    func expand(toLevel level: Int) {
        performWithoutUndo { m in
            func walk(_ t: inout Topic, depth: Int) {
                if !t.children.isEmpty { t.collapsed = depth >= level }
                for i in t.children.indices { walk(&t.children[i], depth: depth + 1) }
            }
            walk(&m.root, depth: 0)
            m.root.collapsed = false
        }
        let visible = selection.filter { layout.nodes[$0] != nil }
        setSelection(visible.isEmpty ? [rootID] : visible)
    }

    /// 展开祖先使主题可见（查找、跳转时用）。
    func reveal(_ id: UUID) {
        if map.path(of: id) != nil {
            var m = map
            if m.reveal(id) { performWithoutUndo { $0 = m } }
        }
        delegate?.editor(self, reveal: id)
    }

    // MARK: - 主题内容

    func setTitle(_ id: UUID, _ title: String) {
        perform(L("Edit Topic")) { $0.update(id) { $0.title = title } }
    }

    func setNote(_ id: UUID, _ note: String) {
        perform(L("Edit Note"), coalesce: "note-\(id)") { $0.update(id) { $0.note = note } }
    }

    func setLink(_ id: UUID, _ link: String?) {
        let value = link?.trimmingCharacters(in: .whitespacesAndNewlines)
        perform(value?.isEmpty == false ? L("Set Hyperlink") : L("Remove Hyperlink")) {
            $0.update(id) { $0.link = (value?.isEmpty == false) ? value : nil }
        }
    }

    /// 从每个主题各自的标签里去掉一个标签（多选时不影响其他标签）。
    func removeLabel(_ label: String, from ids: [UUID]) {
        perform(L("Edit Labels")) { m in for id in ids { m.update(id) { $0.labels.removeAll { $0 == label } } } }
    }

    func setLabels(_ ids: [UUID], _ labels: [String]) {
        let clean = labels.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var unique: [String] = []
        for l in clean where !unique.contains(l) { unique.append(l) }
        perform(L("Edit Labels")) { m in for id in ids { m.update(id) { $0.labels = unique } } }
    }

    func toggleMarker(_ marker: MarkerID, for ids: [UUID]? = nil) {
        let targets = ids ?? selection
        guard let first = targets.first.flatMap({ map.topic($0) }) else { return }
        let adding = !first.markers.contains(marker)
        perform(adding ? L("Add Marker") : L("Remove Marker")) { m in
            for id in targets {
                m.update(id) { t in
                    let has = t.markers.contains(marker)
                    if adding != has { t.markers = MarkerCatalog.toggle(marker, in: t.markers) }
                }
            }
        }
    }

    func clearMarkers(_ ids: [UUID]? = nil) {
        perform(L("Clear Markers")) { m in for id in ids ?? selection { m.update(id) { $0.markers = [] } } }
    }

    // MARK: - 附件 / 图片

    func addAttachments(_ urls: [URL], to id: UUID) throws {
        guard let store = attachments else { return }
        var added: [Attachment] = []
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                throw NSError(domain: "FreeMind", code: 10, userInfo: [
                    NSLocalizedDescriptionKey: LF("“%@” is a folder. Only files can be attached.", url.lastPathComponent),
                ])
            }
            added.append(try store.add(fileAt: url))
        }
        guard !added.isEmpty else { return }
        perform(added.count > 1 ? L("Add Attachments") : L("Add Attachment"), select: [id]) { m in
            m.update(id) { $0.attachments.append(contentsOf: added) }
        }
    }

    func removeAttachment(_ attachmentID: UUID, from id: UUID) {
        perform(L("Remove Attachment")) { $0.update(id) { $0.attachments.removeAll { $0.id == attachmentID } } }
    }

    func renameAttachment(_ attachmentID: UUID, in id: UUID, to name: String) {
        let clean = AttachmentStore.sanitize(name)
        perform(L("Rename Attachment")) { m in
            m.update(id) { t in
                if let i = t.attachments.firstIndex(where: { $0.id == attachmentID }) { t.attachments[i].name = clean }
            }
        }
    }

    /// 用图片数据设置主题图片。显示尺寸按最长边 200pt 等比缩放。
    func setImage(data: Data, name: String, for id: UUID) {
        guard let store = attachments, let image = NSImage(data: data) else { return }
        let resourceID = store.add(data: data, name: name)
        var size = image.size
        let longest = max(size.width, size.height, 1)
        if longest > 200 { size = CGSize(width: size.width * 200 / longest, height: size.height * 200 / longest) }
        let topicImage = TopicImage(id: resourceID, name: AttachmentStore.sanitize(name),
                                    width: Double(size.width.rounded()), height: Double(size.height.rounded()))
        perform(L("Insert Image"), select: [id]) { $0.update(id) { $0.image = topicImage } }
    }

    func setImage(fileAt url: URL, for id: UUID) throws {
        let data = try Data(contentsOf: url)
        guard NSImage(data: data) != nil else {
            throw NSError(domain: "FreeMind", code: 11, userInfo: [
                NSLocalizedDescriptionKey: LF("“%@” is not an image FreeMind can read.", url.lastPathComponent),
            ])
        }
        setImage(data: data, name: url.lastPathComponent, for: id)
    }

    func removeImage(from id: UUID) {
        perform(L("Remove Image")) { $0.update(id) { $0.image = nil } }
    }

    func resizeImage(of id: UUID, scale: Double) {
        guard let image = map.topic(id)?.image else { return }
        let w = max(24, min(800, image.width * scale)), h = max(24, min(800, image.height * scale))
        guard w != image.width || h != image.height else { return }
        let ratio = image.height / max(image.width, 1)
        let newW = w, newH = (ratio * newW).rounded()
        perform(L("Resize Image"), coalesce: "image-size-\(id)") {
            $0.update(id) { $0.image?.width = newW.rounded(); $0.image?.height = newH }
        }
    }

    func setImageWidth(of id: UUID, width: Double) {
        guard let image = map.topic(id)?.image, image.width > 0 else { return }
        resizeImage(of: id, scale: width / image.width)
    }

    // MARK: - 样式

    func updateStyle(_ ids: [UUID]? = nil, actionName: String = L("Format Topic"), coalesce: String? = nil,
                     _ body: (inout TopicStyle) -> Void) {
        let targets = ids ?? selection
        guard !targets.isEmpty else { return }
        perform(actionName, coalesce: coalesce.map { "\($0)-\(targets)" }) { m in
            for id in targets { m.update(id) { body(&$0.style) } }
        }
    }

    func clearStyle(_ ids: [UUID]? = nil) {
        updateStyle(ids, actionName: L("Reset Style")) { $0 = TopicStyle() }
    }

    func setTheme(_ theme: Theme) {
        perform(L("Change Theme")) { $0.theme = theme }
    }

    /// 修改当前导图内嵌的主题参数（检查器里的“自定义主题”）。
    func updateTheme(_ theme: Theme, coalesce: String? = nil) {
        perform(L("Customize Theme"), coalesce: coalesce.map { "theme-\($0)" }) { $0.theme = theme }
    }

    /// 应用主题时可选：清除所有主题的单独样式，让整张图统一。
    func clearAllTopicStyles() {
        perform(L("Reset All Styles")) { m in
            m.root.mutateAll { t in
                let boundary = t.style.boundary
                t.style = TopicStyle()
                t.style.boundary = boundary
            }
        }
    }

    func setStructure(_ structure: MapStructure) {
        perform(L("Change Structure")) { $0.structure = structure }
    }

    func setSpacing(_ spacing: MapSpacing) {
        perform(L("Change Spacing")) { $0.spacing = spacing }
    }

    func setLineStyle(_ style: LineStyle?) {
        perform(L("Change Line Style")) { $0.lineStyle = style }
    }

    func setTopicMaxWidth(_ width: Double) {
        perform(L("Change Topic Width"), coalesce: "max-width") { $0.topicMaxWidth = width }
    }

    func toggleBoundary(_ ids: [UUID]? = nil) {
        let targets = ids ?? selection
        guard let first = targets.first.flatMap({ map.topic($0) }) else { return }
        let on = !(first.style.boundary ?? false)
        updateStyle(targets, actionName: on ? L("Add Boundary") : L("Remove Boundary")) { $0.boundary = on ? true : nil }
    }

    // MARK: - 联系线

    var selectedRelationshipModel: Relationship? {
        guard let id = selectedRelationship else { return nil }
        return map.relationships.first { $0.id == id }
    }

    func selectRelationship(_ id: UUID?) {
        commitEditingIfNeeded()
        if id != nil, !selection.isEmpty { selection = [] }
        selectedRelationship = id
        delegate?.editorSelectionDidChange(self)
    }

    func addRelationship(from: UUID, to: UUID) {
        guard from != to, map.contains(from), map.contains(to) else { return }
        // 联系线隐藏着时新建一条：先显示出来，否则看不到刚建的线
        if map.relationshipsHidden { setRelationshipsHidden(false) }
        let relationship = Relationship(from: from, to: to)
        perform(L("Add Relationship"), select: []) { $0.relationships.append(relationship) }
        selectRelationship(relationship.id)
    }

    func updateRelationship(_ id: UUID, actionName: String, coalesce: String? = nil, _ body: (inout Relationship) -> Void) {
        perform(actionName, coalesce: coalesce) { m in
            if let i = m.relationships.firstIndex(where: { $0.id == id }) { body(&m.relationships[i]) }
        }
    }

    /// 恢复自动弧度，标签也回到自动放置（避开其他标签）。
    func resetRelationshipShape(_ id: UUID) {
        updateRelationship(id, actionName: L("Reshape Relationship")) { r in
            r.control1 = nil
            r.control2 = nil
            r.labelPosition = nil
        }
    }

    func deleteRelationship(_ id: UUID) {
        perform(L("Delete Relationship")) { $0.relationships.removeAll { $0.id == id } }
        selectRelationship(nil)
    }

    /// 显示 / 隐藏全部联系线。和折叠一样不进入撤销栈，但会标记文档已修改，随文件保存。
    func setRelationshipsHidden(_ hidden: Bool) {
        if hidden, selectedRelationship != nil { selectRelationship(nil) }
        performWithoutUndo { $0.relationshipsHidden = hidden }
    }

    // MARK: - 查找

    private func updateFindResults(keepIndex: Bool = false) {
        let q = findQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            findResults = []
            findIndex = nil
            delegate?.editorSelectionDidChange(self)
            return
        }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        var results: [UUID] = []
        map.root.forEach { t in
            if t.title.range(of: q, options: options) != nil
                || t.labels.contains(where: { $0.range(of: q, options: options) != nil })
                || (findInNotes && t.note.range(of: q, options: options) != nil) {
                results.append(t.id)
            }
        }
        let previous = findIndex.flatMap { findResults.indices.contains($0) ? findResults[$0] : nil }
        findResults = results
        if keepIndex, let previous, let i = results.firstIndex(of: previous) {
            findIndex = i
        } else {
            findIndex = nil
        }
        // 画布需要重画高亮
        delegate?.editorSelectionDidChange(self)
    }

    func findNext(backwards: Bool = false) {
        guard !findResults.isEmpty else { return }
        let count = findResults.count
        let next: Int
        if let i = findIndex {
            next = backwards ? (i - 1 + count) % count : (i + 1) % count
        } else {
            next = backwards ? count - 1 : 0
        }
        findIndex = next
        let id = findResults[next]
        reveal(id)
        select(id)
        delegate?.editor(self, reveal: id)
    }

    var currentFindMatch: UUID? {
        guard let i = findIndex, findResults.indices.contains(i) else { return nil }
        return findResults[i]
    }

    // MARK: - 统计

    var topicCount: Int { map.topicCount }
}
