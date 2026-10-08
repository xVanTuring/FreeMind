import Foundation

/// MCP 端点用的最小 HTTP/1.1：字节 → 请求、应答 → 字节两个纯函数，不碰网络，测试里直接喂字节。
/// 参考 UniReader 的 `Sources/MCP/MCPHTTP.swift`。
///
/// 只支持 MCP 客户端实际用到的那部分：带 Content-Length 的请求体，不支持 chunked 请求体；
/// 一个连接只处理一个请求，应答后关闭（`Connection: close`）。
enum MCPHTTP {
    /// 请求体上限。一次工具调用的参数（哪怕是整份 Markdown 大纲）远到不了这个量级。
    static let maxBodyBytes = 8 * 1024 * 1024

    struct Request {
        var method: String
        var path: String
        /// 头名已转小写（HTTP 头名不区分大小写）。
        var headers: [String: String]
        var body: Data

        func header(_ name: String) -> String? { headers[name.lowercased()] }
    }

    enum ParseResult {
        /// 还没收齐（头没到空行，或请求体不够 Content-Length），继续收。
        case incomplete
        case complete(Request)
        /// 坏请求：应答这个状态码和一句说明后关闭连接。
        case invalid(status: Int, message: String)
    }

    private static let headerEnd = Data("\r\n\r\n".utf8)

    static func parse(_ buffer: Data) -> ParseResult {
        guard let r = buffer.range(of: headerEnd) else {
            return buffer.count > 65_536 ? .invalid(status: 431, message: "request header too large") : .incomplete
        }
        guard let head = String(data: buffer[buffer.startIndex..<r.lowerBound], encoding: .utf8) else {
            return .invalid(status: 400, message: "request head is not UTF-8")
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return .invalid(status: 400, message: "bad request line") }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        if let te = headers["transfer-encoding"], te.lowercased().contains("chunked") {
            return .invalid(status: 411, message: "chunked request bodies are not supported; send Content-Length")
        }
        var length = 0
        if let cl = headers["content-length"] {
            guard let n = Int(cl), n >= 0 else { return .invalid(status: 400, message: "bad Content-Length") }
            length = n
        }
        if length > maxBodyBytes { return .invalid(status: 413, message: "request body too large") }
        let bodyStart = r.upperBound
        guard buffer.endIndex - bodyStart >= length else { return .incomplete }

        // 查询串对 MCP 没有意义，直接丢掉
        var path = String(parts[1])
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        let body = Data(buffer[bodyStart..<(bodyStart + length)])
        return .complete(Request(method: String(parts[0]).uppercased(), path: path, headers: headers, body: body))
    }

    // MARK: - 应答

    struct Response {
        var status: Int
        var headers: [(String, String)] = []
        var body = Data()

        static func json(_ status: Int, _ object: Any, extra: [(String, String)] = []) -> Response {
            Response(status: status, headers: [("Content-Type", "application/json")] + extra, body: MCPJSON.data(object))
        }

        static func text(_ status: Int, _ text: String) -> Response {
            Response(status: status, headers: [("Content-Type", "text/plain; charset=utf-8")], body: Data(text.utf8))
        }

        static func empty(_ status: Int) -> Response {
            Response(status: status)
        }
    }

    static func serialize(_ r: Response) -> Data {
        var head = "HTTP/1.1 \(r.status) \(reason(r.status))\r\n"
        for (k, v) in r.headers { head += "\(k): \(v)\r\n" }
        head += "Content-Length: \(r.body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(r.body)
        return out
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 411: return "Length Required"
        case 413: return "Payload Too Large"
        case 431: return "Request Header Fields Too Large"
        default: return "Internal Server Error"
        }
    }

    // MARK: - 安全校验

    /// `Origin` 校验（MCP 规范要求，防浏览器里的 DNS 重绑定）：没带 = 命令行客户端，放行；
    /// 带了就必须是本机地址。端口不看——要挡的是别的网站，不是别的端口。
    static func originAllowed(_ origin: String?) -> Bool {
        guard let origin, !origin.isEmpty else { return true }
        guard let host = URL(string: origin)?.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    /// `Authorization: Bearer xxx` 里的 xxx。
    static func bearer(_ headers: [String: String]) -> String? {
        guard let v = headers["authorization"] else { return nil }
        let parts = v.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return nil }
        return String(parts[1]).trimmingCharacters(in: .whitespaces)
    }

    /// 定长比较口令，耗时与内容无关。
    static func tokenMatches(_ presented: String?, expected: String) -> Bool {
        guard let presented, !expected.isEmpty else { return false }
        let a = Array(presented.utf8), b = Array(expected.utf8)
        var diff = a.count ^ b.count
        for i in 0..<min(a.count, b.count) { diff |= Int(a[i] ^ b[i]) }
        return diff == 0
    }
}
