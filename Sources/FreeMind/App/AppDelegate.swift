import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: NSWindow?
    private var shortcutsWindow: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.build()
    }

    /// 单元测试以本应用为宿主运行时，不弹任何窗口。
    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.isRunningTests { return }
        let prefs = Preferences.shared
        if !prefs.hasLaunchedBefore {
            prefs.hasLaunchedBefore = true
            // 第一次启动：打开“快速上手”导图（此时不再弹模板库）
            isFirstLaunch = true
            openGettingStarted(nil)
        }
    }

    private var isFirstLaunch = false

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { !Self.isRunningTests }

    /// 启动时没有恢复任何文档、或点 Dock 图标且没有窗口时：显示模板库。
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if isFirstLaunch || !NSDocumentController.shared.documents.isEmpty { return true }
        if Preferences.shared.showTemplateGalleryOnNew {
            TemplateGalleryController.show()
        } else {
            DocumentController.sharedController.createBlankDocument()
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - 菜单命令

    @objc func newFromTemplate(_ sender: Any?) {
        TemplateGalleryController.show()
    }

    @objc func importDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = DocumentTypes.importableExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.message = L("Choose a Markdown, OPML, XMind or text file to turn into a mind map.")
        panel.prompt = L("Import")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            DocumentController.sharedController.importFile(at: url)
        }
    }

    @objc func openGettingStarted(_ sender: Any?) {
        DocumentController.sharedController.openUntitled(map: BuiltinTemplates.gettingStarted(), resources: [:],
                                                         displayName: LT("Getting Started", "快速上手"), markEdited: false)
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = L("Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showKeyboardShortcuts(_ sender: Any?) {
        if shortcutsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: KeyboardShortcutsView()))
            window.title = L("Keyboard Shortcuts")
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 560, height: 640))
            window.center()
            shortcutsWindow = window
        }
        shortcutsWindow?.makeKeyAndOrderFront(nil)
    }
}
