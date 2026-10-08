import AppKit

enum TopicShape: String, Codable, CaseIterable, Identifiable {
    case roundedRect, rect, capsule, ellipse, diamond, underline, plain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .roundedRect: return L("Rounded Rectangle")
        case .rect: return L("Rectangle")
        case .capsule: return L("Capsule")
        case .ellipse: return L("Ellipse")
        case .diamond: return L("Diamond")
        case .underline: return L("Underline")
        case .plain: return L("No Border")
        }
    }

    var symbolName: String {
        switch self {
        case .roundedRect: return "app"
        case .rect: return "square"
        case .capsule: return "capsule"
        case .ellipse: return "oval"
        case .diamond: return "diamond"
        case .underline: return "underline"
        case .plain: return "textformat"
        }
    }

    /// 是否是“带框”的形状（影响连线锚点、文字对齐）。
    var isBoxed: Bool { self != .underline && self != .plain }
}

enum LineStyle: String, Codable, CaseIterable, Identifiable {
    case curve, straight, elbow, roundedElbow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .curve: return L("Curve")
        case .straight: return L("Straight")
        case .elbow: return L("Elbow")
        case .roundedElbow: return L("Rounded Elbow")
        }
    }
}

enum FontWeightName: String, Codable, CaseIterable {
    case regular, medium, semibold, bold

    var nsWeight: NSFont.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

/// 某一层级主题（中心 / 分支 / 子主题）的默认样式。
struct LevelStyle: Codable, Equatable {
    var shape: TopicShape
    var fill: Paint
    var text: Paint
    var border: Paint
    var borderWidth: Double
    var fontSize: Double
    var weight: FontWeightName
    var padH: Double
    var padV: Double
    var radius: Double

    init(shape: TopicShape, fill: Paint, text: Paint, border: Paint = .none, borderWidth: Double = 0,
         fontSize: Double, weight: FontWeightName = .regular, padH: Double, padV: Double, radius: Double = 6) {
        self.shape = shape
        self.fill = fill
        self.text = text
        self.border = border
        self.borderWidth = borderWidth
        self.fontSize = fontSize
        self.weight = weight
        self.padH = padH
        self.padV = padV
        self.radius = radius
    }

    private enum CodingKeys: String, CodingKey {
        case shape, fill, text, border, borderWidth, fontSize, weight, padH, padV, radius
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Theme.classic.sub
        shape = (try? c.decodeIfPresent(TopicShape.self, forKey: .shape)) ?? d.shape
        fill = try c.decodeIfPresent(Paint.self, forKey: .fill) ?? d.fill
        text = try c.decodeIfPresent(Paint.self, forKey: .text) ?? d.text
        border = try c.decodeIfPresent(Paint.self, forKey: .border) ?? d.border
        borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? d.borderWidth
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        weight = (try? c.decodeIfPresent(FontWeightName.self, forKey: .weight)) ?? d.weight
        padH = try c.decodeIfPresent(Double.self, forKey: .padH) ?? d.padH
        padV = try c.decodeIfPresent(Double.self, forKey: .padV) ?? d.padV
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? d.radius
    }
}

/// 导图主题：背景、连线、分支配色和各层级样式。文档里会内嵌一份完整副本，
/// 所以导图拿到别的机器上、或者内置主题以后调整了，显示效果都不会变。
struct Theme: Codable, Equatable, Identifiable {
    var id: String
    /// 内置主题存英文原文（显示时再本地化），自定义主题存用户起的名字。
    var name: String
    var background: Paint
    var lineStyle: LineStyle
    var linePaint: Paint
    var lineWidth: Double
    var mainLineWidth: Double
    var branchColors: [Paint]
    var central: LevelStyle
    var main: LevelStyle
    var sub: LevelStyle
    var fontFamily: String?

    var displayName: String { L(name) }

    var backgroundColor: NSColor { background.resolve(branch: .gray, background: .white) ?? .white }

    var isDark: Bool { backgroundColor.isDarkColor }

    func branchColor(at index: Int) -> NSColor {
        guard !branchColors.isEmpty else { return .systemBlue }
        let paint = branchColors[((index % branchColors.count) + branchColors.count) % branchColors.count]
        return paint.resolve(branch: .systemBlue, background: backgroundColor) ?? .systemBlue
    }

    /// 中心主题自身的“分支色”（中心主题没有所属分支，取第一个分支色的深色版）。
    var centralBranchColor: NSColor { branchColor(at: 0) }

    func levelStyle(_ level: Int) -> LevelStyle {
        switch level {
        case 0: return central
        case 1: return main
        default: return sub
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, background, lineStyle, linePaint, lineWidth, mainLineWidth, branchColors, central, main, sub, fontFamily
    }

    init(id: String, name: String, background: Paint, lineStyle: LineStyle, linePaint: Paint = .branch,
         lineWidth: Double, mainLineWidth: Double, branchColors: [Paint],
         central: LevelStyle, main: LevelStyle, sub: LevelStyle, fontFamily: String? = nil) {
        self.id = id
        self.name = name
        self.background = background
        self.lineStyle = lineStyle
        self.linePaint = linePaint
        self.lineWidth = lineWidth
        self.mainLineWidth = mainLineWidth
        self.branchColors = branchColors
        self.central = central
        self.main = main
        self.sub = sub
        self.fontFamily = fontFamily
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Theme.classic
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? d.id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
        background = try c.decodeIfPresent(Paint.self, forKey: .background) ?? d.background
        lineStyle = (try? c.decodeIfPresent(LineStyle.self, forKey: .lineStyle)) ?? d.lineStyle
        linePaint = try c.decodeIfPresent(Paint.self, forKey: .linePaint) ?? d.linePaint
        lineWidth = try c.decodeIfPresent(Double.self, forKey: .lineWidth) ?? d.lineWidth
        mainLineWidth = try c.decodeIfPresent(Double.self, forKey: .mainLineWidth) ?? d.mainLineWidth
        branchColors = try c.decodeIfPresent([Paint].self, forKey: .branchColors) ?? d.branchColors
        central = try c.decodeIfPresent(LevelStyle.self, forKey: .central) ?? d.central
        main = try c.decodeIfPresent(LevelStyle.self, forKey: .main) ?? d.main
        sub = try c.decodeIfPresent(LevelStyle.self, forKey: .sub) ?? d.sub
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily)
    }
}
