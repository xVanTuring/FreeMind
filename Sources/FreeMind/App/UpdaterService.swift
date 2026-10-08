import Foundation
import Observation
import Sparkle

/// Sparkle 2 自动更新的薄封装（参考 UniReader 的 `UpdaterService`）。
///
/// 整个更新流程（拉 appcast、EdDSA 校验、下载、安装、重启）都交给 `SPUStandardUpdaterController`，
/// 界面用 Sparkle 自带的标准窗口：后台按间隔静默检查，真有新版本才弹窗。
/// 这层只负责 controller 的生命周期，并把设置页要显示的几个状态镜像成可观察属性。
///
/// 只在主线程使用：`SPUStandardUpdaterController` 假设由主线程驱动。
@MainActor
@Observable
final class UpdaterService {
    static let shared = UpdaterService()

    /// 正在检查时为 false（“立即检查”按钮据此禁用）。
    private(set) var canCheck = true
    private(set) var lastChecked: Date?
    /// 是否按间隔自动检查。Sparkle 自己持久化这个值，这里只是镜像。
    var automaticallyChecks: Bool {
        didSet {
            if controller.updater.automaticallyChecksForUpdates != automaticallyChecks {
                controller.updater.automaticallyChecksForUpdates = automaticallyChecks
            }
        }
    }

    /// 菜单里的“检查更新…”直接以它为 target（它自己会根据能否检查启用 / 禁用菜单项）。
    @ObservationIgnored let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"

    private init() {
        // 单元测试以 App 为宿主运行时不启动更新检查
        controller = SPUStandardUpdaterController(startingUpdater: !AppDelegate.isRunningTests,
                                                  updaterDelegate: nil, userDriverDelegate: nil)
        let updater = controller.updater
        canCheck = updater.canCheckForUpdates
        lastChecked = updater.lastUpdateCheckDate
        automaticallyChecks = updater.automaticallyChecksForUpdates
        // 这几个属性 Sparkle 标了 KVO，变化时回到主线程更新镜像
        observations = [
            updater.observe(\.canCheckForUpdates) { [weak self] updater, _ in
                let value = updater.canCheckForUpdates
                Task { @MainActor in self?.canCheck = value }
            },
            updater.observe(\.lastUpdateCheckDate) { [weak self] updater, _ in
                let value = updater.lastUpdateCheckDate
                Task { @MainActor in self?.lastChecked = value }
            },
            updater.observe(\.automaticallyChecksForUpdates) { [weak self] updater, _ in
                let value = updater.automaticallyChecksForUpdates
                Task { @MainActor in
                    if self?.automaticallyChecks != value { self?.automaticallyChecks = value }
                }
            },
        ]
    }

    /// 用户主动检查：Sparkle 全程接管界面，包括“已是最新版本”的提示。
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
