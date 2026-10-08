import Foundation

/// 导图结构（布局方式）。
enum MapStructure: String, Codable, CaseIterable, Identifiable {
    /// 思维导图：分支左右平衡分布（顺时针）。
    case mindMap = "mindmap"
    /// 逻辑图：全部向右展开。
    case logicRight = "logic-right"
    /// 逻辑图：全部向左展开。
    case logicLeft = "logic-left"
    /// 组织结构图：向下展开。
    case orgChart = "org-down"
    /// 树状图：缩进列表式，向右下展开。
    case tree = "tree"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mindMap: return L("Mind Map")
        case .logicRight: return L("Logic Chart (Right)")
        case .logicLeft: return L("Logic Chart (Left)")
        case .orgChart: return L("Org Chart")
        case .tree: return L("Tree Chart")
        }
    }

    var symbolName: String {
        switch self {
        case .mindMap: return "point.3.connected.trianglepath.dotted"
        case .logicRight: return "arrow.right.to.line"
        case .logicLeft: return "arrow.left.to.line"
        case .orgChart: return "rectangle.3.group"
        case .tree: return "list.bullet.indent"
        }
    }
}

/// 主题之间的间距。
enum MapSpacing: String, Codable, CaseIterable, Identifiable {
    case compact, standard, loose

    var id: String { rawValue }

    var factor: Double {
        switch self {
        case .compact: return 0.7
        case .standard: return 1.0
        case .loose: return 1.4
        }
    }

    var title: String {
        switch self {
        case .compact: return L("Compact")
        case .standard: return L("Standard")
        case .loose: return L("Loose")
        }
    }
}

struct MindMap: Equatable {
    var root: Topic
    var structure: MapStructure
    var theme: Theme
    var spacing: MapSpacing
    /// 覆盖主题里的连线样式；nil 表示跟随主题。
    var lineStyle: LineStyle?
    /// 主题文字的最大宽度（超出自动换行）。
    var topicMaxWidth: Double
    /// 主题之间的联系线。
    var relationships: [Relationship]

    init(root: Topic, structure: MapStructure = .mindMap, theme: Theme = .classic,
         spacing: MapSpacing = .standard, lineStyle: LineStyle? = nil, topicMaxWidth: Double = 260,
         relationships: [Relationship] = []) {
        self.root = root
        self.structure = structure
        self.theme = theme
        self.spacing = spacing
        self.lineStyle = lineStyle
        self.topicMaxWidth = topicMaxWidth
        self.relationships = relationships
    }

    var effectiveLineStyle: LineStyle { lineStyle ?? theme.lineStyle }

    static func blank(title: String = L("Central Topic"), structure: MapStructure = .mindMap, theme: Theme = .classic) -> MindMap {
        let children = (1...4).map { Topic(title: LF("Main Topic %d", $0)) }
        return MindMap(root: Topic(title: title, children: children), structure: structure, theme: theme)
    }
}

extension MindMap: Codable {
    private enum CodingKeys: String, CodingKey {
        case root, structure, theme, spacing, lineStyle, topicMaxWidth, relationships
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        root = try c.decode(Topic.self, forKey: .root)
        structure = (try? c.decodeIfPresent(MapStructure.self, forKey: .structure)) ?? .mindMap
        theme = (try? c.decodeIfPresent(Theme.self, forKey: .theme)) ?? .classic
        spacing = (try? c.decodeIfPresent(MapSpacing.self, forKey: .spacing)) ?? .standard
        lineStyle = try? c.decodeIfPresent(LineStyle.self, forKey: .lineStyle)
        topicMaxWidth = try c.decodeIfPresent(Double.self, forKey: .topicMaxWidth) ?? 260
        // 逐条容错：某一条联系线数据损坏时只丢弃那一条，不影响其他联系线
        relationships = (try c.decodeIfPresent([Lossy<Relationship>].self, forKey: .relationships) ?? []).compactMap(\.value)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(structure, forKey: .structure)
        try c.encode(spacing, forKey: .spacing)
        try c.encodeIfPresent(lineStyle, forKey: .lineStyle)
        try c.encode(topicMaxWidth, forKey: .topicMaxWidth)
        try c.encode(theme, forKey: .theme)
        try c.encode(root, forKey: .root)
        if !relationships.isEmpty { try c.encode(relationships, forKey: .relationships) }
    }
}

/// 解码失败时得到 nil 而不是让整个数组失败。
struct Lossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

// MARK: - 树操作（按 id 定位，全部基于索引路径）

/// 主题在树中的位置信息。
struct TopicLocation: Equatable {
    var path: [Int]
    var parentID: UUID?
    var depth: Int { path.count }
    var index: Int? { path.last }
}

