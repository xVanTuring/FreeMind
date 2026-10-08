import Foundation

/// 本地化取词：key 就是英文原文，值在 `en.lproj` / `zh-Hans.lproj` 的 Localizable.strings 里。
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// 带格式参数的本地化。
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}
