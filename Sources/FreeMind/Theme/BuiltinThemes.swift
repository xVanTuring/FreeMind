import Foundation

extension Theme {
    static let builtins: [Theme] = [
        .classic, .rainbow, .fresh, .ocean, .forest, .sunset, .candy, .business, .minimal, .paper, .midnight, .graphite,
    ]

    static func builtin(id: String) -> Theme? { builtins.first { $0.id == id } }

    /// 经典：白底，深蓝中心主题，分支柔和多彩，子主题下划线。
    static let classic = Theme(
        id: "classic", name: "Classic", background: "#FFFFFF", lineStyle: .curve,
        lineWidth: 1.5, mainLineWidth: 2.5,
        branchColors: ["#3B82F6", "#F59E0B", "#10B981", "#8B5CF6", "#EF4444", "#06B6D4", "#EC4899", "#84CC16"],
        central: LevelStyle(shape: .roundedRect, fill: "#1E3A5F", text: "#FFFFFF",
                            fontSize: 24, weight: .semibold, padH: 24, padV: 14, radius: 10),
        main: LevelStyle(shape: .roundedRect, fill: "branch-soft", text: "#1F2328", border: "branch", borderWidth: 1.5,
                         fontSize: 16, weight: .medium, padH: 14, padV: 8, radius: 8),
        sub: LevelStyle(shape: .underline, fill: .none, text: "#2B3036", border: "branch", borderWidth: 1.5,
                        fontSize: 14, padH: 4, padV: 4, radius: 0))

    /// 彩虹：分支主题实心彩色胶囊。
    static let rainbow = Theme(
        id: "rainbow", name: "Rainbow", background: "#FFFFFF", lineStyle: .curve,
        lineWidth: 2, mainLineWidth: 3,
        branchColors: ["#E5484D", "#F76B15", "#E9A800", "#30A46C", "#12A594", "#0090FF", "#6E56CF", "#D6409F"],
        central: LevelStyle(shape: .capsule, fill: "#1F2328", text: "#FFFFFF",
                            fontSize: 24, weight: .bold, padH: 28, padV: 14),
        main: LevelStyle(shape: .capsule, fill: "branch", text: "auto",
                         fontSize: 16, weight: .semibold, padH: 16, padV: 8),
        sub: LevelStyle(shape: .underline, fill: .none, text: "#1F2328", border: "branch", borderWidth: 2,
                        fontSize: 14, padH: 4, padV: 4, radius: 0))

    /// 清新：薄荷绿系，圆角折线。
    static let fresh = Theme(
        id: "fresh", name: "Fresh", background: "#F4FBF8", lineStyle: .roundedElbow,
        lineWidth: 1.5, mainLineWidth: 2,
        branchColors: ["#14B8A6", "#0EA5E9", "#22C55E", "#6366F1", "#F97316"],
        central: LevelStyle(shape: .capsule, fill: "#0F766E", text: "#FFFFFF",
                            fontSize: 22, weight: .semibold, padH: 26, padV: 13),
        main: LevelStyle(shape: .roundedRect, fill: "#FFFFFF", text: "#134E4A", border: "branch", borderWidth: 1.5,
                         fontSize: 16, weight: .medium, padH: 14, padV: 8, radius: 8),
        sub: LevelStyle(shape: .roundedRect, fill: "branch-soft", text: "#1F2937",
                        fontSize: 13.5, padH: 10, padV: 5, radius: 6))

    /// 海洋：蓝色系，实心分支。
    static let ocean = Theme(
        id: "ocean", name: "Ocean", background: "#F2F7FC", lineStyle: .curve,
        lineWidth: 1.5, mainLineWidth: 2.5,
        branchColors: ["#1E6FD9", "#0E9AA7", "#3D5A80", "#2A9D8F", "#4361EE", "#118AB2"],
        central: LevelStyle(shape: .roundedRect, fill: "#0B3954", text: "#FFFFFF",
                            fontSize: 24, weight: .semibold, padH: 24, padV: 14, radius: 12),
        main: LevelStyle(shape: .roundedRect, fill: "branch", text: "auto",
                         fontSize: 16, weight: .medium, padH: 14, padV: 8, radius: 8),
        sub: LevelStyle(shape: .roundedRect, fill: "branch-soft", text: "#0B2540",
                        fontSize: 13.5, padH: 10, padV: 5, radius: 6))