extension Topic {
    subscript(path path: ArraySlice<Int>) -> Topic {
        get {
            guard let first = path.first else { return self }
            return children[first][path: path.dropFirst()]
        }
        set {
            guard let first = path.first else { self = newValue; return }
            children[first][path: path.dropFirst()] = newValue
        }
    }
}

extension MindMap {
    /// 建立 id → 位置 的索引。O(n)。
    func buildIndex() -> [UUID: TopicLocation] {
        var index: [UUID: TopicLocation] = [:]
        func walk(_ t: Topic, path: [Int], parent: UUID?) {
            index[t.id] = TopicLocation(path: path, parentID: parent)
            for (i, child) in t.children.enumerated() {
                walk(child, path: path + [i], parent: t.id)
            }
        }
        walk(root, path: [], parent: nil)
        return index
    }

    func path(of id: UUID) -> [Int]? {
        func search(_ t: Topic, _ path: [Int]) -> [Int]? {
            if t.id == id { return path }
            for (i, child) in t.children.enumerated() {
                if let found = search(child, path + [i]) { return found }
            }
            return nil
        }
        return search(root, [])
    }

    func topic(_ id: UUID) -> Topic? {
        guard let p = path(of: id) else { return nil }
        return root[path: p[...]]
    }

    func topic(at path: [Int]) -> Topic { root[path: path[...]] }

    func parentID(of id: UUID) -> UUID? {
        guard let p = path(of: id), !p.isEmpty else { return nil }
        return root[path: p.dropLast()[...]].id
    }

    func contains(_ id: UUID) -> Bool { path(of: id) != nil }

    /// `ancestor` 是否是 `id` 的祖先（或就是自身）。
    func isAncestor(_ ancestor: UUID, of id: UUID) -> Bool {
        guard let a = path(of: ancestor), let b = path(of: id), a.count <= b.count else { return false }
        return Array(b.prefix(a.count)) == a
    }

    /// 修改指定主题。找不到返回 false。
    @discardableResult
    mutating func update(_ id: UUID, _ body: (inout Topic) -> Void) -> Bool {
        guard let p = path(of: id) else { return false }
        body(&root[path: p[...]])
        return true
    }

    /// 移除主题（根主题不可移除），返回被移除的主题和原位置。
    @discardableResult
    mutating func remove(_ id: UUID) -> (topic: Topic, parentID: UUID, index: Int)? {
        guard let p = path(of: id), let last = p.last else { return nil }
        let parentPath = p.dropLast()
        let parentID = root[path: parentPath[...]].id
        let removed = root[path: parentPath[...]].children.remove(at: last)
        return (removed, parentID, last)
    }

    /// 插入到指定父主题下；index 越界时追加到末尾。
    @discardableResult
    mutating func insert(_ topic: Topic, into parentID: UUID, at index: Int?) -> Bool {
        update(parentID) { parent in
            let i = min(max(index ?? parent.children.count, 0), parent.children.count)
            parent.children.insert(topic, at: i)
        }
    }

    /// 所有主题（深度优先，含根）。
    var allTopics: [Topic] {
        var result: [Topic] = []
        root.forEach { result.append($0) }
        return result
    }

    var topicCount: Int { root.subtreeCount }

    /// 一组 id 里去掉“祖先已在集合中”的那些，避免对子树重复操作。
    func topmost(_ ids: [UUID]) -> [UUID] {
        let set = Set(ids)
        return ids.filter { id in
            var current = parentID(of: id)
            while let p = current {
                if set.contains(p) { return false }
                current = parentID(of: p)
            }
            return true
        }
    }

    /// 展开到能看见指定主题（把所有祖先设为展开）。返回是否有改动。
    @discardableResult
    mutating func reveal(_ id: UUID) -> Bool {
        guard let p = path(of: id), !p.isEmpty else { return false }
        var changed = false
        for depth in 0..<p.count {
            let ancestorPath = p.prefix(depth)
            if root[path: ancestorPath[...]].collapsed {
                root[path: ancestorPath[...]].collapsed = false
                changed = true
            }
        }
        return changed
    }

    /// 所有被引用的资源 id（附件 + 图片）。
    var referencedResourceIDs: Set<UUID> { root.resourceIDs() }

    /// 所有主题换成新 id（联系线端点同步更新），用于模板实例化。
    func withFreshTopicIDs() -> MindMap {
        var copy = self
        var mapping: [UUID: UUID] = [:]
        copy.root.mutateAll { t in
            let new = UUID()
            mapping[t.id] = new
            t.id = new
        }
        copy.relationships = relationships.compactMap { r in
            guard let from = mapping[r.from], let to = mapping[r.to] else { return nil }
            var n = r
            n.id = UUID()
            n.from = from
            n.to = to
            return n
        }
        return copy
    }
}
