import Foundation

/// 工具分级。
enum MCPToolTier {
    /// 只读：任何时候都能调。
    case read
    /// 只改界面不改内容（选中、滚动到主题、打开文件）：任何时候都能调。
    case navigate
    /// 修改导图：受设置里的“允许 Agent 修改导图”开关管。
    case write
    /// 删除：同受写入开关管，额外标 `destructiveHint` 让客户端向用户确认。
    case delete

    var writes: Bool { self == .write || self == .delete }

    /// 协议里的 `annotations`。
    var annotations: MCPObject {
        switch self {
        case .read: return ["readOnlyHint": true, "openWorldHint": false]
        case .navigate: return ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false]
        case .write: return ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false]
        case .delete: return ["readOnlyHint": false, "destructiveHint": true, "idempotentHint": false, "openWorldHint": false]
        }
    }
}

/// 工具返回：`text` 给模型读，`structured` 给程序用，`image` 是导图截图。
struct MCPToolResult {
    var text: String
    var structured: MCPObject?
    var image: Data?

    init(text: String, structured: MCPObject? = nil, image: Data? = nil) {
        self.text = text
        self.structured = structured
        self.image = image
    }

    func json() -> MCPObject {
        var content: [MCPObject] = []
        if let image {
            content.append(["type": "image", "data": image.base64EncodedString(), "mimeType": "image/png"])
        }
        content.append(["type": "text", "text": text])
        var out: MCPObject = ["content": content, "isError": false]
        if let structured { out["structuredContent"] = structured }
        return out
    }

    static func failure(_ message: String) -> MCPObject {
        ["content": [["type": "text", "text": message]], "isError": true]
    }
}

struct MCPTool {
    let name: String
    let title: String
    let description: String
    let inputSchema: MCPObject
    let tier: MCPToolTier
    let handler: @MainActor (MCPArgs) async throws -> MCPToolResult

    func listing() -> MCPObject {
        ["name": name, "title": title, "description": description,
         "inputSchema": inputSchema, "annotations": tier.annotations]
    }
}

/// 工具注册表 + 统一的写入闸门：写入开关关着时拒绝所有写工具，这条规则只写在 `call` 这一处。
@MainActor
final class MCPCatalog {
    private(set) var tools: [MCPTool] = []
    private var byName: [String: MCPTool] = [:]
    /// 由 `MCPServer` 注入（读设置），测试里可以直接换掉。
    var isWriteAllowed: () -> Bool = { false }

    func register(_ tool: MCPTool) {
        precondition(byName[tool.name] == nil, "MCP 工具重名：\(tool.name)")
        tools.append(tool)
        byName[tool.name] = tool
    }

    func listing() -> [MCPObject] { tools.map { $0.listing() } }

    /// 执行一个工具。两层错误分开：
    /// - 工具不存在、缺必填参数、参数类型不对 → 抛 `MCPInvalidParams`（调度器映射成 -32602）；
    /// - 执行失败 → `isError: true` 的正常应答，模型读到后自己纠正。
    func call(name: String, arguments: MCPObject) async throws -> MCPObject {
        guard let tool = byName[name] else { throw MCPInvalidParams("unknown tool '\(name)'") }
        if let required = tool.inputSchema["required"] as? [String] {
            for key in required where arguments[key] == nil || arguments[key] is NSNull {
                throw MCPInvalidParams("argument '\(key)' is required")
            }
        }
        if tool.tier.writes, !isWriteAllowed() {
            return MCPToolResult.failure(
                "Editing is turned off in FreeMind › Settings › Agent, so \(name) was not run. Ask the user to turn on \"Allow agents to edit maps\".")
        }
        do {
            return try await tool.handler(MCPArgs(arguments)).json()
        } catch let error as MCPInvalidParams {
            throw error
        } catch let error as MCPToolError {
            return MCPToolResult.failure(error.message)
        } catch {
            return MCPToolResult.failure("\(name) failed: \(error.localizedDescription)")
        }
    }
}
