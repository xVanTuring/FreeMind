import AppKit

/// 修改导图的工具。每次调用先在副本上做完全部修改（中途参数出错就整个放弃，导图不变），
/// 再一次性交给 `MapEditor.perform`：一次调用 = 一个撤销步骤，撤销菜单里显示为“Agent：…”。
extension MCPFacade {
    /// 写工具用：找到文档，并先提交用户正在行内编辑的标题——之后读到的导图就是最终要改的那份，
    /// Agent 的修改不会盖掉用户刚输入的文字。
    func writableDocument(_ args: MCPArgs) throws -> MindMapDocument {
        let doc = try self.document(args)
        doc.editor.commitEditingIfNeeded()
        return doc
    }

    func edit(_ doc: MindMapDocument, _ actionName: String, select: [UUID]? = nil,
              _ change: (inout MindMap) throws -> Void) throws {
        let editor = doc.editor
        editor.commitEditingIfNeeded()
        var updated = editor.map
        try change(&updated)
        guard updated != editor.map else { return }
        // 自己开一个撤销组：不依赖事件循环的自动分组，保证一次调用正好是一步
        let undo = doc.undoManager
        let ownGroup = undo.map { $0.groupingLevel == 0 } ?? false
        if ownGroup { undo?.beginUndoGrouping() }
        editor.perform(LF("Agent: %@", actionName), select: select) { $0 = updated }
        if ownGroup { undo?.endUndoGrouping() }
    }

    // MARK: - 参数转换

    static let allMarkers: [MarkerID] = MarkerGroup.allCases.flatMap { MarkerCatalog.markers(in: $0) }

    static var markerHelp: String {
        let colors = MarkerColorName.allCases.map(\.rawValue).joined(separator: ", ")
        let symbols = MarkerCatalog.symbols.map(\.key).joined(separator: ", ")
        return "priority-1 … priority-6, task-0 / task-25 / task-50 / task-75 / task-100 (progress), "
            + "flag-<color>, star-<color> (colors: \(colors)), symbol-<name> (\(symbols))"
    }

    /// 标记 id 列表：校验名字，同组互斥的只保留最后一个。
    func markers(_ raw: [String], adding base: [MarkerID] = []) throws -> [MarkerID] {
        var result = base
        for r in raw {
            let id = MarkerID(r.trimmingCharacters(in: .whitespaces).lowercased())
            guard Self.allMarkers.contains(id) else {
                throw MCPToolError("Unknown marker '\(r)'. Valid markers: \(Self.markerHelp).")
            }
            if !result.contains(id) { result = MarkerCatalog.toggle(id, in: result) }
        }
        return result
    }

    static func cleanLabels(_ labels: [String]) -> [String] {
        var unique: [String] = []
        for l in labels.map({ $0.trimmingCharacters(in: .whitespaces) }) where !l.isEmpty && !unique.contains(l) {
            unique.append(l)
        }
        return unique
    }

