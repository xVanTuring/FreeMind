import Foundation
import Observation

/// 应用设置（UserDefaults）。
@Observable
final class Preferences {
    static let shared = Preferences()

    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Key {
        static let defaultTheme = "defaultTheme"
        static let defaultStructure = "defaultStructure"
        static let defaultSpacing = "defaultSpacing"
        static let showGallery = "showTemplateGalleryOnNew"
        static let showWelcome = "showWelcomeOnLaunch"
        static let headingLevels = "markdownHeadingLevels"
        static let mdNotes = "markdownIncludeNotes"
        static let mdAttachments = "markdownExportAttachments"
        static let mdLabels = "markdownIncludeLabels"
        static let restoreView = "restoreViewState"
        static let pngScale = "pngScale"
        static let hasLaunched = "hasLaunchedBefore"
        static let galleryReset = "templateGalleryPreferenceReset"
    }

    var defaultThemeID: String { didSet { defaults.set(defaultThemeID, forKey: Key.defaultTheme) } }
    var defaultStructure: MapStructure { didSet { defaults.set(defaultStructure.rawValue, forKey: Key.defaultStructure) } }
    var defaultSpacing: MapSpacing { didSet { defaults.set(defaultSpacing.rawValue, forKey: Key.defaultSpacing) } }
    /// 新建导图时先显示模板库。
    var showTemplateGalleryOnNew: Bool { didSet { defaults.set(showTemplateGalleryOnNew, forKey: Key.showGallery) } }
    /// 启动时（没有打开的导图）显示欢迎窗口；关闭后改为直接新建。
    var showWelcomeOnLaunch: Bool { didSet { defaults.set(showWelcomeOnLaunch, forKey: Key.showWelcome) } }
    var markdownHeadingLevels: Int { didSet { defaults.set(markdownHeadingLevels, forKey: Key.headingLevels) } }
    var markdownIncludeNotes: Bool { didSet { defaults.set(markdownIncludeNotes, forKey: Key.mdNotes) } }
    var markdownExportAttachments: Bool { didSet { defaults.set(markdownExportAttachments, forKey: Key.mdAttachments) } }
    var markdownIncludeLabels: Bool { didSet { defaults.set(markdownIncludeLabels, forKey: Key.mdLabels) } }
    /// 重新打开导图时恢复上次的缩放和位置。
    var restoreViewState: Bool { didSet { defaults.set(restoreViewState, forKey: Key.restoreView) } }
    var pngScale: Int { didSet { defaults.set(pngScale, forKey: Key.pngScale) } }

    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: Key.hasLaunched) }
        set { defaults.set(newValue, forKey: Key.hasLaunched) }
    }

    private init() {
        // 旧版本启动时也弹模板库，用户为了不让它在启动时出现会取消“新建时显示”，结果新建也看不到模板。
        // 启动改为欢迎窗口后，把这个设置恢复成默认值（只做一次）。
        if !defaults.bool(forKey: Key.galleryReset) {
            defaults.removeObject(forKey: Key.showGallery)
            defaults.set(true, forKey: Key.galleryReset)
        }
        defaults.register(defaults: [
            Key.defaultTheme: Theme.classic.id,
            Key.defaultStructure: MapStructure.mindMap.rawValue,
            Key.defaultSpacing: MapSpacing.standard.rawValue,
            Key.showGallery: true,
            Key.showWelcome: true,
            Key.headingLevels: 3,
            Key.mdNotes: true,
            Key.mdAttachments: true,
            Key.mdLabels: false,
            Key.restoreView: true,
            Key.pngScale: 2,
        ])
        defaultThemeID = defaults.string(forKey: Key.defaultTheme) ?? Theme.classic.id
        defaultStructure = MapStructure(rawValue: defaults.string(forKey: Key.defaultStructure) ?? "") ?? .mindMap
        defaultSpacing = MapSpacing(rawValue: defaults.string(forKey: Key.defaultSpacing) ?? "") ?? .standard
        showTemplateGalleryOnNew = defaults.bool(forKey: Key.showGallery)
        showWelcomeOnLaunch = defaults.bool(forKey: Key.showWelcome)
        markdownHeadingLevels = min(max(defaults.integer(forKey: Key.headingLevels), 0), 6)
        markdownIncludeNotes = defaults.bool(forKey: Key.mdNotes)
        markdownExportAttachments = defaults.bool(forKey: Key.mdAttachments)
        markdownIncludeLabels = defaults.bool(forKey: Key.mdLabels)
        restoreViewState = defaults.bool(forKey: Key.restoreView)
        pngScale = min(max(defaults.integer(forKey: Key.pngScale), 1), 4)
    }

    var defaultTheme: Theme {
        Theme.builtin(id: defaultThemeID) ?? ThemeLibrary.shared.customTheme(id: defaultThemeID) ?? .classic
    }

    var markdownOptions: MarkdownExportOptions {
        var o = MarkdownExportOptions()
        o.headingLevels = markdownHeadingLevels
        o.includeNotes = markdownIncludeNotes
        o.includeLabels = markdownIncludeLabels
        return o
    }
}
