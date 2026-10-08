import Foundation

/// 联系线：连接任意两个主题的曲线箭头（XMind 的 Relationship）。
struct Relationship: Identifiable, Equatable {
    var id: UUID
    var from: UUID
    var to: UUID
    var title: String
    /// 两个控制点相对于起点 / 终点的偏移；nil 表示自动弧度。
    var control1: Offset?
    var control2: Offset?
    var color: Paint?
    var dashed: Bool
    var arrowStart: Bool
    var arrowEnd: Bool

    struct Offset: Codable, Equatable {
        var dx: Double
        var dy: Double
    }

    init(id: UUID = UUID(), from: UUID, to: UUID, title: String = "") {
        self.id = id
        self.from = from
        self.to = to
        self.title = title
        self.control1 = nil
        self.control2 = nil
        self.color = nil
        self.dashed = true
        self.arrowStart = false
        self.arrowEnd = true
    }
}

extension Relationship: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, from, to, title, control1, control2, color, dashed, arrowStart, arrowEnd
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        from = try c.decode(UUID.self, forKey: .from)
        to = try c.decode(UUID.self, forKey: .to)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        control1 = try c.decodeIfPresent(Offset.self, forKey: .control1)
        control2 = try c.decodeIfPresent(Offset.self, forKey: .control2)
        color = try c.decodeIfPresent(Paint.self, forKey: .color)
        dashed = try c.decodeIfPresent(Bool.self, forKey: .dashed) ?? true
        arrowStart = try c.decodeIfPresent(Bool.self, forKey: .arrowStart) ?? false
        arrowEnd = try c.decodeIfPresent(Bool.self, forKey: .arrowEnd) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(from, forKey: .from)
        try c.encode(to, forKey: .to)
        if !title.isEmpty { try c.encode(title, forKey: .title) }
        try c.encodeIfPresent(control1, forKey: .control1)
        try c.encodeIfPresent(control2, forKey: .control2)
        try c.encodeIfPresent(color, forKey: .color)
        if !dashed { try c.encode(false, forKey: .dashed) }
        if arrowStart { try c.encode(true, forKey: .arrowStart) }
        if !arrowEnd { try c.encode(false, forKey: .arrowEnd) }
    }
}