    /// 森林：米色纸底，绿与棕。
    static let forest = Theme(
        id: "forest", name: "Forest", background: "#F7F4EA", lineStyle: .curve,
        lineWidth: 1.5, mainLineWidth: 3,
        branchColors: ["#2D6A4F", "#BC6C25", "#588157", "#7F5539", "#386641", "#9C6644"],
        central: LevelStyle(shape: .ellipse, fill: "#283618", text: "#FEFAE0",
                            fontSize: 22, weight: .semibold, padH: 22, padV: 12),
        main: LevelStyle(shape: .roundedRect, fill: "#FFFDF5", text: "branch-dark", border: "branch", borderWidth: 2,
                         fontSize: 16, weight: .semibold, padH: 14, padV: 8, radius: 10),
        sub: LevelStyle(shape: .underline, fill: .none, text: "#3A3226", border: "branch", borderWidth: 1.5,
                        fontSize: 14, padH: 4, padV: 4, radius: 0))

    /// 日落：暖色系。
    static let sunset = Theme(
        id: "sunset", name: "Sunset", background: "#FFF7F0", lineStyle: .curve,
        lineWidth: 1.5, mainLineWidth: 2.5,
        branchColors: ["#E76F51", "#D62828", "#F77F00", "#C9184A", "#9D4EDD", "#E9A800"],
        central: LevelStyle(shape: .capsule, fill: "#E76F51", text: "#FFFFFF",
                            fontSize: 24, weight: .bold, padH: 28, padV: 14),
        main: LevelStyle(shape: .roundedRect, fill: "branch-soft", text: "branch-dark",
                         fontSize: 16, weight: .semibold, padH: 14, padV: 8, radius: 10),
        sub: LevelStyle(shape: .underline, fill: .none, text: "#3D2B24", border: "branch", borderWidth: 1.5,
                        fontSize: 14, padH: 4, padV: 4, radius: 0))

    /// 糖果：马卡龙色胶囊。
    static let candy = Theme(
        id: "candy", name: "Candy", background: "#FFFDF9", lineStyle: .curve,
        lineWidth: 2, mainLineWidth: 3,
        branchColors: ["#F28AB2", "#6CC5F0", "#9D8DF1", "#5FCF92", "#F7B267", "#F4845F"],
        central: LevelStyle(shape: .capsule, fill: "#FFFFFF", text: "#3A2E4D", border: "#3A2E4D", borderWidth: 2.5,
                            fontSize: 24, weight: .bold, padH: 28, padV: 14),
        main: LevelStyle(shape: .capsule, fill: "branch", text: "#FFFFFF",
                         fontSize: 16, weight: .semibold, padH: 16, padV: 8),
        sub: LevelStyle(shape: .capsule, fill: "branch-soft", text: "#3A2E4D",
                        fontSize: 13.5, padH: 12, padV: 5))

    /// 商务：方正、折线，适合组织结构图。
    static let business = Theme(
        id: "business", name: "Business", background: "#FFFFFF", lineStyle: .elbow,
        lineWidth: 1.2, mainLineWidth: 1.8,
        branchColors: ["#1F4E79", "#2E75B6", "#44546A", "#2F5597"],
        central: LevelStyle(shape: .rect, fill: "#1F4E79", text: "#FFFFFF",
                            fontSize: 22, weight: .semibold, padH: 24, padV: 14, radius: 2),
        main: LevelStyle(shape: .rect, fill: "branch-soft", text: "#1B2A3A", border: "branch", borderWidth: 1.2,
                         fontSize: 15, weight: .semibold, padH: 14, padV: 8, radius: 2),
        sub: LevelStyle(shape: .rect, fill: "#FFFFFF", text: "#273444", border: "#B8C4D2", borderWidth: 1,
                        fontSize: 13.5, padH: 10, padV: 6, radius: 2))

