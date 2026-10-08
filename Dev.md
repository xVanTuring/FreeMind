# FreeMind 开发说明

## 构建

需要 macOS 14 以上、Xcode 16 以上和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```sh
xcodegen                      # 由 project.yml 生成 FreeMind.xcodeproj
xcodebuild -project FreeMind.xcodeproj -scheme FreeMind -configuration Release build
xcodebuild -project FreeMind.xcodeproj -scheme FreeMind test
```

本地构建使用 ad-hoc 签名，可以直接运行。第一次构建会解析自动更新用的 [Sparkle](https://sparkle-project.org) 包。

## 脚本

- `scripts/make-icon.sh`：把 `Sources/FreeMind/Resources/AppIcon.svg` 栅格化为应用图标（需要 `rsvg-convert`）
- `scripts/check-strings.sh`：检查所有界面文字是否都有中文翻译
- `scripts/package.sh`：打出 Developer ID 签名并经过公证的 `.zip` 和 `.dmg`；`scripts/release.sh`：发布 GitHub release 并更新 Sparkle 的更新源（[说明](docs/release.md)）

## 文档

- [`docs/format.md`](docs/format.md)：`.fmind` 文件格式
- [`docs/mcp.md`](docs/mcp.md)：给 AI Agent 用的 MCP 服务和工具列表
- [`docs/release.md`](docs/release.md)：签名、公证、发布和自动更新

## 项目结构

```
Sources/FreeMind/
├─ App/            启动、主菜单、欢迎窗口、文档控制器（新建走模板库，打开 Markdown/OPML/XMind 走导入）
├─ Model/          主题树、标记、联系线（值类型，撤销直接保存快照）
├─ Theme/          颜色描述、风格定义、内置风格、自定义风格库
├─ Layout/         样式解析、文字测量、五种结构的布局算法
├─ Canvas/         画布视图（绘制、选择、行内编辑、拖放、联系线交互）、渲染器、弹出编辑框
├─ Document/       NSDocument 子类、.fmind 包读写、附件存储、导出
├─ Editor/         编辑核心 MapEditor（所有修改与撤销）、窗口、工具栏、查找栏、状态栏
├─ Inspector/      右侧格式面板（样式 / 导图 / 标记 / 内容）
├─ ImportExport/   Markdown、OPML、XMind、图片导出
├─ Templates/      内置模板、用户模板、模板库窗口
├─ Settings/       偏好设置、设置窗口、快捷键窗口
├─ MCP/            给 AI Agent 用的本机 MCP 服务（HTTP、JSON-RPC、工具）
└─ Resources/      Info.plist、图标、中英文本地化
Extensions/
├─ QuickLook/      空格预览扩展（数据型预览，输出 PDF）
├─ Thumbnail/      Finder 缩略图扩展
└─ Shared/         两个扩展共用的读取代码和沙盒 entitlements
```
