# MCP 服务（让 AI Agent 操作导图）

FreeMind 打开后会在本机启动一个 [MCP](https://modelcontextprotocol.io) 服务，Claude Code、Codex 等 AI Agent
连上后可以读取打开着的导图，也可以直接添加、修改、移动、删除主题，调整格式，新建和保存导图。

## 接入

设置 › Agent：

| 设置 | 默认 | 说明 |
|---|---|---|
| 允许 AI Agent 使用 FreeMind | 开 | 打开 FreeMind 时启动服务；切换后立即生效 |
| 允许 Agent 修改导图 | 开 | 关闭后只能用读取类工具，修改类工具会返回错误并提示用户去开 |
| 端口 | 8775 | 只监听 `127.0.0.1`，其他电脑连不上 |
| 访问令牌 | 首次启动随机生成 | 每个请求都要带 `Authorization: Bearer <令牌>`；“生成新令牌”后要重新配置 Agent |

“拷贝命令”给出 Claude Code 的接入命令，“拷贝 JSON”给出通用的 MCP 配置：

```sh
claude mcp add --transport http freemind http://127.0.0.1:8775/mcp --header "Authorization: Bearer <令牌>"
```

```json
{
  "mcpServers": {
    "freemind": {
      "type": "http",
      "url": "http://127.0.0.1:8775/mcp",
      "headers": { "Authorization": "Bearer <令牌>" }
    }
  }
}
```

## 工具

主题 id 是 `get_map` 输出里方括号中的 8 位值（任意至少 4 位的唯一前缀都可以，`root` 表示中心主题）。
不传 `map_id` 时操作最前面窗口里的导图；`map_id` 可以是 `list_maps` 给出的编号（`m1`、`m2`…，本次运行内有效）、
文件路径或窗口标题。

读取（任何时候可用）：

| 工具 | 作用 |
|---|---|
| `list_maps` | 打开的导图（从前到后）、文件路径、主题数、用户当前选中的主题、是否允许修改 |
| `get_map` | 整张导图或某个分支的缩进大纲（`[id] 标题 · 标记 · 标签 · 链接…`，备注另起一行），末尾列出联系线；也可以输出 Markdown |
| `get_topic` | 单个主题的全部信息：路径、父主题和位置、子主题、备注、链接、标签、标记、样式、附件、联系线 |
| `search_topics` | 在标题、标签、备注里查找（忽略大小写和重音） |
| `get_selection` | 用户选中的主题或联系线 |
| `render_map` | 把导图画成 PNG 返回给 Agent（最长边不超过 2400 像素，折叠的分支不画） |

界面操作（不改内容，任何时候可用）：

| 工具 | 作用 |
|---|---|
| `select_topics` | 在窗口里选中主题并滚动过去（被折叠的会先展开祖先） |
| `open_map` | 打开 `.fmind`，或把 Markdown / OPML / XMind / 文本导入成新导图 |

修改（受“允许 Agent 修改导图”控制）：

| 工具 | 作用 |
|---|---|
| `add_topics` | 在某个主题下一次添加多个主题，可以任意嵌套（对象形式或 Markdown 大纲） |
| `update_topics` | 批量修改标题、备注、链接、标签、标记、样式；传 `null` 清除某项 |
| `move_topics` | 移动到别的父主题下，或调整顺序 |
| `delete_topics` | 删除主题（连同子主题，或 `keep_children` 让子主题上移一级）；标为 destructive |
| `fold_topics` | 折叠 / 展开、全部展开、全部折叠、只显示前几层 |
| `add_relationship` / `update_relationship` / `delete_relationship` | 联系线 |
| `set_map_format` | 结构、风格、间距、连线样式、主题宽度 |
| `create_map` | 新建导图窗口（可以直接带内容） |
| `save_map` | 保存；新导图第一次要给 `path`，已有文件绝不覆盖 |

## 设计

- **代码位置**：`Sources/FreeMind/MCP/`。手写的 JSON-RPC 2.0 over HTTP，不依赖 MCP SDK，和 Perch、UniReader 是同一套做法。
  - `MCPHTTP`：字节 ↔ HTTP 请求 / 应答的纯函数，加上 Origin、令牌校验。
  - `MCPProtocol`：JSON-RPC 调度（`initialize` / `ping` / `tools/list` / `tools/call`）。不做会话跟踪
    （规范允许不分配 `Mcp-Session-Id`），App 重启后客户端继续调用也不会出错。`GET` 返回 405（不提供服务端推送）。
  - `MCPCatalog`：工具表和统一的写入闸门，写工具在这里一处拦截。
  - `MCPServer`：`NWListener` 监听、鉴权、启停。网络收发在自己的队列上，鉴权和工具执行都在主线程。
  - `MCPFacade`：找文档、解析主题 id、把导图格式化成文字；`MCPFacade+Edit` 是全部修改操作。
  - `MCPTools`：工具注册（名字、给模型看的英文说明、参数 schema、分级）。
- **修改走和界面相同的路径**：每个写工具先在导图副本上做完全部修改（参数出错就整个放弃，导图不变），
  再一次性交给 `MapEditor.perform`。一次调用正好是一个撤销步骤，撤销菜单里显示为“撤销 Agent：插入主题”这样的名字，
  用户可以用 ⌘Z 撤销 Agent 的任何修改。写之前会先提交用户正在行内编辑的文字。
- **安全**：只监听 `127.0.0.1`；每个请求都要令牌（定长比较）；带了 `Origin` 头的请求必须来自本机地址，
  防止网页借浏览器访问本机端口（DNS 重绑定）。
- **令牌存在 UserDefaults**（`mcpToken`），没有像 Perch 那样放钥匙串：本地构建是 ad-hoc 签名，
  每次重新编译签名都会变，钥匙串会反复弹窗要求授权。
- 单元测试里 App 不启动服务（`AppDelegate.isRunningTests`）。`MCPTests` 覆盖 HTTP 解析、调度、各工具，
  并在随机端口上起一个服务，用 `URLSession` 走真实 HTTP 往返。

## 手动测试

```sh
TOKEN=$(defaults read tech.xvanturing.FreeMind mcpToken)
curl -s -X POST http://127.0.0.1:8775/mcp -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_map","arguments":{}}}' | jq -r '.result.content[0].text'
```