    static func cleanLink(_ link: String?) -> String? {
        let value = link?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    /// 颜色：`#RRGGBB` / `#RRGGBBAA`，填充和边框还可以是 `none`。
    static func paint(_ raw: String, key: String) throws -> Paint {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.lowercased() == "none" { return .none }
        guard NSColor(hex: value) != nil else {
            throw MCPToolError("'\(key)' must be a hex color such as #E5484D (or \"none\"), got '\(raw)'.")
        }
        return Paint((value.hasPrefix("#") ? "" : "#") + value.uppercased())
    }

    /// 把 `style` 对象里出现的字段写进样式；值为 null 表示清除这一项、恢复跟随风格。
    static func applyStyle(_ object: MCPObject, to style: inout TopicStyle) throws {
        let a = MCPArgs(object)
        func color(_ key: String, _ path: WritableKeyPath<TopicStyle, Paint?>) throws {
            if a.isNull(key) { style[keyPath: path] = nil }
            if let v = try a.string(key) { style[keyPath: path] = try paint(v, key: key) }
        }
        try color("fill", \.fill)
        try color("text_color", \.textColor)
        try color("border", \.border)
        try color("branch_color", \.branchColor)
        if a.isNull("shape") { style.shape = nil }
        if let v = try a.string("shape") {
            guard let shape = TopicShape(rawValue: v) else {
                throw MCPToolError("Unknown shape '\(v)'. Use one of: \(TopicShape.allCases.map(\.rawValue).joined(separator: ", ")).")
            }
            style.shape = shape
        }
        if a.isNull("font_size") { style.fontSize = nil }
        if let v = try a.double("font_size") { style.fontSize = min(max(v, 8), 96) }
        if a.isNull("bold") { style.bold = nil }
        if let v = try a.bool("bold") { style.bold = v }
        if a.isNull("italic") { style.italic = nil }
        if let v = try a.bool("italic") { style.italic = v }
        if a.isNull("boundary") { style.boundary = nil }
        if let v = try a.bool("boundary") { style.boundary = v ? true : nil }
    }

    /// 嵌套的主题描述 → 主题树。
    func makeTopics(_ specs: [MCPObject], level: Int = 0) throws -> [Topic] {
        guard level < 64 else { throw MCPInvalidParams("topics are nested too deeply") }
        return try specs.map { spec in
            let a = MCPArgs(spec)
            var t = Topic(title: try a.requiredString("title"))
            t.note = try a.string("note") ?? ""
            t.link = Self.cleanLink(try a.string("link"))
            t.labels = Self.cleanLabels(try a.stringArray("labels") ?? [])
            t.markers = try markers(try a.stringArray("markers") ?? [])
            if let style = try a.object("style") { try Self.applyStyle(style, to: &t.style) }
            t.children = try makeTopics(try a.objectArray("children") ?? [], level: level + 1)
            let collapsed = try a.bool("collapsed") ?? false
            t.collapsed = collapsed && !t.children.isEmpty
            return t
        }
    }

    // MARK: - 主题

    func addTopics(_ args: MCPArgs) throws -> MCPToolResult {
        let doc = try writableDocument(args)
        let map = doc.editor.map
        let parentID = try topicID(try args.string("parent_id") ?? "root", in: map)
        var topics: [Topic] = []
        if let specs = try args.objectArray("topics") { topics += try makeTopics(specs) }
        if let markdown = try args.string("markdown") { topics += MarkdownImporter.parseFragment(markdown) }
        guard !topics.isEmpty else {
            throw MCPInvalidParams("pass 'topics' (an array of topic objects) or 'markdown' (an outline) with at least one topic")
        }
        let index = try args.int("index")
        try edit(doc, L("Insert Topics")) { m in
            m.update(parentID) { p in
                p.collapsed = false
                let i = min(max(index ?? p.children.count, 0), p.children.count)
                p.children.insert(contentsOf: topics, at: i)
            }
        }
        let count = topics.reduce(0) { $0 + $1.subtreeCount }
        var lines = ["Added \(count) topic(s) under \(Self.ref(doc.editor.map.topic(parentID) ?? map.root)):"]
        for t in topics { outline(t, depth: nil, includeNotes: false, into: &lines) }
        return MCPToolResult(text: lines.joined(separator: "\n"),
                             structured: ["created_ids": topics.map { Self.shortID($0.id) }])
    }

    func updateTopics(_ args: MCPArgs) throws -> MCPToolResult {
        let doc = try writableDocument(args)
        let map = doc.editor.map
        guard let updates = try args.objectArray("updates"), !updates.isEmpty else {
            throw MCPInvalidParams("'updates' must be a non-empty array")
        }
        var touched: [UUID] = []
        var updated = map
        for update in updates {
            let a = MCPArgs(update)
            let id = try topicID(try a.requiredString("topic_id"), in: map)
            guard var t = updated.topic(id) else { continue }
            if let title = try a.string("title") {
                guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw MCPToolError("A topic title cannot be empty.")
                }
                t.title = title
            }
            if a.isNull("note") { t.note = "" }
            if let note = try a.string("note") { t.note = note }
            if a.isNull("link") { t.link = nil }
            if a.has("link") { t.link = Self.cleanLink(try a.string("link")) }
            if a.isNull("labels") { t.labels = [] }
            if let labels = try a.stringArray("labels") { t.labels = Self.cleanLabels(labels) }
            if a.isNull("markers") { t.markers = [] }
            if let list = try a.stringArray("markers") { t.markers = try markers(list) }
            if let list = try a.stringArray("add_markers") { t.markers = try markers(list, adding: t.markers) }
            if let list = try a.stringArray("remove_markers") {
                let remove = Set(list.map { MarkerID($0.trimmingCharacters(in: .whitespaces).lowercased()) })
                t.markers.removeAll { remove.contains($0) }
            }
            if try a.bool("reset_style") == true { t.style = TopicStyle() }
            if let style = try a.object("style") { try Self.applyStyle(style, to: &t.style) }
            let final = t
            updated.update(id) { $0 = final }
            if !touched.contains(id) { touched.append(id) }
        }
        try edit(doc, L("Edit Topics")) { $0 = updated }
        let now = doc.editor.map
        let lines = touched.compactMap { now.topic($0) }.map { "- " + Self.summaryLine($0) }
        return MCPToolResult(text: "Updated \(touched.count) topic(s):\n" + lines.joined(separator: "\n"))
    }

