import Foundation
import Observation

/// 用户自定义主题，存放在 `~/Library/Application Support/FreeMind/Themes.json`。
@Observable
final class ThemeLibrary {
    static let shared = ThemeLibrary()

    private(set) var customThemes: [Theme] = []

    @ObservationIgnored private let fileURL: URL

    private init() {
        fileURL = AppDirectories.support.appendingPathComponent("Themes.json")
        if let data = try? Data(contentsOf: fileURL),
           let themes = try? JSONDecoder().decode([Theme].self, from: data) {
            customThemes = themes
        }
    }

    var allThemes: [Theme] { Theme.builtins + customThemes }

    func customTheme(id: String) -> Theme? { customThemes.first { $0.id == id } }

    func theme(id: String) -> Theme? { Theme.builtin(id: id) ?? customTheme(id: id) }

    func isCustom(_ id: String) -> Bool { customTheme(id: id) != nil }

    /// 保存为新的自定义主题，返回带新 id 的主题。
    @discardableResult
    func add(_ theme: Theme, name: String) -> Theme {
        var t = theme
        t.id = "custom-" + UUID().uuidString
        t.name = name
        customThemes.append(t)
        persist()
        return t
    }

    func update(_ theme: Theme) {
        guard let i = customThemes.firstIndex(where: { $0.id == theme.id }) else { return }
        customThemes[i] = theme
        persist()
    }

    func delete(id: String) {
        customThemes.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            try encoder.encode(customThemes).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("FreeMind: failed to save themes: \(error)")
        }
    }
}

enum AppDirectories {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("FreeMind", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var templates: URL {
        let url = support.appendingPathComponent("Templates", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
