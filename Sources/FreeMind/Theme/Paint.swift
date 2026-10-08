import AppKit

/// 主题里的颜色描述。可以是固定色 `#RRGGBB(AA)`，也可以是相对分支颜色的描述：
/// - `branch`：分支色
/// - `branch-soft`：分支色与背景混合后的浅色（适合做填充）
/// - `branch-mid`：分支色与背景的中间色
/// - `branch-dark`：加深的分支色
/// - `auto`：根据底色自动选黑/白（只对文字有意义）
/// - `none`：不画
struct Paint: RawRepresentable, Codable, Hashable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ raw: String) { self.rawValue = raw }
    init(stringLiteral value: String) { self.rawValue = value }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    static let none: Paint = "none"
    static let branch: Paint = "branch"
    static let branchSoft: Paint = "branch-soft"
    static let branchMid: Paint = "branch-mid"
    static let branchDark: Paint = "branch-dark"
    static let auto: Paint = "auto"

    var isNone: Bool { rawValue == "none" || rawValue.isEmpty }
    var isFixed: Bool { rawValue.hasPrefix("#") }

    init(color: NSColor) { self.rawValue = color.hexString }

    /// - Parameters:
    ///   - branch: 当前分支色
    ///   - background: 画布背景色
    ///   - under: 文字下方的底色（填充色，没有填充就是背景）
    func resolve(branch: NSColor, background: NSColor, under: NSColor? = nil) -> NSColor? {
        switch rawValue {
        case "", "none": return nil
        case "branch": return branch
        case "branch-soft": return branch.mixed(with: background, fraction: 0.82)
        case "branch-mid": return branch.mixed(with: background, fraction: 0.5)
        case "branch-dark": return branch.mixed(with: .black, fraction: 0.35)
        case "auto": return (under ?? background).contrastingTextColor
        default: return NSColor(hex: rawValue)
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if s.count == 6 {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        } else {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        let a = Int((c.alphaComponent * 255).rounded())
        if a < 255 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// 线性混合：fraction=0 返回自身，1 返回 other。
    func mixed(with other: NSColor, fraction: CGFloat) -> NSColor {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return self }
        let t = max(0, min(1, fraction))
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
                       alpha: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * t)
    }

    /// 相对亮度（WCAG 定义）。
    var luminance: CGFloat {
        guard let c = usingColorSpace(.sRGB) else { return 1 }
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }

    var isDarkColor: Bool { luminance < 0.4 }

    var contrastingTextColor: NSColor {
        luminance < 0.42 ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
                         : NSColor(srgbRed: 0.12, green: 0.14, blue: 0.16, alpha: 1)
    }
}