    func moveTopics(_ args: MCPArgs) throws -> MCPToolResult {
        let doc = try writableDocument(args)
        let map = doc.editor.map
        let ids = try topicIDs(try args.requiredStringArray("topic_ids"), in: map)
        let parentID = try topicID(try args.requiredString("parent_id"), in: map)
        guard !ids.contains(map.root.id) else { throw MCPToolError("The central topic cannot be moved.") }
        let moving = map.topmost(ids)
        if let bad = moving.first(where: { map.isAncestor($0, of: parentID) }), let t = map.topic(bad) {
            throw MCPToolError("Cannot move \(Self.ref(t)) into itself or one of its own subtopics.")
        }
        let index = try args.int("index")
        try edit(doc, L("Move Topics")) { m in
            // 从同一个父主题里、插入位置前面移走的主题会让位置前移
            var insertIndex = index
            var topics: [Topic] = []
            for id in moving {
                guard let removed = m.remove(id) else { continue }
                if removed.parentID == parentID, let i = insertIndex, removed.index < i { insertIndex = i - 1 }
                topics.append(removed.topic)
            }
            m.update(parentID) { p in
                p.collapsed = false
                let i = min(max(insertIndex ?? p.children.count, 0), p.children.count)
                p.children.insert(contentsOf: topics, at: i)
            }
        }
        let parent = doc.editor.map.topic(parentID).map(Self.ref) ?? ""
        return MCPToolResult(text: "Moved \(moving.count) topic(s) under \(parent).")
    }

    func deleteTopics(_ args: MCPArgs) throws -> MCPToolResult {
        let doc = try writableDocument(args)
        let editor = doc.editor
        let map = editor.map
        let ids = try topicIDs(try args.requiredStringArray("topic_ids"), in: map)
        guard !ids.contains(map.root.id) else { throw MCPToolError("The central topic cannot be deleted.") }
        let keepChildren = try args.bool("keep_children") ?? false
        let targets = map.topmost(ids)
        var updated = map
        var removedCount = 0
        for id in targets {
            guard let removed = updated.remove(id) else { continue }
            if keepChildren {
                removedCount += 1
                updated.update(removed.parentID) { p in
                    p.children.insert(contentsOf: removed.topic.children, at: min(removed.index, p.children.count))
                }
            } else {
                removedCount += removed.topic.subtreeCount
            }
        }
        // 选中的主题被删光时改选第一个被删主题的父主题
        let remaining = editor.selection.filter { updated.contains($0) }
        let fallback = targets.first.flatMap { map.parentID(of: $0) }.map { [$0] }
        try edit(doc, L("Delete Topics"), select: remaining.isEmpty ? fallback : nil) { $0 = updated }
        return MCPToolResult(text: "Deleted \(removedCount) topic(s)"
                             + (keepChildren ? "; their subtopics moved up one level." : " including their subtopics.")
                             + " The user can undo this with Command-Z.")
    }

    func foldTopics(_ args: MCPArgs) throws -> MCPToolResult {
        let doc = try writableDocument(args)
        let editor = doc.editor
        let action = try args.requiredString("action")
        switch action {
        case "collapse", "expand":
            let ids = try topicIDs(try args.requiredStringArray("topic_ids"), in: editor.map)
            editor.setCollapsed(ids, action == "collapse")
        case "expand_all":
            editor.expandAll()
        case "collapse_all":
            editor.collapseAll()
        case "show_levels":
            guard let level = try args.int("level"), level >= 1 else {
                throw MCPInvalidParams("'level' (1 or more) is required for show_levels")
            }
            editor.expand(toLevel: level)
        default:
            throw MCPInvalidParams("unknown action '\(action)'")
        }
        return MCPToolResult(text: "Done. \(editor.layout.order.count) of \(editor.map.topicCount) topics are visible.")
    }

    func selectTopics(_ args: MCPArgs) throws -> MCPToolResult {
        let doc = try writableDocument(args)
        let editor = doc.editor
        let ids = try topicIDs(try args.requiredStringArray("topic_ids"), in: editor.map)
        // 先展开祖先，被折叠的主题才能选中
        for id in ids { editor.reveal(id) }
        editor.setSelection(ids)
        if let last = ids.last { editor.reveal(last) }
        return MCPToolResult(text: "Selected " + editor.selectedTopics.map(Self.ref).joined(separator: ", ") + ".")
    }

    // MARK: - 联系线