    /// 极简：黑白，无色块。
    static let minimal = Theme(
        id: "minimal", name: "Minimal", background: "#FFFFFF", lineStyle: .curve,
        lineWidth: 1.2, mainLineWidth: 1.8,
        branchColors: ["#2B2B2B"],
        central: LevelStyle(shape: .roundedRect, fill: .none, text: "#111111", border: "#111111", borderWidth: 2,
                            fontSize: 24, weight: .semibold, padH: 22, padV: 12, radius: 8),
        main: LevelStyle(shape: .underline, fill: .none, text: "#111111", border: "#2B2B2B", borderWidth: 1.8,
                         fontSize: 17, weight: .semibold, padH: 4, padV: 5, radius: 0),
        sub: LevelStyle(shape: .underline, fill: .none, text: "#333333", border: "#2B2B2B", borderWidth: 1.2,
                        fontSize: 14, padH: 4, padV: 4, radius: 0))

    /// 纸墨：米黄纸底，宋体，墨色线条。
    static let paper = Theme(
        id: "paper", name: "Ink & Paper", background: "#FBF6EC", lineStyle: .curve,
        lineWidth: 1.4, mainLineWidth: 2.4,
        branchColors: ["#5C4033", "#8B3A3A", "#3E5641", "#4A4E69", "#8B5E3C"],
        central: LevelStyle(shape: .ellipse, fill: .none, text: "#2B1D14", border: "#5C4033", borderWidth: 2,
                            fontSize: 24, weight: .bold, padH: 22, padV: 12),
        main: LevelStyle(shape: .underline, fill: .none, text: "branch-dark", border: "branch", borderWidth: 2.4,
                         fontSize: 17, weight: .semibold, padH: 4, padV: 5, radius: 0),
        sub: LevelStyle(shape: .underline, fill: .none, text: "#3B2F25", border: "branch", borderWidth: 1.4,
                        fontSize: 14.5, padH: 4, padV: 4, radius: 0),
        fontFamily: "Songti SC")

    /// 午夜：深色背景，霓虹分支。
    static let midnight = Theme(
        id: "midnight", name: "Midnight", background: "#141821", lineStyle: .curve,
        lineWidth: 1.6, mainLineWidth: 2.6,
        branchColors: ["#7AA2F7", "#BB9AF7", "#9ECE6A", "#E0AF68", "#F7768E", "#7DCFFF"],
        central: LevelStyle(shape: .roundedRect, fill: "#262C3F", text: "#EEF1F8", border: "#7AA2F7", borderWidth: 2,
                            fontSize: 24, weight: .semibold, padH: 24, padV: 14, radius: 12),
        main: LevelStyle(shape: .roundedRect, fill: "branch-soft", text: "#EEF1F8", border: "branch", borderWidth: 1.5,
                         fontSize: 16, weight: .medium, padH: 14, padV: 8, radius: 8),
        sub: LevelStyle(shape: .underline, fill: .none, text: "#C9CFDD", border: "branch", borderWidth: 1.5,
                        fontSize: 14, padH: 4, padV: 4, radius: 0))

    /// 石墨：深灰单色。
    static let graphite = Theme(
        id: "graphite", name: "Graphite", background: "#202326", lineStyle: .roundedElbow,
        linePaint: "#7D838C", lineWidth: 1.4, mainLineWidth: 2,
        branchColors: ["#9AA0A8"],
        central: LevelStyle(shape: .roundedRect, fill: "#F2F2F2", text: "#1C1E21",
                            fontSize: 22, weight: .semibold, padH: 22, padV: 12, radius: 8),
        main: LevelStyle(shape: .roundedRect, fill: "#363A40", text: "#F2F2F2",
                         fontSize: 15.5, weight: .medium, padH: 14, padV: 8, radius: 7),
        sub: LevelStyle(shape: .plain, fill: .none, text: "#D0D3D8",
                        fontSize: 14, padH: 6, padV: 4, radius: 0))
}
