import XCTest
@testable import FreeMind

/// MCP 服务：HTTP 解析、JSON-RPC 调度、各个工具，以及走真实 HTTP 的完整往返。
@MainActor
final class MCPTests: XCTestCase {
    private var doc: MindMapDocument!
    private var catalog: MCPCatalog!
    private var facade: MCPFacade!
    private var writeAllowed = true

    override func setUp() async throws {
        doc = MindMapDocument()
        var map = MindMap.blank(title: "Root")
        map.root.children[0].title = "Alpha"
        map.root.children[0].children = [Topic(title: "Alpha child", note: "secret note about apples")]
        map.root.children[1].title = "Beta"
        doc.editor.load(map)
        doc.undoManager?.groupsByEvent = false
        facade = MCPFacade()
        facade.documents = { [unowned self] in [self.doc] }
        catalog = MCPCatalog()
        catalog.isWriteAllowed = { [unowned self] in self.writeAllowed }
        MCPTools.registerAll(catalog: catalog, facade: facade)
        writeAllowed = true
    }

    private var map: MindMap { doc.editor.map }

    private func id(_ title: String) -> String {
        MCPFacade.shortID(map.allTopics.first { $0.title == title }!.id)
    }

    /// 调用工具，返回文字内容和是否出错。
    @discardableResult
    private func call(_ name: String, _ args: MCPObject = [:]) async throws -> (text: String, isError: Bool, result: MCPObject) {
        let result = try await catalog.call(name: name, arguments: args)
        let text = ((result["content"] as? [MCPObject])?.last?["text"] as? String) ?? ""
        return (text, result["isError"] as? Bool ?? false, result)
    }

    // MARK: - HTTP

    func testHTTPParserWaitsForWholeBody() {
        let head = "POST /mcp?x=1 HTTP/1.1\r\nHost: localhost\r\nContent-Length: 10\r\nAuthorization: Bearer abc\r\n\r\n"
        guard case .incomplete = MCPHTTP.parse(Data((head + "01234").utf8)) else { return XCTFail("should wait") }
        guard case .complete(let request) = MCPHTTP.parse(Data((head + "0123456789").utf8)) else { return XCTFail("should parse") }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/mcp")
        XCTAssertEqual(String(decoding: request.body, as: UTF8.self), "0123456789")
        XCTAssertEqual(MCPHTTP.bearer(request.headers), "abc")
    }

    func testHTTPRejectsChunkedBodies() {
        let raw = "POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
        guard case .invalid(let status, _) = MCPHTTP.parse(Data(raw.utf8)) else { return XCTFail() }
        XCTAssertEqual(status, 411)
    }

    func testOriginAndToken() {
        XCTAssertTrue(MCPHTTP.originAllowed(nil))
        XCTAssertTrue(MCPHTTP.originAllowed("http://localhost:3000"))
        XCTAssertTrue(MCPHTTP.originAllowed("http://127.0.0.1"))
        XCTAssertFalse(MCPHTTP.originAllowed("https://evil.example"))
        XCTAssertFalse(MCPHTTP.originAllowed("null"))
        XCTAssertTrue(MCPHTTP.tokenMatches("secret", expected: "secret"))
        XCTAssertFalse(MCPHTTP.tokenMatches("secreT", expected: "secret"))
        XCTAssertFalse(MCPHTTP.tokenMatches(nil, expected: "secret"))
        XCTAssertFalse(MCPHTTP.tokenMatches("", expected: ""))
    }

    // MARK: - 协议

    private func dispatch(_ object: Any) async -> MCPObject? {
        let outcome = await MCPDispatcher(catalog: catalog).dispatch(body: MCPJSON.data(object))
        guard case .response(let response) = outcome else { return nil }
        return response
    }

    func testInitializeAndToolList() async {
        let initialize = await dispatch(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                         "params": ["protocolVersion": "2025-06-18", "capabilities": [:],
                                                    "clientInfo": ["name": "test", "version": "1"]]])
        let result = initialize?["result"] as? MCPObject
        XCTAssertEqual(result?["protocolVersion"] as? String, "2025-06-18")
        XCTAssertNotNil(result?["instructions"])

        let unknownVersion = await dispatch(["jsonrpc": "2.0", "id": 2, "method": "initialize", "params": ["protocolVersion": "1999-01-01"]])
        XCTAssertEqual((unknownVersion?["result"] as? MCPObject)?["protocolVersion"] as? String, MCPVersions.latest)

