import AppKit

// 第一个创建的 NSDocumentController 会成为 shared，必须在 NSApp 启动前创建。
_ = DocumentController()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
