import AppKit

/// MCP 工具与导图之间唯一的接触面：找文档、解析主题 id、把导图格式化成给模型读的文字。
/// 修改操作在 `MCPFacade+Edit.swift`，全部经过 `MapEditor.perform`，和界面操作走同一条路径。
@MainActor
final class MCPFacade {
    /// 当前打开的导图，第一个是最前面窗口里的。测试里换成固定列表。
    var documents: () -> [MindMapDocument] = { MCPFacade.openDocuments() }

    /// 按窗口前后顺序排列的打开文档（没有窗口的排在最后）。
    static func openDocuments() -> [MindMapDocument] {
        let ordered = NSApp.orderedWindows.compactMap { $0.windowController?.document as? MindMapDocument }
        let all = NSDocumentController.shared.documents.compactMap { $0 as? MindMapDocument }
        var result: [MindMapDocument] = []
        for doc in ordered + all where !result.contains(where: { $0 === doc }) { result.append(doc) }
        return result
    }

    // MARK: - 查找

    /// `map_id` 可以是 list_maps 给出的编号、文件路径或窗口标题；不传就是最前面的导图。
    func document(_ args: MCPArgs) throws -> MindMapDocument {
        let docs = documents()
        guard let key = try args.string("map_id")?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            guard let front = docs.first else {
                throw MCPToolError("No map is open in FreeMind. Use create_map or open_map first.")
            }
            return front
        }
        if let doc = docs.first(where: { $0.agentID.caseInsensitiveCompare(key) == .orderedSame }) { return doc }
        let path = URL(fileURLWithPath: (key as NSString).expandingTildeInPath).standardizedFileURL.path
        if let doc = docs.first(where: { $0.fileURL?.standardizedFileURL.path == path }) { return doc }
        let named = docs.filter { $0.displayName.caseInsensitiveCompare(key) == .orderedSame }
        if named.count == 1 { return named[0] }
        throw MCPToolError("No open map matches map_id '\(key)'. Call list_maps to see the open maps.")
    }

    static func shortID(_ id: UUID) -> String { String(id.uuidString.prefix(8)).lowercased() }

    /// 主题 id：完整 UUID、至少 4 位的唯一前缀，或 `root`（中心主题）。
    func topicID(_ raw: String, in map: MindMap) throws -> UUID {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if key == "root" || key == "central" { return map.root.id }
        if let uuid = UUID(uuidString: key), map.contains(uuid) { return uuid }
        guard key.count >= 4 else {
            throw MCPToolError("'\(raw)' is not a topic id. Use the 8-character ids printed by get_map, or \"root\".")
        }
        var found: [UUID] = []
        map.root.forEach { if $0.id.uuidString.lowercased().hasPrefix(key) { found.append($0.id) } }
        switch found.count {
        case 1: return found[0]
        case 0: throw MCPToolError("No topic with id '\(raw)' in this map. Call get_map to see the current ids.")
        default: throw MCPToolError("Topic id '\(raw)' matches several topics; use more characters.")
        }
    }

    func topicIDs(_ raw: [String], in map: MindMap) throws -> [UUID] {
        var result: [UUID] = []
        for r in raw {
            let id = try topicID(r, in: map)
            if !result.contains(id) { result.append(id) }
        }
        return result
    }

    func relationshipID(_ raw: String, in map: MindMap) throws -> UUID {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        let found = map.relationships.filter { $0.id.uuidString.lowercased().hasPrefix(key) }
        guard key.count >= 4, found.count == 1 else {
            throw MCPToolError(found.count > 1
                ? "Relationship id '\(raw)' matches several relationships; use more characters."
                : "No relationship with id '\(raw)' in this map. get_map lists relationships at the end.")
        }
        return found[0].id
    }

    // MARK: - 格式化

    static func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\\n")
    }

    /// `[a1b2c3d4] 标题`
    static func ref(_ topic: Topic) -> String { "[\(shortID(topic.id))] \(oneLine(topic.title))" }

    /// 从中心主题到该主题的标题路径，如 `项目 › 调研 › 竞品`。
    func pathText(_ id: UUID, in map: MindMap) -> String {
        guard let path = map.path(of: id) else { return "" }
        var titles = [Self.oneLine(map.root.title)]
        var current = map.root
        for i in path {
            current = current.children[i]
            titles.append(Self.oneLine(current.title))
        }
        return titles.joined(separator: " › ")
    }

    /// 一行主题摘要：id、标题和各种附加信息。
    static func summaryLine(_ t: Topic) -> String {
        var parts = [ref(t)]
        if !t.markers.isEmpty { parts.append("markers: " + t.markers.map(\.rawValue).joined(separator: ", ")) }
        if !t.labels.isEmpty { parts.append("labels: " + t.labels.joined(separator: ", ")) }
        if let link = t.link, t.hasLink { parts.append("link: " + link) }
        if !t.attachments.isEmpty { parts.append(t.attachments.count == 1 ? "1 attachment" : "\(t.attachments.count) attachments") }
        if t.image != nil { parts.append("image") }
        if t.style.boundary == true { parts.append("boundary") }
        if t.collapsed, !t.children.isEmpty { parts.append("collapsed") }
        return parts.joined(separator: " · ")
    }

    /// 缩进大纲。`depth` 是起点以下最多展开几层（nil = 全部），超出的分支只写一句还有多少主题。
    func outline(_ topic: Topic, depth: Int?, includeNotes: Bool, level: Int = 0, into lines: inout [String]) {
        let indent = String(repeating: "  ", count: level)
        var line = indent + Self.summaryLine(topic)
        let truncated = depth.map { level >= $0 } ?? false
        if truncated, !topic.children.isEmpty {
            line += " · +" + Self.count(topic.subtreeCount - 1, "more topic")
        }
        lines.append(line)
        if includeNotes, topic.hasNote {
            let noteLines = topic.note.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
            for (i, l) in noteLines.enumerated() {
                lines.append(indent + (i == 0 ? "  note: " : "        ") + l)
            }
        }
        guard !truncated else { return }
        for child in topic.children {
            outline(child, depth: depth, includeNotes: includeNotes, level: level + 1, into: &lines)
        }
    }

    func relationshipLines(_ map: MindMap) -> [String] {
        map.relationships.compactMap { r in
            guard let from = map.topic(r.from), let to = map.topic(r.to) else { return nil }
            var line = "[\(Self.shortID(r.id))] \(Self.ref(from)) → \(Self.ref(to))"
            if !r.title.isEmpty { line += " · \"\(Self.oneLine(r.title))\"" }
            return line
        }
    }

    func mapHeader(_ doc: MindMapDocument) -> String {
        let map = doc.editor.map
        var parts = ["Map \"\(doc.displayName ?? "")\" (map_id \(doc.agentID))",
                     "structure: \(map.structure.rawValue)",
                     "theme: \(map.theme.displayName)",
                     Self.count(map.topicCount, "topic")]
        if !map.relationships.isEmpty { parts.append(Self.count(map.relationships.count, "relationship")) }
        return parts.joined(separator: " · ")
    }

    /// `1 topic` / `3 topics`
    static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    /// 主题样式覆盖（只列出设置过的项）。
    static func styleObject(_ s: TopicStyle) -> MCPObject {
        var o: MCPObject = [:]
        if let v = s.shape { o["shape"] = v.rawValue }
        if let v = s.fill { o["fill"] = v.rawValue }
        if let v = s.textColor { o["text_color"] = v.rawValue }
        if let v = s.border { o["border"] = v.rawValue }
        if let v = s.fontSize { o["font_size"] = v }
        if let v = s.bold { o["bold"] = v }
        if let v = s.italic { o["italic"] = v }
        if let v = s.branchColor { o["branch_color"] = v.rawValue }
        if let v = s.boundary { o["boundary"] = v }
        return o
    }

    // MARK: - 读取

    func listMaps(writeAllowed: Bool) -> MCPToolResult {
        let docs = documents()
        var lines: [String] = []
        var items: [MCPObject] = []
        for (i, doc) in docs.enumerated() {
            let editor = doc.editor
            let map = editor.map
            var line = "- \(doc.agentID): \"\(doc.displayName ?? "")\""
            if i == 0 { line += " (frontmost)" }
            line += " · " + (doc.fileURL?.path ?? "never saved")
            if doc.isDocumentEdited { line += " · unsaved changes" }
            line += " · \(map.topicCount) topics · central topic: \(Self.ref(map.root))"
            let selected = editor.selectedTopics
            if !selected.isEmpty { line += " · selected: " + selected.map(Self.ref).joined(separator: ", ") }
            lines.append(line)
            items.append([
                "map_id": doc.agentID,
                "title": doc.displayName ?? "",
                "path": doc.fileURL?.path ?? NSNull(),
                "frontmost": i == 0,
                "unsaved_changes": doc.isDocumentEdited,
                "topic_count": map.topicCount,
                "central_topic": ["id": Self.shortID(map.root.id), "title": map.root.title],
                "selected_topic_ids": selected.map { Self.shortID($0.id) },
            ])
        }
        var text = docs.isEmpty ? "No maps are open. Use create_map or open_map." : "Open maps (front to back):\n" + lines.joined(separator: "\n")
        text += "\nEditing by agents is " + (writeAllowed ? "allowed." : "turned off (read-only). Write tools will fail until the user turns on \"Allow agents to edit maps\" in Settings › Agent.")
        return MCPToolResult(text: text, structured: ["maps": items, "write_allowed": writeAllowed])
    }

    func getMap(_ args: MCPArgs) throws -> MCPToolResult {
        let doc = try document(args)
        let map = doc.editor.map
        let start = try args.string("topic_id").map { try topicID($0, in: map) } ?? map.root.id
        guard let topic = map.topic(start) else { throw MCPToolError("Topic not found.") }
        let depth = try args.int("depth").map { max($0, 0) }

        if try args.string("format") == "markdown" {
            var options = MarkdownExportOptions()
            options.includeNotes = try args.bool("include_notes") ?? true
            options.includeLabels = true
            var sub = MindMap(root: topic)
            if let depth { Self.prune(&sub.root, depth: depth) }
            return MCPToolResult(text: MarkdownExporter.export(sub, options: options).text)
        }

        var lines = [mapHeader(doc)]
        if start != map.root.id { lines.append("Subtree of: " + pathText(start, in: map)) }
        let selected = doc.editor.selectedTopics
        if !selected.isEmpty { lines.append("Selected by the user: " + selected.map(Self.ref).joined(separator: ", ")) }
        lines.append("")
        outline(topic, depth: depth, includeNotes: try args.bool("include_notes") ?? true, into: &lines)
        let rels = relationshipLines(map)
        if !rels.isEmpty, start == map.root.id {
            lines.append("")
            lines.append("Relationships:")
            lines.append(contentsOf: rels)
        }
        return MCPToolResult(text: lines.joined(separator: "\n"))
    }

    private static func prune(_ topic: inout Topic, depth: Int) {
        if depth <= 0 { topic.children = []; return }
        for i in topic.children.indices { prune(&topic.children[i], depth: depth - 1) }
    }

    func getTopic(_ args: MCPArgs) throws -> MCPToolResult {
        let doc = try document(args)
        let map = doc.editor.map
        let id = try topicID(try args.requiredString("topic_id"), in: map)
        guard let t = map.topic(id) else { throw MCPToolError("Topic not found.") }
        let parent = map.parentID(of: id).flatMap { map.topic($0) }

        var lines = [Self.ref(t), "Path: " + pathText(id, in: map)]
        if let parent, let index = parent.children.firstIndex(where: { $0.id == id }) {
            lines.append("Parent: \(Self.ref(parent)) · position \(index) of \(parent.children.count) (0-based)")
        } else {
            lines.append("This is the central topic.")
        }
        if !t.children.isEmpty {
            lines.append("Children (\(t.children.count))" + (t.collapsed ? ", collapsed" : "") + ": "
                         + t.children.map(Self.ref).joined(separator: "; "))
        }
        if !t.markers.isEmpty { lines.append("Markers: " + t.markers.map(\.rawValue).joined(separator: ", ")) }
        if !t.labels.isEmpty { lines.append("Labels: " + t.labels.joined(separator: ", ")) }
        if let link = t.link, t.hasLink { lines.append("Link: " + link) }
        if !t.attachments.isEmpty {
            lines.append("Attachments: " + t.attachments.map { "\($0.name) (\(ByteCountFormatter.string(fromByteCount: $0.size, countStyle: .file)))" }.joined(separator: ", "))
        }
        if let image = t.image { lines.append("Image: \(image.name), shown at \(Int(image.width))×\(Int(image.height)) pt") }
        let style = Self.styleObject(t.style)
        if !style.isEmpty { lines.append("Style overrides: " + MCPJSON.string(style)) }
        for r in map.relationships where r.from == id || r.to == id {
            let other = map.topic(r.from == id ? r.to : r.from).map(Self.ref) ?? "?"
            lines.append("Relationship [\(Self.shortID(r.id))] " + (r.from == id ? "→ " : "← ") + other
                         + (r.title.isEmpty ? "" : " · \"\(Self.oneLine(r.title))\""))
        }
        if t.hasNote { lines.append("Note:\n" + t.note) }

        let structured: MCPObject = [
            "id": Self.shortID(t.id),
            "title": t.title,
            "path": pathText(id, in: map),
            "parent_id": parent.map { Self.shortID($0.id) } ?? NSNull(),
            "children": t.children.map { ["id": Self.shortID($0.id), "title": $0.title] },
            "collapsed": t.collapsed,
            "note": t.note,
            "link": t.link ?? NSNull(),
            "labels": t.labels,
            "markers": t.markers.map(\.rawValue),
            "style": style,
        ]
        return MCPToolResult(text: lines.joined(separator: "\n"), structured: structured)
    }

    func search(_ args: MCPArgs) throws -> MCPToolResult {
        let doc = try document(args)
        let map = doc.editor.map
        let query = try args.requiredString("query").trimmingCharacters(in: .whitespacesAndNewlines)
        let inNotes = try args.bool("in_notes") ?? true
        let limit = min(max(try args.int("limit") ?? 50, 1), 500)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

        // 每个结果一段文字：主题行，备注里命中时再加一行上下文
        var matches: [String] = []
        map.root.forEach { t in
            let inTitle = t.title.range(of: query, options: options) != nil
                || t.labels.contains { $0.range(of: query, options: options) != nil }
            let noteRange = inNotes ? t.note.range(of: query, options: options) : nil
            guard inTitle || noteRange != nil else { return }
            var entry = "\(Self.ref(t)) — \(pathText(t.id, in: map))"
            if !inTitle, let r = noteRange {
                let lower = t.note.index(r.lowerBound, offsetBy: -40, limitedBy: t.note.startIndex) ?? t.note.startIndex
                let upper = t.note.index(r.upperBound, offsetBy: 40, limitedBy: t.note.endIndex) ?? t.note.endIndex
                entry += "\n    note: …" + Self.oneLine(String(t.note[lower..<upper])) + "…"
            }
            matches.append(entry)
        }
        if matches.isEmpty { return MCPToolResult(text: "No topics match \"\(query)\".") }
        let header = "\(matches.count) topic(s) match \"\(query)\"" + (matches.count > limit ? " (showing \(limit))" : "") + ":\n"
        return MCPToolResult(text: header + matches.prefix(limit).joined(separator: "\n"))
    }

    func selection(_ args: MCPArgs) throws -> MCPToolResult {
        let doc = try document(args)
        let editor = doc.editor
        let map = editor.map
        var lines = [mapHeader(doc)]
        let selected = editor.selectedTopics
        if selected.isEmpty, editor.selectedRelationshipModel == nil {
            lines.append("Nothing is selected.")
        }
        for t in selected { lines.append("Selected topic: \(Self.summaryLine(t)) — \(pathText(t.id, in: map))") }
        if let r = editor.selectedRelationshipModel,
           let line = relationshipLines(MindMap(root: map.root, relationships: [r])).first {
            lines.append("Selected relationship: " + line)
        }
        return MCPToolResult(text: lines.joined(separator: "\n"),
                             structured: ["selected_topic_ids": selected.map { Self.shortID($0.id) }])
    }

    /// 把整张导图（折叠的分支不画）渲染成 PNG。
    func render(_ args: MCPArgs) throws -> MCPToolResult {
        let doc = try document(args)
        let layout = doc.editor.layout
        let requested = CGFloat(min(max(try args.double("scale") ?? 1, 0.25), 2))
        let longest = max(layout.bounds.width, layout.bounds.height) + 80
        // 限制最长边，避免一张图几十 MB
        let scale = min(requested, 2400 / max(longest, 1))
        guard let png = ImageExporter.pngData(layout: layout, images: { doc.attachments.image(for: $0) }, scale: scale),
              let rep = NSBitmapImageRep(data: png) else {
            throw MCPToolError("Could not render the map.")
        }
        var text = "\(mapHeader(doc))\nRendered at \(rep.pixelsWide)×\(rep.pixelsHigh) px."
        if doc.editor.map.root.subtreeCount > doc.editor.layout.order.count {
            text += " Collapsed branches are not shown."
        }
        return MCPToolResult(text: text, image: png)
    }
}