        let list = await dispatch(["jsonrpc": "2.0", "id": 3, "method": "tools/list"])
        let names = ((list?["result"] as? MCPObject)?["tools"] as? [MCPObject])?.compactMap { $0["name"] as? String } ?? []
        XCTAssertTrue(names.contains("get_map"))
        XCTAssertTrue(names.contains("add_topics"))
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testNotificationsAndErrors() async {
        let outcome = await MCPDispatcher(catalog: catalog).dispatch(
            body: MCPJSON.data(["jsonrpc": "2.0", "method": "notifications/initialized"]))
        guard case .accepted = outcome else { return XCTFail("notifications get no response") }

        let unknown = await dispatch(["jsonrpc": "2.0", "id": 1, "method": "nope"])
        XCTAssertEqual((unknown?["error"] as? MCPObject)?["code"] as? Int, JSONRPCCode.methodNotFound)

        let missing = await dispatch(["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "get_topic", "arguments": [:]]])
        XCTAssertEqual((missing?["error"] as? MCPObject)?["code"] as? Int, JSONRPCCode.invalidParams)

        let parse = await MCPDispatcher(catalog: catalog).dispatch(body: Data("{oops".utf8))
        guard case .response(let r) = parse else { return XCTFail() }
        XCTAssertEqual((r["error"] as? MCPObject)?["code"] as? Int, JSONRPCCode.parseError)
    }

    // MARK: - 读取

    func testListAndReadMap() async throws {
        let list = try await call("list_maps")
        XCTAssertTrue(list.text.contains(doc.agentID))
        XCTAssertTrue(list.text.contains("(frontmost)"))

        let outline = try await call("get_map")
        XCTAssertFalse(outline.isError)
        XCTAssertTrue(outline.text.contains("[\(id("Root"))] Root"))
        XCTAssertTrue(outline.text.contains("    [\(id("Alpha child"))] Alpha child"))
        XCTAssertTrue(outline.text.contains("note: secret note about apples"))

        let shallow = try await call("get_map", ["depth": 1, "include_notes": false])
        XCTAssertFalse(shallow.text.contains("Alpha child"))
        XCTAssertTrue(shallow.text.contains("+1 more topic"))
        XCTAssertFalse(shallow.text.contains("+1 more topics"))

        let markdown = try await call("get_map", ["format": "markdown", "topic_id": id("Alpha")])
        XCTAssertTrue(markdown.text.hasPrefix("# Alpha"))

        let topic = try await call("get_topic", ["topic_id": id("Alpha child")])
        XCTAssertTrue(topic.text.contains("Path: Root › Alpha › Alpha child"))

        let search = try await call("search_topics", ["query": "APPLES"])
        XCTAssertTrue(search.text.contains("Alpha child"))
        XCTAssertTrue(search.text.contains("note: …"))
    }

    func testTopicIDResolution() async throws {
        let root = try await call("get_topic", ["topic_id": "root"])
        XCTAssertTrue(root.text.contains("central topic"))
        let full = try await call("get_topic", ["topic_id": map.root.children[1].id.uuidString])
        XCTAssertTrue(full.text.hasPrefix("[\(id("Beta"))] Beta"))
        let bad = try await call("get_topic", ["topic_id": "zzzzzzzz"])
        XCTAssertTrue(bad.isError)
        let short = try await call("get_topic", ["topic_id": "ab"])
        XCTAssertTrue(short.isError)
    }

    // MARK: - 修改

    func testAddNestedTopicsIsOneUndoStep() async throws {
        let before = map
        let result = try await call("add_topics", [
            "parent_id": id("Beta"),
            "topics": [
                ["title": "Plan", "markers": ["priority-1", "priority-2", "task-50"], "labels": ["a", " a ", "b"],
                 "children": [["title": "Step 1"], ["title": "Step 2", "note": "details"]]],
                ["title": "Risks", "link": "https://example.com"],
            ],
        ])
        XCTAssertFalse(result.isError, result.text)
        let beta = map.topic(map.root.children[1].id)!
        XCTAssertEqual(beta.children.map(\.title), ["Plan", "Risks"])
        XCTAssertEqual(beta.children[0].children.map(\.title), ["Step 1", "Step 2"])
        // 同组标记互斥：两个优先级只留最后一个
        XCTAssertEqual(beta.children[0].markers.map(\.rawValue), ["priority-2", "task-50"])
        XCTAssertEqual(beta.children[0].labels, ["a", "b"])
        XCTAssertTrue(result.text.contains("Step 2"))

        XCTAssertTrue(doc.undoManager!.canUndo)
        XCTAssertEqual(doc.undoManager!.undoActionName, LF("Agent: %@", L("Insert Topics")))
        doc.undoManager!.undo()
        XCTAssertEqual(map, before)
    }

    func testAddTopicsFromMarkdownAtIndex() async throws {
        let result = try await call("add_topics", ["markdown": "- One\n  - One.a\n- Two", "index": 0])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(map.root.children.prefix(2).map(\.title), ["One", "Two"])
        XCTAssertEqual(map.root.children[0].children.map(\.title), ["One.a"])
    }

    func testInvalidInputChangesNothing() async throws {
        let before = map
        let badMarker = try await call("add_topics", ["topics": [["title": "Fine"], ["title": "Bad", "markers": ["priority-9"]]]])
        XCTAssertTrue(badMarker.isError)
        XCTAssertTrue(badMarker.text.contains("priority-1"))
        let badColor = try await call("update_topics", ["updates": [["topic_id": id("Alpha"), "title": "Changed",
                                                                     "style": ["fill": "red"]]]])
        XCTAssertTrue(badColor.isError)
        XCTAssertEqual(map, before)
        XCTAssertFalse(doc.undoManager!.canUndo)
    }

    func testUpdateTopics() async throws {
        let alpha = id("Alpha")
        _ = try await call("update_topics", ["updates": [["topic_id": alpha, "link": "https://a.example",
                                                          "markers": ["flag-red"], "style": ["fill": "#e5484d", "bold": true]]]])
        let result = try await call("update_topics", ["updates": [
            ["topic_id": alpha, "title": "Alpha 2", "add_markers": ["flag-blue", "symbol-idea"], "link": NSNull(),
             "style": ["bold": NSNull()]],
            ["topic_id": id("Beta"), "note": "new note"],
        ]])
        XCTAssertFalse(result.isError, result.text)
        let t = map.root.children[0]
        XCTAssertEqual(t.title, "Alpha 2")
        XCTAssertNil(t.link)
        XCTAssertEqual(t.markers.map(\.rawValue), ["flag-blue", "symbol-idea"])
        XCTAssertEqual(t.style.fill, Paint("#E5484D"))
        XCTAssertNil(t.style.bold)
        XCTAssertEqual(map.root.children[1].note, "new note")
    }

    func testMoveAndDeleteTopics() async throws {
        let child = id("Alpha child")
        let moved = try await call("move_topics", ["topic_ids": [child], "parent_id": "root", "index": 0])
        XCTAssertFalse(moved.isError, moved.text)
        XCTAssertEqual(map.root.children[0].title, "Alpha child")
        XCTAssertTrue(map.root.children[1].children.isEmpty)

        let intoSelf = try await call("move_topics", ["topic_ids": [id("Alpha")], "parent_id": id("Alpha")])
        XCTAssertTrue(intoSelf.isError)

        _ = try await call("add_topics", ["parent_id": id("Beta"), "markdown": "- B1\n- B2"])
        let kept = try await call("delete_topics", ["topic_ids": [id("Beta")], "keep_children": true])
        XCTAssertFalse(kept.isError, kept.text)
        XCTAssertNil(map.allTopics.first { $0.title == "Beta" })
        XCTAssertNotNil(map.allTopics.first { $0.title == "B1" })

        let root = try await call("delete_topics", ["topic_ids": ["root"]])
        XCTAssertTrue(root.isError)
    }

    func testRelationshipsAndFormat() async throws {
        let added = try await call("add_relationship", ["from_id": id("Alpha"), "to_id": id("Beta"), "title": "depends on"])
        XCTAssertFalse(added.isError, added.text)
        let relID = (added.result["structuredContent"] as? MCPObject)?["relationship_id"] as! String
        let outline = try await call("get_map")
        XCTAssertTrue(outline.text.contains("[\(relID)] [\(id("Alpha"))] Alpha → [\(id("Beta"))] Beta · \"depends on\""))

        _ = try await call("update_relationship", ["relationship_id": relID, "dashed": false, "color": "#0090FF"])
        XCTAssertEqual(map.relationships.first?.dashed, false)
        XCTAssertEqual(map.relationships.first?.color, Paint("#0090FF"))
        _ = try await call("delete_relationship", ["relationship_id": relID])
        XCTAssertTrue(map.relationships.isEmpty)

        let format = try await call("set_map_format", ["structure": "org-down", "theme": "Midnight", "line_style": "elbow"])
        XCTAssertFalse(format.isError, format.text)
        XCTAssertEqual(map.structure, .orgChart)
        XCTAssertEqual(map.theme.id, "midnight")
        XCTAssertEqual(map.lineStyle, .elbow)
        let badTheme = try await call("set_map_format", ["theme": "nope"])
        XCTAssertTrue(badTheme.isError)
    }

    /// 用户隐藏了联系线：get_map 说明一下；Agent 新建联系线时和界面上一样自动显示。
    func testHiddenRelationships() async throws {
        _ = try await call("add_relationship", ["from_id": id("Alpha"), "to_id": id("Beta")])
        doc.editor.setRelationshipsHidden(true)
        let outline = try await call("get_map")
        XCTAssertTrue(outline.text.contains("1 relationship (hidden on the canvas)"), outline.text)
        let added = try await call("add_relationship", ["from_id": id("Beta"), "to_id": id("Alpha")])
        XCTAssertFalse(added.isError, added.text)
        XCTAssertFalse(map.relationshipsHidden)
        XCTAssertEqual(doc.editor.layout.relationships.count, 2)
    }

    func testFoldAndSelect() async throws {
        _ = try await call("fold_topics", ["action": "collapse", "topic_ids": [id("Alpha")]])
        XCTAssertTrue(map.root.children[0].collapsed)
        let selected = try await call("select_topics", ["topic_ids": [id("Alpha child")]])
        XCTAssertFalse(selected.isError, selected.text)
        // 选中被折叠的主题会先展开它的祖先
        XCTAssertFalse(map.root.children[0].collapsed)
        XCTAssertEqual(doc.editor.selection, [map.root.children[0].children[0].id])
        let selection = try await call("get_selection")
        XCTAssertTrue(selection.text.contains("Alpha child"))
    }

    func testWriteToolsBlockedWhenEditingIsOff() async throws {
        writeAllowed = false
        let before = map
        let result = try await call("add_topics", ["markdown": "- Nope"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("Allow agents to edit maps"))
        XCTAssertEqual(map, before)
        // 读取和选中不受影响
        let read = try await call("get_map")
        XCTAssertFalse(read.isError)
        let select = try await call("select_topics", ["topic_ids": [id("Beta")]])
        XCTAssertFalse(select.isError)
    }

    func testRenderMap() async throws {
        let result = try await call("render_map")
        let content = result.result["content"] as? [MCPObject]
        XCTAssertEqual(content?.first?["type"] as? String, "image")
        let data = Data(base64Encoded: content?.first?["data"] as? String ?? "")
        XCTAssertNotNil(data.flatMap { NSImage(data: $0) })
    }

    func testNoOpenMap() async throws {
        facade.documents = { [] }
        let result = try await call("get_map")
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("create_map"))
    }

    // MARK: - 真实 HTTP 往返

    func testHTTPRoundTrip() async throws {
        let server = MCPServer()
        server.portProvider = { 0 }
        server.tokenProvider = { "test-token" }
        server.catalog.isWriteAllowed = { true }
        server.facade.documents = { [unowned self] in [self.doc] }
        server.start()
        defer { server.stop() }
        for _ in 0..<200 where !server.isRunning { try await Task.sleep(nanoseconds: 10_000_000) }
        let port = try XCTUnwrap(server.listeningPort)
        let url = URL(string: "http://127.0.0.1:\(port)/mcp")!

        func post(_ body: Any, token: String? = "test-token", origin: String? = nil) async throws -> (Int, MCPObject?) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
            request.httpBody = MCPJSON.data(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            return ((response as! HTTPURLResponse).statusCode, MCPJSON.parse(data) as? MCPObject)
        }

        let (noToken, _) = try await post(["jsonrpc": "2.0", "id": 1, "method": "ping"], token: nil)
        XCTAssertEqual(noToken, 401)
        let (wrongToken, _) = try await post(["jsonrpc": "2.0", "id": 1, "method": "ping"], token: "nope")
        XCTAssertEqual(wrongToken, 401)
        let (badOrigin, _) = try await post(["jsonrpc": "2.0", "id": 1, "method": "ping"], origin: "https://evil.example")
        XCTAssertEqual(badOrigin, 403)

        let (status, initialize) = try await post(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                                   "params": ["protocolVersion": "2025-06-18"]])
        XCTAssertEqual(status, 200)
        XCTAssertEqual(((initialize?["result"] as? MCPObject)?["serverInfo"] as? MCPObject)?["name"] as? String, "FreeMind")

        let (accepted, _) = try await post(["jsonrpc": "2.0", "method": "notifications/initialized"])
        XCTAssertEqual(accepted, 202)

        let (_, added) = try await post(["jsonrpc": "2.0", "id": 2, "method": "tools/call",
                                         "params": ["name": "add_topics", "arguments": ["markdown": "- 来自 Agent 的主题"]]])
        XCTAssertEqual((added?["result"] as? MCPObject)?["isError"] as? Bool, false)
        XCTAssertEqual(map.root.children.last?.title, "来自 Agent 的主题")

        let (_, read) = try await post(["jsonrpc": "2.0", "id": 3, "method": "tools/call",
                                        "params": ["name": "get_map", "arguments": [:]]])
        let text = (((read?["result"] as? MCPObject)?["content"] as? [MCPObject])?.first?["text"] as? String) ?? ""
        XCTAssertTrue(text.contains("来自 Agent 的主题"))

        var get = URLRequest(url: url)
        get.setValue("Bearer test-token", forHTTPHeaderField: "Authorization")
        let (_, getResponse) = try await URLSession.shared.data(for: get)
        XCTAssertEqual((getResponse as! HTTPURLResponse).statusCode, 405)
    }
}
