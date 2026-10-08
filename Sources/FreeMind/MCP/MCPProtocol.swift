import Foundation

/// MCP 协议层：JSON-RPC 2.0 解码与方法调度（initialize / ping / tools/list / tools/call）。
/// 不碰网络——`dispatch(body:)` 是“请求字节 → 应答”的纯逻辑，测试里直接喂 JSON。
///
/// 不做会话跟踪（规范允许服务端不分配 `Mcp-Session-Id`）：每个请求自带全部信息，
/// App 重启后客户端拿旧连接继续调也不会出错。不提供 resources / prompts，工具已经够用。
enum MCPVersions {
    static let supported = ["2025-11-25", "2025-06-18", "2025-03-26"]
    static let latest = "2025-11-25"

    /// 客户端要的版本我们支持就用它的，否则给我们最新的（客户端不接受会自己断开）。
    static func negotiate(_ requested: String?) -> String {
        if let requested, supported.contains(requested) { return requested }
        return latest
    }
}

enum JSONRPCCode {
    static let parseError = -32700
    static let invalidRequest = -32600
    static let methodNotFound = -32601
    static let invalidParams = -32602
    static let internalError = -32603
}

enum MCPDispatchOutcome {
    /// JSON-RPC 应答（HTTP 200）。
    case response(MCPObject)
    /// 通知（没有 id），不需要应答体（HTTP 202）。
    case accepted
}

@MainActor
struct MCPDispatcher {
    let catalog: MCPCatalog
    var serverName = "FreeMind"
    var serverVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    var instructions = MCPDispatcher.defaultInstructions

    func dispatch(body: Data) async -> MCPDispatchOutcome {
        guard let parsed = MCPJSON.parse(body) else {
            return .response(Self.error(id: nil, code: JSONRPCCode.parseError, message: "parse error: body is not valid JSON"))
        }
        if parsed is [Any] {
            // 2025-06-18 起协议去掉了批量请求
            return .response(Self.error(id: nil, code: JSONRPCCode.invalidRequest, message: "JSON-RPC batches are not supported"))
        }
        guard let obj = parsed as? MCPObject, let method = obj["method"] as? String else {
            return .response(Self.error(id: (parsed as? MCPObject)?["id"], code: JSONRPCCode.invalidRequest,
                                        message: "invalid request: need a JSON-RPC 2.0 object with a method"))
        }
        guard let id = obj["id"], !(id is NSNull) else {
            // notifications/initialized、notifications/cancelled 等：收下即可
            return .accepted
        }
        let params = (obj["params"] as? MCPObject) ?? [:]

        switch method {
        case "initialize":
            let result: MCPObject = [
                "protocolVersion": MCPVersions.negotiate(params["protocolVersion"] as? String),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": serverName, "title": "FreeMind", "version": serverVersion],
                "instructions": instructions,
            ]
            return .response(Self.result(id: id, result))
        case "ping":
            return .response(Self.result(id: id, [:]))
        case "tools/list":
            return .response(Self.result(id: id, ["tools": catalog.listing()]))
        case "tools/call":
            guard let name = params["name"] as? String else {
                return .response(Self.error(id: id, code: JSONRPCCode.invalidParams, message: "tools/call needs params.name"))
            }
            do {
                let result = try await catalog.call(name: name, arguments: (params["arguments"] as? MCPObject) ?? [:])
                return .response(Self.result(id: id, result))
            } catch let error as MCPInvalidParams {
                return .response(Self.error(id: id, code: JSONRPCCode.invalidParams, message: error.message))
            } catch {
                return .response(Self.error(id: id, code: JSONRPCCode.internalError, message: "\(error)"))
            }
        case "resources/list":
            return .response(Self.result(id: id, ["resources": [MCPObject]()]))
        case "resources/templates/list":
            return .response(Self.result(id: id, ["resourceTemplates": [MCPObject]()]))
        case "prompts/list":
            return .response(Self.result(id: id, ["prompts": [MCPObject]()]))
        default:
            return .response(Self.error(id: id, code: JSONRPCCode.methodNotFound, message: "method not found: \(method)"))
        }
    }

    static func result(id: Any, _ result: MCPObject) -> MCPObject {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(id: Any?, code: Int, message: String) -> MCPObject {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    /// 随 `initialize` 下发给模型的使用说明（英文）。
    static let defaultInstructions = """
    FreeMind is a mind-map editor. Each open map is a tree of topics under one central topic, \
    plus optional relationships (curved arrows) between any two topics. \
    Call list_maps first: it shows the open maps, which one is in front, and what the user has selected. \
    Map tools act on the frontmost map unless you pass map_id. \
    Read a map with get_map before changing it; it prints every topic as "[id] title". \
    Topic ids are the 8-character values in brackets (any unique prefix of at least 4 characters works, \
    and "root" means the central topic). \
    To build or extend a map, prefer one add_topics call with nested topics (or a Markdown outline) \
    over many single calls. \
    Every change you make is one undo step the user can revert with Command-Z, and maps save automatically. \
    Markers are ids such as priority-1 … priority-6, task-0 / task-25 / task-50 / task-75 / task-100, \
    flag-red, star-blue, symbol-idea. Colors are hex strings like #E5484D.
    """
}