    func addRelationship(_ args: MCPArgs) throws -> MCPToolResult {
        let doc = try writableDocument(args)
        let map = doc.editor.map
        let from = try topicID(try args.requiredString("from_id"), in: map)
        let to = try topicID(try args.requiredString("to_id"), in: map)
        guard from != to else { throw MCPToolError("A relationship needs two different topics.") }
        let relationship = Relationship(from: from, to: to, title: try args.string("title") ?? "")
        try edit(doc, L("Add Relationship")) { $0.relationships.append(relationship) }
        return MCPToolResult(text: "Added relationship [\(Self.shortID(relationship.id))].",
                             structured: ["relationship_id": Self.shortID(relationship.id)])
    }

    func updateRelationship(_ args: MCPArgs) throws -> MCPToolResult {
        let doc = try writableDocument(args)
        let id = try relationshipID(try args.requiredString("relationship_id"), in: doc.editor.map)
        let color: Paint?? = args.isNull("color") ? .some(nil) : try args.string("color").map { try Self.paint($0, key: "color") }
        let title = try args.string("title")
        let dashed = try args.bool("dashed")
        let arrowStart = try args.bool("arrow_start")
        let arrowEnd = try args.bool("arrow_end")
        try edit(doc, L("Edit Relationship")) { m in
            guard let i = m.relationships.firstIndex(where: { $0.id == id }) else { return }
            if let title { m.relationships[i].title = title }
            if let dashed { m.relationships[i].dashed = dashed }
            if let arrowStart { m.relationships[i].arrowStart = arrowStart }
            if let arrowEnd { m.relationships[i].arrowEnd = arrowEnd }
            if let color { m.relationships[i].color = color }
        }
        return MCPToolResult(text: "Updated relationship [\(Self.shortID(id))].")
    }

    func deleteRelationship(_ args: MCPArgs) throws -> MCPToolResult {
        let doc = try writableDocument(args)
        let id = try relationshipID(try args.requiredString("relationship_id"), in: doc.editor.map)
        try edit(doc, L("Delete Relationship")) { $0.relationships.removeAll { $0.id == id } }
        if doc.editor.selectedRelationship == id { doc.editor.selectRelationship(nil) }
        return MCPToolResult(text: "Deleted relationship [\(Self.shortID(id))].")
    }

    // MARK: - 整张导图

    static func theme(named raw: String) throws -> Theme {
        let library = ThemeLibrary.shared
        if let theme = library.theme(id: raw) { return theme }
        if let theme = library.allThemes.first(where: {
            $0.displayName.caseInsensitiveCompare(raw) == .orderedSame || $0.name.caseInsensitiveCompare(raw) == .orderedSame
        }) { return theme }
        let names = library.allThemes.map { "\($0.id) (\($0.displayName))" }.joined(separator: ", ")
        throw MCPToolError("Unknown theme '\(raw)'. Available themes: \(names).")
    }

