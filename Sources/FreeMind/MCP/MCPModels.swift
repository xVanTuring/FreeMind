import Foundation

/// 松散的 JSON 对象：MCP 协议往返的最小公分母，不为每个工具的输入输出单独建 Codable 类型。
/// 与 Perch / UniReader 的 `Sources/MCP` 同一套约定。
typealias MCPObject = [String: Any]

enum MCPJSON {
    static func parse(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func data(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data()
    }

    static func string(_ value: Any, pretty: Bool = false) -> String {
        var options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .withoutEscapingSlashes, .sortedKeys]
        if pretty { options.insert(.prettyPrinted) }
        let data = (try? JSONSerialization.data(withJSONObject: value, options: options)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

/// 工具执行中的业务失败（导图不存在、主题 id 不对……）。`MCPCatalog.call` 把它包成
/// `isError: true` 的正常应答，让模型读到消息后自己改参数重试，而不是收到协议级错误。
struct MCPToolError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// 参数不合法：协议级错误，对应 JSON-RPC -32602。
struct MCPInvalidParams: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// 按类型读取工具参数，类型不对统一抛 `MCPInvalidParams`。
/// 对模型常见的小偏差放宽：数字写成字符串、布尔写成 "true" 都接受。
struct MCPArgs {
    let raw: MCPObject

    init(_ raw: MCPObject) { self.raw = raw }

    /// 传了这个 key 且不是 null。
    func has(_ key: String) -> Bool {
        guard let value = raw[key] else { return false }
        return !(value is NSNull)
    }

    /// 传了这个 key，值是 null（“清除”的意思）。
    func isNull(_ key: String) -> Bool { raw[key] is NSNull }

    func string(_ key: String) throws -> String? {
        guard has(key) else { return nil }
        guard let s = raw[key] as? String else { throw MCPInvalidParams("'\(key)' must be a string") }
        return s
    }

    func requiredString(_ key: String) throws -> String {
        guard let s = try string(key), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPInvalidParams("'\(key)' is required and must be a non-empty string")
        }
        return s
    }

    func int(_ key: String) throws -> Int? {
        guard has(key) else { return nil }
        if let n = raw[key] as? NSNumber { return n.intValue }
        if let s = raw[key] as? String, let n = Int(s.trimmingCharacters(in: .whitespaces)) { return n }
        throw MCPInvalidParams("'\(key)' must be an integer")
    }

    func double(_ key: String) throws -> Double? {
        guard has(key) else { return nil }
        if let n = raw[key] as? NSNumber { return n.doubleValue }
        if let s = raw[key] as? String, let n = Double(s.trimmingCharacters(in: .whitespaces)) { return n }
        throw MCPInvalidParams("'\(key)' must be a number")
    }

    func bool(_ key: String) throws -> Bool? {
        guard has(key) else { return nil }
        if let b = raw[key] as? Bool { return b }
        if let s = raw[key] as? String {
            switch s.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: break
            }
        }
        throw MCPInvalidParams("'\(key)' must be a boolean")
    }

    func stringArray(_ key: String) throws -> [String]? {
        guard has(key) else { return nil }
        // 只给了一个字符串时当作单元素数组
        if let s = raw[key] as? String { return [s] }
        guard let items = raw[key] as? [Any] else { throw MCPInvalidParams("'\(key)' must be an array of strings") }
        return try items.map {
            guard let s = $0 as? String else { throw MCPInvalidParams("'\(key)' must be an array of strings") }
            return s
        }
    }

    func requiredStringArray(_ key: String) throws -> [String] {
        guard let items = try stringArray(key), !items.isEmpty else {
            throw MCPInvalidParams("'\(key)' is required and must be a non-empty array of strings")
        }
        return items
    }

    func object(_ key: String) throws -> MCPObject? {
        guard has(key) else { return nil }
        guard let o = raw[key] as? MCPObject else { throw MCPInvalidParams("'\(key)' must be an object") }
        return o
    }

    func objectArray(_ key: String) throws -> [MCPObject]? {
        guard has(key) else { return nil }
        guard let items = raw[key] as? [Any] else { throw MCPInvalidParams("'\(key)' must be an array of objects") }
        return try items.map {
            guard let o = $0 as? MCPObject else { throw MCPInvalidParams("'\(key)' must be an array of objects") }
            return o
        }
    }
}

/// 构造工具 `inputSchema` 用的 JSON Schema 片段，只覆盖用得到的子集。
enum MCPSchema {
    static func object(_ properties: MCPObject, required: [String] = []) -> MCPObject {
        var o: MCPObject = ["type": "object", "properties": properties]
        if !required.isEmpty { o["required"] = required }
        return o
    }

    static func string(_ description: String) -> MCPObject {
        ["type": "string", "description": description]
    }

    static func enumeration(_ values: [String], _ description: String) -> MCPObject {
        ["type": "string", "enum": values, "description": description]
    }

    static func integer(_ description: String, min: Int? = nil, max: Int? = nil) -> MCPObject {
        var o: MCPObject = ["type": "integer", "description": description]
        if let min { o["minimum"] = min }
        if let max { o["maximum"] = max }
        return o
    }

    static func number(_ description: String) -> MCPObject {
        ["type": "number", "description": description]
    }

    static func boolean(_ description: String) -> MCPObject {
        ["type": "boolean", "description": description]
    }

    static func array(_ items: MCPObject, _ description: String) -> MCPObject {
        ["type": "array", "items": items, "description": description]
    }

    /// 允许显式传 null（表示“清除”）。
    static func nullable(_ schema: MCPObject) -> MCPObject {
        var o = schema
        if let type = o["type"] as? String { o["type"] = [type, "null"] }
        if let values = o["enum"] as? [Any] { o["enum"] = values + [NSNull()] }
        return o
    }
}
