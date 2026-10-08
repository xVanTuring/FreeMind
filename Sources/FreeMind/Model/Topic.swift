import Foundation

/// 主题节点。整棵树是嵌套的值类型，撤销/重做直接保存整张图的快照。
struct Topic: Identifiable, Equatable {
    var id: UUID
    var title: String
    var children: [Topic]
    /// 折叠状态，随文档一起保存。
    var collapsed: Bool
    var note: String
    var link: String?
    var attachments: [Attachment]
    var image: TopicImage?
    var markers: [MarkerID]
    var labels: [String]
    var style: TopicStyle

    init(id: UUID = UUID(),
         title: String,
         children: [Topic] = [],
         collapsed: Bool = false,
         note: String = "",
         link: String? = nil,
         attachments: [Attachment] = [],
         image: TopicImage? = nil,
         markers: [MarkerID] = [],
         labels: [String] = [],
         style: TopicStyle = TopicStyle()) {
        self.id = id
        self.title = title
        self.children = children
        self.collapsed = collapsed
        self.note = note
        self.link = link
        self.attachments = attachments
        self.image = image
        self.markers = markers
        self.labels = labels
        self.style = style
    }

    var hasNote: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasLink: Bool { !(link ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    /// 子树中的主题总数（含自身）。
    var subtreeCount: Int { 1 + children.reduce(0) { $0 + $1.subtreeCount } }

    /// 深度优先遍历（含自身）。
    func forEach(_ body: (Topic) -> Void) {
        body(self)
        for child in children { child.forEach(body) }
    }

    /// 深度优先修改（含自身）。
    mutating func mutateAll(_ body: (inout Topic) -> Void) {
        body(&self)
        for i in children.indices { children[i].mutateAll(body) }
    }

    /// 生成一份 id 全新的副本（复制/粘贴、模板实例化时用）。
    func withFreshIDs() -> Topic {
        var copy = self
        copy.mutateAll { $0.id = UUID() }
        return copy
    }

    /// 子树里引用到的所有附件 / 图片资源 id。
    func resourceIDs() -> Set<UUID> {
        var ids = Set<UUID>()
        forEach { topic in
            topic.attachments.forEach { ids.insert($0.id) }
            if let image = topic.image { ids.insert(image.id) }
        }
        return ids
    }
}

// MARK: - Codable（缺省字段省略，读取时容忍缺失，便于格式演进）

extension Topic: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, children, collapsed, note, link, attachments, image, markers, labels, style
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        children = try c.decodeIfPresent([Topic].self, forKey: .children) ?? []
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link)
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        image = try c.decodeIfPresent(TopicImage.self, forKey: .image)
        markers = try c.decodeIfPresent([MarkerID].self, forKey: .markers) ?? []
        labels = try c.decodeIfPresent([String].self, forKey: .labels) ?? []
        style = try c.decodeIfPresent(TopicStyle.self, forKey: .style) ?? TopicStyle()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        if collapsed { try c.encode(true, forKey: .collapsed) }
        if !note.isEmpty { try c.encode(note, forKey: .note) }
        if let link, !link.isEmpty { try c.encode(link, forKey: .link) }
        if !attachments.isEmpty { try c.encode(attachments, forKey: .attachments) }
        try c.encodeIfPresent(image, forKey: .image)
        if !markers.isEmpty { try c.encode(markers, forKey: .markers) }
        if !labels.isEmpty { try c.encode(labels, forKey: .labels) }
        if !style.isEmpty { try c.encode(style, forKey: .style) }
        if !children.isEmpty { try c.encode(children, forKey: .children) }
    }
}

/// 主题上的附件。文件本体放在包内 `attachments/<id>/<name>`。
struct Attachment: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var size: Int64

    init(id: UUID = UUID(), name: String, size: Int64) {
        self.id = id
        self.name = name
        self.size = size
    }
}

/// 显示在主题内部的图片。文件同样存放在 `attachments/<id>/<name>`。
struct TopicImage: Codable, Equatable {
    var id: UUID
    var name: String
    /// 显示尺寸（pt）。
    var width: Double
    var height: Double
}

/// 单个主题的样式覆盖。nil 表示沿用主题（Theme）里的层级样式。
struct TopicStyle: Codable, Equatable {
    var shape: TopicShape?
    var fill: Paint?
    var textColor: Paint?
    var border: Paint?
    var fontSize: Double?
    var bold: Bool?
    var italic: Bool?
    /// 分支颜色：作用于本主题出发的连线和整棵子树。
    var branchColor: Paint?
    /// 外框：在整棵子树外面画一圈虚线框。
    var boundary: Bool?

    var isEmpty: Bool { self == TopicStyle() }
}