    static func structure(_ raw: String) throws -> MapStructure {
        guard let s = MapStructure(rawValue: raw) else {
            throw MCPToolError("Unknown structure '\(raw)'. Use one of: \(MapStructure.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        return s
    }

    func setMapFormat(_ args: MCPArgs) throws -> MCPToolResult {
        let doc = try writableDocument(args)
        let structure = try args.string("structure").map(Self.structure)
        let theme = try args.string("theme").map(Self.theme(named:))
        let spacing = try args.string("spacing").map { raw -> MapSpacing in
            guard let s = MapSpacing(rawValue: raw) else { throw MCPToolError("Unknown spacing '\(raw)'.") }
            return s
        }
        var lineStyle: LineStyle?? = nil
        if let raw = try args.string("line_style") {
            if raw == "theme" {
                lineStyle = .some(nil)
            } else {
                guard let s = LineStyle(rawValue: raw) else { throw MCPToolError("Unknown line style '\(raw)'.") }
                lineStyle = .some(s)
            }
        }
        let width = try args.double("topic_max_width").map { min(max($0, 120), 600) }
        try edit(doc, L("Change Map Format")) { m in
            if let structure { m.structure = structure }
            if let theme { m.theme = theme }
            if let spacing { m.spacing = spacing }
            if let lineStyle { m.lineStyle = lineStyle }
            if let width { m.topicMaxWidth = width }
        }
        let map = doc.editor.map
        return MCPToolResult(text: "Map format: structure \(map.structure.rawValue) · theme \(map.theme.displayName) · "
                             + "spacing \(map.spacing.rawValue) · lines \(map.effectiveLineStyle.rawValue)"
                             + (map.lineStyle == nil ? " (from theme)" : "") + " · topic width \(Int(map.topicMaxWidth)).")
    }

    // MARK: - 文档

    func createMap(_ args: MCPArgs) throws -> MCPToolResult {
        let prefs = Preferences.shared
        let title = try args.string("title")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let markdown = try args.string("markdown")
        var map: MindMap
        if let title, !title.isEmpty {
            map = MindMap(root: Topic(title: title, children: markdown.map(MarkdownImporter.parseFragment) ?? []))
        } else if let markdown, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            map = MarkdownImporter.parse(markdown, defaultTitle: L("Central Topic")).map
        } else {
            map = MindMap(root: Topic(title: L("Central Topic")))
        }
        map.structure = try args.string("structure").map(Self.structure) ?? prefs.defaultStructure
        map.theme = try args.string("theme").map(Self.theme(named:)) ?? prefs.defaultTheme
        map.spacing = prefs.defaultSpacing
        if let specs = try args.objectArray("topics") { map.root.children += try makeTopics(specs) }
        guard let doc = DocumentController.sharedController.openUntitled(map: map, resources: [:], displayName: nil,
                                                                         markEdited: true) else {
            throw MCPToolError("FreeMind could not create a new map.")
        }
        var lines = ["Created \(mapHeader(doc)). It is not saved to a file yet; use save_map with a path to save it.", ""]
        outline(doc.editor.map.root, depth: nil, includeNotes: false, into: &lines)
        return MCPToolResult(text: lines.joined(separator: "\n"), structured: ["map_id": doc.agentID])
    }

    func openMap(_ args: MCPArgs) async throws -> MCPToolResult {
        let raw = try args.requiredString("path")
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { throw MCPToolError("No file at \(url.path).") }
        let controller = DocumentController.sharedController
        let ext = url.pathExtension.lowercased()
        if DocumentTypes.importableExtensions.contains(ext) {
            // 导入：自己处理，出错时把原因告诉 Agent，而不是在 App 里弹警告框
            let results = try Importer.importAll(at: url)
            let docs = results.compactMap { result in
                controller.openUntitled(map: result.map, resources: result.resources,
                                        displayName: results.count > 1 ? result.title : url.deletingPathExtension().lastPathComponent,
                                        markEdited: true)
            }
            guard !docs.isEmpty else { throw MCPToolError("Nothing could be imported from \(url.lastPathComponent).") }
            return MCPToolResult(text: "Imported \(url.lastPathComponent) as a new unsaved map: "
                                 + docs.map(mapHeader).joined(separator: "; "),
                                 structured: ["map_ids": docs.map(\.agentID)])
        }
        guard ext == DocumentTypes.fileExtension else {
            throw MCPToolError("FreeMind opens .fmind maps and imports \(DocumentTypes.importableExtensions.joined(separator: ", ")) files.")
        }
        let doc: NSDocument = try await withCheckedThrowingContinuation { continuation in
            controller.openDocument(withContentsOf: url, display: true) { doc, _, error in
                if let doc { continuation.resume(returning: doc) } else {
                    continuation.resume(throwing: MCPToolError(error?.localizedDescription ?? "Could not open \(url.path)."))
                }
            }
        }
        guard let map = doc as? MindMapDocument else { throw MCPToolError("Could not open \(url.path).") }
        return MCPToolResult(text: "Opened " + mapHeader(map) + ".", structured: ["map_id": map.agentID])
    }

    func saveMap(_ args: MCPArgs) async throws -> MCPToolResult {
        let doc = try writableDocument(args)
        let url: URL
        let operation: NSDocument.SaveOperationType
        if let raw = try args.string("path"), !raw.isEmpty {
            var target = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath).standardizedFileURL
            if target.pathExtension.lowercased() != DocumentTypes.fileExtension {
                target.appendPathExtension(DocumentTypes.fileExtension)
            }
            if target != doc.fileURL?.standardizedFileURL, FileManager.default.fileExists(atPath: target.path) {
                throw MCPToolError("A file already exists at \(target.path). Choose another path; FreeMind will not overwrite it.")
            }
            url = target
            operation = target == doc.fileURL?.standardizedFileURL ? .saveOperation : .saveAsOperation
        } else {
            guard let fileURL = doc.fileURL else {
                throw MCPToolError("This map has never been saved. Pass 'path' (for example ~/Documents/Plan.fmind).")
            }
            url = fileURL
            operation = .saveOperation
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            doc.save(to: url, ofType: DocumentTypes.map, for: operation) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        return MCPToolResult(text: "Saved \(mapHeader(doc)) to \(url.path).", structured: ["path": url.path])
    }
}
