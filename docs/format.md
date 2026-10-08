# `.fmind` 文件格式

FreeMind 的专属格式是一个 **macOS package**（目录包）：在 Finder 里显示为单个文件，实际上是一个文件夹。
右键 ▸ “显示包内容” 可以看到里面的结构。

```
我的导图.fmind/
├── content.json                    导图内容（结构、主题、样式、折叠状态、视图状态）
└── attachments/                    附件和主题图片（没有时省略整个目录）
    ├── 3F2A…-UUID/
    │   └── 需求文档.pdf             保留原始文件名
    └── 9C41…-UUID/
        └── 截图.png
```

- UTI：`tech.xvanturing.freemind.map`，遵循 `com.apple.package`、`public.composite-content`
- 扩展名：`.fmind`
- 每个附件放在以资源 UUID 命名的子目录里，子目录内只有一个文件，文件名就是原始文件名（`/` 和 `:` 会被替换为 `-`）。
  这样同名文件不会冲突，用户“显示包内容”时也能直接看懂。
- 附件和图片共用同一个资源目录；`content.json` 里通过 UUID 引用。
- 保存时只重写 `content.json`，未变化的附件由 NSDocument 以硬链接方式保留，不会每次自动保存都复制大文件。
- 不再被任何主题引用的资源会在保存时从包里移除（在内存中保留到文档关闭，撤销后仍可恢复）。

## content.json

```jsonc
{
  "format": "freemind",          // 固定值
  "version": 1,                  // 格式版本；读到比自己新的版本会拒绝打开并提示升级
  "generator": "FreeMind 1.0.0",
  "map": {
    "structure": "mindmap",      // mindmap | logic-right | logic-left | org-down | tree
    "spacing": "standard",       // compact | standard | loose
    "lineStyle": "curve",        // 可选，覆盖主题的连线样式：curve | straight | elbow | roundedElbow
    "topicMaxWidth": 260,        // 主题文字最大宽度（pt）
    "theme": { … },              // 完整内嵌的主题，见下文
    "root": { … },               // 中心主题（Topic）
    "relationships": [ … ],      // 可选，联系线
    "relationshipsHidden": true  // 可选，隐藏联系线（只影响显示，联系线数据照常保存）；没有这个字段表示显示
  },
  "view": {                      // 可选，打开时恢复的视图
    "zoom": 1.0,
    "centerX": 0, "centerY": 0,  // 可视区域中心（布局坐标，中心主题中心为原点）
    "selection": ["UUID", …]
  }
}
```

### Topic

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | UUID | 必填 |
| `title` | string | 主题文字，可含换行 |
| `children` | [Topic] | 子主题，省略表示无 |
| `collapsed` | bool | 折叠状态，`true` 时才写入 |
| `note` | string | 备注（纯文本，保留 Markdown 原文） |
| `link` | string | 超链接（URL 或文件路径） |
| `attachments` | [{`id`, `name`, `size`}] | 附件，`id` 对应 `attachments/<id>/<name>` |
| `image` | {`id`, `name`, `width`, `height`} | 主题图片，宽高为显示尺寸（pt） |
| `markers` | [string] | 标记，见下表 |
| `labels` | [string] | 标签 |
| `style` | object | 单独样式覆盖：`shape` `fill` `textColor` `border` `fontSize` `bold` `italic` `branchColor` `boundary` |

缺省值一律省略，读取时缺失字段使用默认值，便于以后扩展字段而不破坏旧文件。

### 标记 id

| 组 | id |
|---|---|
| 优先级 | `priority-1` … `priority-6` |
| 进度 | `task-0` `task-25` `task-50` `task-75` `task-100` |
| 旗帜 | `flag-red` `flag-orange` `flag-yellow` `flag-green` `flag-blue` `flag-purple` `flag-gray` |
| 星星 | `star-<同上颜色>` |
| 符号 | `symbol-question` `symbol-important` `symbol-idea` `symbol-check` `symbol-cross` `symbol-heart` `symbol-like` `symbol-dislike` `symbol-pin` `symbol-time` `symbol-person` `symbol-money` |

