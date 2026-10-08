import AppKit

/// 主题 + 层级 + 单独覆盖 合并后的最终样式，布局和绘制都只看它。
struct ResolvedStyle {
    var shape: TopicShape
    var fill: NSColor?
    var text: NSColor
    var border: NSColor?
    var borderWidth: CGFloat
    var font: NSFont
    var padH: CGFloat
    var padV: CGFloat
    var radius: CGFloat
    var branchColor: NSColor
    var alignment: NSTextAlignment

    /// 下划线形状的线宽。
    var underlineWidth: CGFloat { max(borderWidth, 1) }

    static func resolve(topic: Topic, level: Int, branchColor: NSColor, theme: Theme) -> ResolvedStyle {
        let base = theme.levelStyle(level)
        let override = topic.style
        let background = theme.backgroundColor
        let shape = override.shape ?? base.shape

        var fillPaint = override.fill ?? base.fill
        // 从下划线/无边框切换到带框形状时，如果主题这一层没有填充色，补一个浅色底，避免只剩一个空框。
        if shape.isBoxed, override.fill == nil, !base.shape.isBoxed, fillPaint.isNone {
            fillPaint = .branchSoft
        }
        let fill = fillPaint.resolve(branch: branchColor, background: background)

        var borderPaint = override.border ?? base.border
        var borderWidth = CGFloat(base.borderWidth)
        if shape == .underline {
            if borderPaint.isNone { borderPaint = .branch }
            if borderWidth <= 0 { borderWidth = 1.5 }
        } else if override.border != nil, borderWidth <= 0 {
            borderWidth = 1.5
        }
        if shape.isBoxed, !base.shape.isBoxed, override.border == nil {
            // 由下划线改成带框时，下划线颜色不应该变成边框。
            borderPaint = .none
            borderWidth = 0
        }
        let border = borderPaint.resolve(branch: branchColor, background: background)

        let under = fill ?? background
        let text = (override.textColor ?? base.text).resolve(branch: branchColor, background: background, under: under)
            ?? under.contrastingTextColor

        let size = CGFloat(override.fontSize ?? base.fontSize)
        var weight = base.weight.nsWeight
        if let bold = override.bold { weight = bold ? .bold : .regular }
        let font = FontCache.font(family: theme.fontFamily, size: size, weight: weight, italic: override.italic ?? false)

        var padH = CGFloat(base.padH), padV = CGFloat(base.padV)
        if shape.isBoxed, !base.shape.isBoxed {
            padH = max(padH, 10); padV = max(padV, 5)
        } else if !shape.isBoxed, base.shape.isBoxed {
            padH = 4; padV = 4
        }

        return ResolvedStyle(
            shape: shape, fill: fill, text: text, border: border, borderWidth: border == nil ? 0 : borderWidth,
            font: font, padH: padH, padV: padV, radius: CGFloat(base.radius),
            branchColor: branchColor,
            alignment: shape.isBoxed ? .center : .left)
    }
}

enum FontCache {
    private static var cache: [String: NSFont] = [:]

    static func font(family: String?, size: CGFloat, weight: NSFont.Weight, italic: Bool) -> NSFont {
        let key = "\(family ?? "-")|\(size)|\(weight.rawValue)|\(italic)"
        if let cached = cache[key] { return cached }
        var font: NSFont = .systemFont(ofSize: size, weight: weight)
        if let family, !family.isEmpty {
            let bold = weight.rawValue >= NSFont.Weight.semibold.rawValue
            let fmWeight = bold ? 9 : (weight.rawValue >= NSFont.Weight.medium.rawValue ? 6 : 5)
            if let custom = NSFontManager.shared.font(withFamily: family, traits: bold ? .boldFontMask : [],
                                                      weight: fmWeight, size: size) {
                font = custom
            }
        }
        if italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        cache[key] = font
        return font
    }
}
