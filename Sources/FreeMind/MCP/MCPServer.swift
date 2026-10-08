import Foundation
import Network
import Observation

/// MCP（Model Context Protocol）服务：让本机的 AI Agent（Claude Code、Codex 等）通过 HTTP + JSON-RPC
/// 读取和编辑打开着的导图。跑在 App 进程里，只监听 127.0.0.1，每个请求都要带口令。
///
/// 结构参考 Perch / UniReader 的 `Sources/MCP`：协议和 HTTP 解析是纯逻辑（`MCPProtocol` / `MCPHTTP`），
/// 这里只管监听、鉴权和启停。网络收发在自己的队列上，鉴权和工具执行跳到主线程（导图模型只在主线程改）。
@MainActor
@Observable
final class MCPServer {
    static let shared = MCPServer()

    nonisolated static let defaultPort = 8775

    private(set) var isRunning = false
    /// 实际监听的端口（端口设为 0 时由系统分配，测试用）。
    private(set) var listeningPort: Int?
    private(set) var lastError: String?

    @ObservationIgnored let catalog = MCPCatalog()
    @ObservationIgnored let facade = MCPFacade()
    @ObservationIgnored private lazy var dispatcher = MCPDispatcher(catalog: catalog)
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private nonisolated let queue = DispatchQueue(label: "tech.xvanturing.freemind.mcp")

    /// 端口、口令、写入开关从哪里读。默认读设置，测试里换成固定值。
    @ObservationIgnored var portProvider: () -> Int = { Preferences.shared.mcpPort }
    @ObservationIgnored var tokenProvider: () -> String = { Preferences.shared.mcpToken }

    init() {
        catalog.isWriteAllowed = { Preferences.shared.mcpAllowWrite }
        MCPTools.registerAll(catalog: catalog, facade: facade)
    }

    var endpointURL: String { "http://127.0.0.1:\(listeningPort ?? portProvider())/mcp" }

    // MARK: - 启停

    func start() {
        guard listener == nil else { return }
        let port = portProvider()
        guard port == 0 || (1024...65535).contains(port), let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            lastError = LF("Port %d is not valid. Use a number from 1024 to 65535.", port)
            return
        }
        let params = NWParameters.tcp
        // 改端口后立即重启时旧连接可能还在 TIME_WAIT，允许复用地址
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)
        let listener: NWListener
        do {
            // 端口已经由 requiredLocalEndpoint 指定，不能再用 NWListener(using:on:) 传一次（会报 EINVAL）
            listener = try NWListener(using: params)
        } catch {
            lastError = LF("Cannot listen on port %d: %@", port, error.localizedDescription)
            return
        }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            let actual = listener?.port.map { Int($0.rawValue) }
            Task { @MainActor in
                guard let self, self.listener === listener else { return }
                switch state {
                case .ready:
                    self.isRunning = true
                    self.listeningPort = actual
                    self.lastError = nil
                    NSLog("FreeMind MCP: listening on 127.0.0.1:%d", actual ?? port)
                case .failed(let error):
                    NSLog("FreeMind MCP: listener failed: %@", "\(error)")
                    self.stop()
                    self.lastError = LF("Cannot listen on port %d: %@", port, error.localizedDescription)
                default:
                    break
                }
            }
        }
        self.listener = listener
        lastError = nil
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        listeningPort = nil
    }

    /// 改了端口或口令后调用：在运行就重启，没在运行就什么都不做。
    func restartIfRunning() {
        guard listener != nil else { return }
        stop()
        start()
    }

    // MARK: - 连接（在 `queue` 上）

    private nonisolated func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    /// 攒字节直到解出一个完整请求（头和体可能分几次到）。一问一答后关闭连接。
    private nonisolated func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self, error == nil else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch MCPHTTP.parse(buffer) {
            case .incomplete:
                if isComplete { connection.cancel() } else { self.receive(connection, buffer: buffer) }
            case let .invalid(status, message):
                self.send(.text(status, message), on: connection)
            case let .complete(request):
                self.handle(request, on: connection)
            }
        }
    }

    private nonisolated func send(_ response: MCPHTTP.Response, on connection: NWConnection) {
        connection.send(content: MCPHTTP.serialize(response), completion: .contentProcessed { _ in connection.cancel() })
    }

    private nonisolated func handle(_ request: MCPHTTP.Request, on connection: NWConnection) {
        guard request.path == "/mcp" else {
            send(.text(404, "not found; MCP endpoint is POST /mcp"), on: connection)
            return
        }
        // 浏览器发起的请求一定带 Origin；命令行客户端不带。只挡别的网站，不挡本机工具。
        guard MCPHTTP.originAllowed(request.header("origin")) else {
            send(.text(403, "origin not allowed"), on: connection)
            return
        }
        if let version = request.header("mcp-protocol-version"), !MCPVersions.supported.contains(version) {
            send(.json(400, ["error": "unsupported MCP-Protocol-Version \(version); supported: \(MCPVersions.supported.joined(separator: ", "))"]),
                 on: connection)
            return
        }
        switch request.method {
        case "POST":
            break
        case "GET":
            // 不提供服务端主动推送的事件流（规范允许返回 405）
            send(.text(405, "GET is not supported; this server does not open server-to-client streams"), on: connection)
            return
        case "DELETE":
            // 没有会话可结束
            send(.empty(200), on: connection)
            return
        default:
            send(.text(405, "method not allowed"), on: connection)
            return
        }
        Task { @MainActor in
            guard MCPHTTP.tokenMatches(MCPHTTP.bearer(request.headers), expected: self.tokenProvider()) else {
                self.send(.json(401, ["error": "missing or wrong bearer token; copy it from FreeMind › Settings › Agent"]),
                          on: connection)
                return
            }
            switch await self.dispatcher.dispatch(body: request.body) {
            case .accepted:
                self.send(.empty(202), on: connection)
            case .response(let object):
                self.send(.json(200, object), on: connection)
            }
        }
    }
}
