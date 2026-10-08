import Foundation

/// 标记 id，形如 `priority-1`、`task-50`、`flag-red`、`symbol-idea`，和 XMind 的 markerId 思路一致。
struct MarkerID: RawRepresentable, Hashable, Codable, Comparable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ raw: String) { self.rawValue = raw }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    var group: MarkerGroup? {
        MarkerGroup.allCases.first { rawValue.hasPrefix($0.rawValue + "-") }
    }

    /// 前缀之后的部分，例如 `priority-3` → `3`。
    var suffix: String {
        guard let group else { return rawValue }
        return String(rawValue.dropFirst(group.rawValue.count + 1))
    }

    static func < (lhs: MarkerID, rhs: MarkerID) -> Bool {
        let lo = lhs.group?.order ?? 99, ro = rhs.group?.order ?? 99
        return lo == ro ? lhs.rawValue < rhs.rawValue : lo < ro
    }
}

enum MarkerGroup: String, CaseIterable, Identifiable {
    case priority, task, flag, star, symbol

    var id: String { rawValue }
    var order: Int { MarkerGroup.allCases.firstIndex(of: self) ?? 0 }

    /// 同组内是否互斥（例如一个主题只能有一个优先级）。
    var isExclusive: Bool { self != .symbol }

    var title: String {
        switch self {
        case .priority: return L("Priority")
        case .task: return L("Progress")
        case .flag: return L("Flag")
        case .star: return L("Star")
        case .symbol: return L("Symbol")
        }
    }
}

enum MarkerColorName: String, CaseIterable {
    case red, orange, yellow, green, blue, purple, gray

    var hex: String {
        switch self {
        case .red: return "#E5484D"
        case .orange: return "#F76B15"
        case .yellow: return "#E9A800"
        case .green: return "#30A46C"
        case .blue: return "#0090FF"
        case .purple: return "#8E4EC6"
        case .gray: return "#8B8D98"
        }
    }

    var title: String {
        switch self {
        case .red: return L("Red")
        case .orange: return L("Orange")
        case .yellow: return L("Yellow")
        case .green: return L("Green")
        case .blue: return L("Blue")
        case .purple: return L("Purple")
        case .gray: return L("Gray")
        }
    }
}

/// 图形符号类标记：SF Symbol 名称 + 固定颜色。
struct SymbolMarker {
    let key: String
    let symbol: String
    let colorHex: String
    let titleKey: String
}

enum MarkerCatalog {
    static let priorities: [MarkerID] = (1...6).map { MarkerID("priority-\($0)") }
    static let progress: [MarkerID] = [0, 25, 50, 75, 100].map { MarkerID("task-\($0)") }
    static let flags: [MarkerID] = MarkerColorName.allCases.map { MarkerID("flag-\($0.rawValue)") }
    static let stars: [MarkerID] = MarkerColorName.allCases.map { MarkerID("star-\($0.rawValue)") }

    static let symbols: [SymbolMarker] = [
        SymbolMarker(key: "question", symbol: "questionmark.circle.fill", colorHex: "#0090FF", titleKey: "Question"),
        SymbolMarker(key: "important", symbol: "exclamationmark.circle.fill", colorHex: "#E5484D", titleKey: "Important"),
        SymbolMarker(key: "idea", symbol: "lightbulb.fill", colorHex: "#E9A800", titleKey: "Idea"),
        SymbolMarker(key: "check", symbol: "checkmark.circle.fill", colorHex: "#30A46C", titleKey: "Done"),
        SymbolMarker(key: "cross", symbol: "xmark.circle.fill", colorHex: "#E5484D", titleKey: "Rejected"),
        SymbolMarker(key: "heart", symbol: "heart.fill", colorHex: "#E93D82", titleKey: "Love"),
        SymbolMarker(key: "like", symbol: "hand.thumbsup.fill", colorHex: "#0090FF", titleKey: "Like"),
        SymbolMarker(key: "dislike", symbol: "hand.thumbsdown.fill", colorHex: "#8B8D98", titleKey: "Dislike"),
        SymbolMarker(key: "pin", symbol: "pin.fill", colorHex: "#E5484D", titleKey: "Pin"),
        SymbolMarker(key: "time", symbol: "hourglass", colorHex: "#F76B15", titleKey: "Time"),
        SymbolMarker(key: "person", symbol: "person.crop.circle.fill", colorHex: "#12A594", titleKey: "Person"),
        SymbolMarker(key: "money", symbol: "dollarsign.circle.fill", colorHex: "#30A46C", titleKey: "Cost"),
    ]

    static let symbolIDs: [MarkerID] = symbols.map { MarkerID("symbol-\($0.key)") }

    static func markers(in group: MarkerGroup) -> [MarkerID] {
        switch group {
        case .priority: return priorities
        case .task: return progress
        case .flag: return flags
        case .star: return stars
        case .symbol: return symbolIDs
        }
    }

    static func symbol(for id: MarkerID) -> SymbolMarker? {
        guard id.group == .symbol else { return nil }
        return symbols.first { $0.key == id.suffix }
    }

    /// 标记的可读名称（用于提示文字、菜单）。
    static func title(for id: MarkerID) -> String {
        switch id.group {
        case .priority: return String(format: L("Priority %@"), id.suffix)
        case .task: return String(format: L("Progress %@%%"), id.suffix)
        case .flag: return "\(MarkerColorName(rawValue: id.suffix)?.title ?? id.suffix) · \(L("Flag"))"
        case .star: return "\(MarkerColorName(rawValue: id.suffix)?.title ?? id.suffix) · \(L("Star"))"
        case .symbol: return symbol(for: id).map { L($0.titleKey) } ?? id.rawValue
        case nil: return id.rawValue
        }
    }

    /// 切换一个标记：同组互斥时替换掉同组已有的标记；已存在则移除。
    static func toggle(_ id: MarkerID, in markers: [MarkerID]) -> [MarkerID] {
        if markers.contains(id) { return markers.filter { $0 != id } }
        var result = markers
        if let group = id.group, group.isExclusive {
            result.removeAll { $0.group == group }
        }
        result.append(id)
        return result.sorted()
    }
}