同一组内互斥（符号组除外）。

### 颜色（Paint）

颜色是字符串：

- `#RRGGBB` / `#RRGGBBAA`：固定颜色
- `branch`：所在分支的颜色
- `branch-soft`：分支色与背景混合后的浅色
- `branch-mid`：分支色与背景的中间色
- `branch-dark`：加深的分支色
- `auto`：根据底色自动选择黑色或白色（只用于文字）
- `none`：不绘制

### Theme

```jsonc
{
  "id": "classic", "name": "Classic",
  "background": "#FFFFFF",
  "lineStyle": "curve", "linePaint": "branch", "lineWidth": 1.5, "mainLineWidth": 2.5,
  "branchColors": ["#3B82F6", "#F59E0B", …],
  "central": LevelStyle, "main": LevelStyle, "sub": LevelStyle,
  "fontFamily": "Songti SC"          // 可选
}
```

`LevelStyle`：`shape`（roundedRect / rect / capsule / ellipse / diamond / underline / plain）、`fill`、`text`、`border`、
`borderWidth`、`fontSize`、`weight`（regular / medium / semibold / bold）、`padH`、`padV`、`radius`。

主题完整内嵌在文档里：导图拿到别的电脑上，或者以后内置主题调整了，显示效果都不会变。

### Relationship（联系线）

| 字段 | 说明 |
|---|---|
| `id` `from` `to` | UUID；`from` / `to` 为主题 id |
| `title` | 标签文字 |
| `control1` / `control2` | 可选，`{dx, dy}`：两个控制点分别相对起点主题、终点主题中心的偏移；省略表示自动弧度 |
| `labelPosition` | 可选，0…1：标签中心在曲线上的位置（贝塞尔参数，0.5 是中点）；省略表示自动放置，避开其他标签和主题。用户手动调整过联系线形状时写入 |
| `color` | 可选，颜色（Paint） |
| `dashed` | 默认 `true` |
| `arrowStart` / `arrowEnd` | 默认 `false` / `true` |

## 与其他格式的转换

| 格式 | 导入 | 导出 | 说明 |
|---|---|---|---|
| Markdown | ✓ | ✓ | 标题 + 嵌套列表；备注为段落（备注里以 `-`、`#`、`1.` 开头的行会加反斜杠转义，导入时还原）；`- [x]` / `- [ ]` ↔ 进度 100% / 0%（25–75% 导出为未完成）；可连同附件导出到 `<名称>.assets/` 文件夹，导入时按相对路径找回附件（`📎 [名称](路径)`）和图片（`![](路径)`）。出于安全考虑，导入只读取 md 文件所在目录之内的相对路径，绝对路径、`../` 和指向目录外的符号链接一律忽略 |
| OPML | ✓ | ✓ | `text`、`_note`、`url`（也认 `htmlUrl`、`xmlUrl`）、`_collapsed`；Workflowy 的 `_complete` 导入为进度 100%；文字里的格式标签（`<b>` 等）去掉，整行 `**粗体**` 改为粗体样式；空条目不导入。已用 OPML 2.0 官方示例和 Workflowy、Logseq、MultiMarkdown 等导出的文件验证 |
| XMind | ✓ | — | 新版 `content.json`（文件里同时带的 `content.xml` 只是给旧版本看的提示，忽略）与 XMind 8 `content.xml`；每个画布导入为一张导图；支持备注、链接、附件、图片、标签、标记、折叠状态、联系线、外框。FreeMind 没有的元素：标注、概要、自由主题当作普通子主题接在后面；XMind 8 的批注追加到备注末尾；外框框住多个子主题时给每个子主题各加一个；没有对应图标的标记（表情、箭头、标签等）不导入；主题样式按 FreeMind 默认风格显示。已用 XMind 8 Pro、XMind Zen、XMind 2026 实际保存的文件验证 |
| PNG / PDF | — | ✓ | PDF 为矢量 |
