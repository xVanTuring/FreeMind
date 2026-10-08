# FreeMind — 开发说明

macOS 原生思维导图（类 XMind）。AppKit 文档型应用 + 自绘画布，SwiftUI 只用于检查器、模板库、设置等面板。
xcodegen 管理工程（`FreeMind.xcodeproj` 由 `project.yml` 生成，不要手改），macOS 14+，Swift 5 语言模式，ad-hoc 签名。

## 构建 / 测试 / 运行

```sh
xcodegen
xcodebuild -project FreeMind.xcodeproj -scheme FreeMind -configuration Debug -derivedDataPath build/DerivedData build 2>&1 | grep -E "error:|BUILD "
xcodebuild -project FreeMind.xcodeproj -scheme FreeMind -configuration Debug -derivedDataPath build/DerivedData test 2>&1 | grep -E "error:|failed \(|TEST "
build/DerivedData/Build/Products/Debug/FreeMind.app/Contents/MacOS/FreeMind   # 直接运行，日志输出到终端
```

- 渲染目检：`TEST_RUNNER_FREEMIND_RENDER_DIR=<目录> xcodebuild … test` 会把五种结构、全部风格、全部模板、检查器各页、
  模板库、设置窗口渲染成 PNG 写到该目录（`RenderSnapshotTests`），并生成一份带附件的 `sample.fmind`。
- README 配图：`TEST_RUNNER_FREEMIND_SHOWCASE_DIR=<目录> xcodebuild … test -only-testing:FreeMindTests/ShowcaseTests`
  生成示例导图（`docs/samples/` 里的就是它生成的）和 `structures.png`、`themes.png` 两张拼图；窗口截图（hero、welcome、
  gallery、colors）是打开示例导图后用 `screencapture -l <窗口号>` 截的。README 有英文（`README.md`）和中文（`README.zh-CN.md`）两份，改一份要同步另一份。
- 导入兼容性：`TEST_RUNNER_FREEMIND_IMPORT_SAMPLES=<目录> xcodebuild … test -only-testing:FreeMindTests/ImportSamplesTests`
  把目录里的 .xmind / .opml / .md 全部导入一遍，统计写到 `<目录>/import-report.txt`。样例文件不进仓库（版权属于原作者），
  上次用的来源：tobyqin/xmindparser 的 tests/*.xmind（XMind 8 Pro / Zen / 2026）、zhuifengshen/xmind 的 docs/*.xmind、
  hosting.opml.org/dave/spec/*.opml、Workflowy / Logseq / MultiMarkdown 导出的 OPML。固定下来的规则在 `ImportCompatibilityTests`。
- 单元测试以 App 为宿主运行；`AppDelegate.isRunningTests` 为真时不弹任何窗口。
- 新增界面文字后跑 `scripts/check-strings.sh`，确保 `zh-Hans.lproj/Localizable.strings` 有对应翻译。

## 关键设计

- **数据模型是值类型**（`MindMap` / `Topic` / `Relationship`）。所有可撤销修改都经过 `MapEditor.perform(_:select:coalesce:_:)`：
  先存整张图快照，修改后注册撤销。连续输入（备注、拖动滑块、拖动联系线控制柄）用 `coalesce` 合并成一步。
- **折叠不进入撤销栈**（`performWithoutUndo`，但会标记文档已修改）；撤销恢复快照时保留当前折叠状态。
- 每次修改后整体重排（`LayoutEngine.run()`，文字测量有缓存）。坐标以中心主题中心为原点，画布四周留白 640pt，
  `updateFrame(anchor:)` 在画布尺寸变化时调整滚动位置，保证内容不跳动。
- `MapRenderer` 是唯一的绘制代码，画布、PNG/PDF 导出、打印、模板 / 风格缩略图共用。
- **快捷键**：Tab、Return、Delete、空格等纯按键在 `MindMapCanvasView.keyDown` 里直接处理——
  窗口里有其他可聚焦控件时，Tab 会被键盘焦点切换抢走，不会走菜单快捷键。菜单上的同名快捷键只用于显示和兜底。
- 行内编辑用 `TopicTextEditor`（NSTextView），有独立撤销栈；输入时实时重排（`editingTextDidChange`）但不写模型，
  结束编辑才提交为一步撤销。选中主题后直接打字会进入编辑并把按键转交输入框（支持中文输入法组字）。
- 包格式读写见 `docs/format.md`。保存时在原有 FileWrapper 上增量更新，附件未变化时由 NSDocument 硬链接。
- 菜单命令走响应链，画布是第一响应者；工具栏按钮直接以画布为 target（检查器有焦点时也能用）。
- **启动与新建**：启动时没有打开的导图 → 欢迎窗口（`WelcomeWindow.swift`，最近列表来自 `NSDocumentController.recentDocumentURLs`，
  缩略图复用 `MapPreviewLoader`）；⌘N → `DocumentController.newDocument` → 模板库。任何文档加入
  `DocumentController.addDocument` 时关闭欢迎窗口。Dock 右键菜单在 `AppDelegate.applicationDockMenu`。
- 检查器（格式面板）用“名称 + 紧凑控件”的行（`InspectorRow`），颜色用 `ColorButton` 点开色板，不要平铺大块选项。

## Quick Look 扩展

- `FreeMindQuickLook`（空格预览）和 `FreeMindThumbnail`（Finder 缩略图）两个 app-extension 只编译模型、布局、渲染、
  `DocumentFormat.swift`、`L.swift` 这部分代码（见 `project.yml`），直接读包内 `content.json` 和附件，开沙盒。
  新增被这些文件引用的类型时，注意别把 App 专属的依赖（Preferences、NSDocument 等）带进去，否则扩展编译失败。
- 验证缩略图：`qlmanage -x -t -s 400 -o <目录> 某个.fmind`（要加 `-x` 走 quicklookd）。
  `qlmanage -p` 在命令行里调起预览扩展会崩在 qlmanage 自身（它没有 Bundle ID），预览只能在 Finder 里按空格验证。

## 约定

- UI 文字一律 `L("English")` / `LF("English %d", …)`，key 就是英文原文；模板正文用 `LT("English", "中文")`。
- 代码注释用中文。
