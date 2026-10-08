import Foundation

/// 注册全部 MCP 工具：名字、说明、参数 schema、分级，处理逻辑都在 `MCPFacade`。
/// 说明文字是给模型看的，用英文，写清楚参数的格式和默认值。
@MainActor
enum MCPTools {
    static func registerAll(catalog: MCPCatalog, facade: MCPFacade) {
        registerReadTools(catalog: catalog, facade: facade)
        registerTopicTools(catalog: catalog, facade: facade)
        registerMapTools(catalog: catalog, facade: facade)
    }

    // MARK: - 共用 schema

    static let mapID = MCPSchema.string(
        "Which map: an id from list_maps (such as m1), the file path, or the window title. Default: the frontmost map.")

    static let topicIDs = MCPSchema.array(MCPSchema.string("Topic id"), "Topic ids from get_map (8 characters; \"root\" is the central topic)")

    static let style = MCPSchema.object([
        "shape": MCPSchema.nullable(MCPSchema.enumeration(TopicShape.allCases.map(\.rawValue), "Topic shape")),
        "fill": MCPSchema.nullable(MCPSchema.string("Fill color, #RRGGBB, or \"none\" for no fill")),
        "text_color": MCPSchema.nullable(MCPSchema.string("Text color, #RRGGBB")),
        "border": MCPSchema.nullable(MCPSchema.string("Border color, #RRGGBB, or \"none\"")),
        "branch_color": MCPSchema.nullable(MCPSchema.string("Color of the lines of this topic's whole branch, #RRGGBB")),
        "font_size": MCPSchema.nullable(MCPSchema.number("Font size in points (8–96)")),
        "bold": MCPSchema.nullable(MCPSchema.boolean("Bold text")),
        "italic": MCPSchema.nullable(MCPSchema.boolean("Italic text")),
        "boundary": MCPSchema.nullable(MCPSchema.boolean("Draw a dashed frame around this topic and all its subtopics")),
    ])

    static let topicSpec = MCPSchema.object([
        "title": MCPSchema.string("Topic text"),
        "note": MCPSchema.string("Longer note shown in the note panel (plain text or Markdown)"),
        "link": MCPSchema.string("Hyperlink URL"),
        "labels": MCPSchema.array(MCPSchema.string("Label"), "Short labels shown under the topic"),
        "markers": MCPSchema.array(MCPSchema.string("Marker id"), "Marker ids such as priority-1, task-50, flag-red, symbol-idea"),
        "style": style,
        "collapsed": MCPSchema.boolean("Collapse this topic's subtopics (default false)"),
        "children": MCPSchema.array(["type": "object"], "Subtopics, each an object with these same fields"),
    ], required: ["title"])

    // MARK: - 读取

    private static func registerReadTools(catalog: MCPCatalog, facade: MCPFacade) {
        catalog.register(MCPTool(
            name: "list_maps",
            title: "List open maps",
            description: "List the mind maps open in FreeMind (front to back) with their map_id, file path, topic count and the user's current selection, and whether agents may edit. Call this first.",
            inputSchema: MCPSchema.object([:]),
            tier: .read
        ) { [weak catalog] _ in
            facade.listMaps(writeAllowed: catalog?.isWriteAllowed() ?? false)
        })

        catalog.register(MCPTool(
            name: "get_map",
            title: "Read map",
            description: "Read a map (or one branch) as an indented outline. Each line is \"[id] title\" followed by markers, labels, link and other details; notes follow on lines starting with \"note:\". Relationships are listed at the end. Use format \"markdown\" for a Markdown outline without ids.",
            inputSchema: MCPSchema.object([
                "map_id": mapID,
                "topic_id": MCPSchema.string("Only this topic and its subtopics. Default: the whole map"),
                "depth": MCPSchema.integer("How many levels below the starting topic to include. Default: all", min: 0),
                "include_notes": MCPSchema.boolean("Include topic notes (default true)"),
                "format": MCPSchema.enumeration(["outline", "markdown"], "Output format (default outline)"),
            ]),
            tier: .read
        ) { args in try facade.getMap(args) })

        catalog.register(MCPTool(
            name: "get_topic",
            title: "Read topic",
            description: "Everything about one topic: its path from the central topic, parent and position, children, note, link, labels, markers, style overrides, attachments and relationships.",
            inputSchema: MCPSchema.object([
                "map_id": mapID,
                "topic_id": MCPSchema.string("Topic id"),
            ], required: ["topic_id"]),
            tier: .read
        ) { args in try facade.getTopic(args) })

        catalog.register(MCPTool(
            name: "search_topics",
            title: "Search topics",
            description: "Find topics whose title, labels or note contain the text (ignoring case and accents). Returns ids with their path from the central topic.",
            inputSchema: MCPSchema.object([
                "map_id": mapID,
                "query": MCPSchema.string("Text to look for"),
                "in_notes": MCPSchema.boolean("Also search notes (default true)"),
                "limit": MCPSchema.integer("Maximum results (default 50)", min: 1, max: 500),
            ], required: ["query"]),
            tier: .read
        ) { args in try facade.search(args) })

        catalog.register(MCPTool(
            name: "get_selection",
            title: "Get selection",
            description: "The topics (or relationship) the user has selected in a map. Use it when the user says \"this topic\" or \"the selected branch\".",
            inputSchema: MCPSchema.object(["map_id": mapID]),
            tier: .read
        ) { args in try facade.selection(args) })

        catalog.register(MCPTool(
            name: "render_map",
            title: "Render map as image",
            description: "Draw the map as a PNG image, exactly as FreeMind shows it (collapsed branches are hidden). Use it to check the layout and colors.",
            inputSchema: MCPSchema.object([
                "map_id": mapID,
                "scale": MCPSchema.number("Scale factor, 0.25–2 (default 1). Large maps are scaled down to at most 2400 pixels."),
            ]),
            tier: .read
        ) { args in try facade.render(args) })
    }

    // MARK: - 主题

    private static func registerTopicTools(catalog: MCPCatalog, facade: MCPFacade) {
        catalog.register(MCPTool(
            name: "add_topics",
            title: "Add topics",
            description: "Add one or more topics, with any number of nested subtopics, under a parent topic in a single undo step. Give the topics as 'topics' (objects with title, note, link, labels, markers, style and children) or as a 'markdown' outline (headings and nested lists; text under an item becomes its note). Returns the new ids.",
            inputSchema: MCPSchema.object([
                "map_id": mapID,
                "parent_id": MCPSchema.string("Parent topic id. Default: \"root\" (the central topic)"),
                "index": MCPSchema.integer("Position among the parent's subtopics, 0-based. Default: after the last one", min: 0),
                "topics": MCPSchema.array(topicSpec, "Topics to add"),
                "markdown": MCPSchema.string("Alternative to 'topics': a Markdown outline such as \"- Idea\\n  - Detail\""),
            ]),
            tier: .write
        ) { args in try facade.addTopics(args) })

        catalog.register(MCPTool(
            name: "update_topics",
            title: "Edit topics",
            description: "Change one or more topics in a single undo step. Only the fields you pass change. Pass null to clear a field (note, link, labels, markers, or a style property, which then follows the map's theme again).",
            inputSchema: MCPSchema.object([
                "map_id": mapID,
                "updates": MCPSchema.array(MCPSchema.object([
                    "topic_id": MCPSchema.string("Topic id"),
                    "title": MCPSchema.string("New topic text"),
                    "note": MCPSchema.nullable(MCPSchema.string("New note; replaces the whole note")),
                    "link": MCPSchema.nullable(MCPSchema.string("Hyperlink URL")),
                    "labels": MCPSchema.nullable(MCPSchema.array(MCPSchema.string("Label"), "Replaces all labels")),
                    "markers": MCPSchema.nullable(MCPSchema.array(MCPSchema.string("Marker id"), "Replaces all markers")),
                    "add_markers": MCPSchema.array(MCPSchema.string("Marker id"),
                                                   "Markers to add; a marker replaces any marker of the same kind (one priority, one progress, one flag, one star)"),
                    "remove_markers": MCPSchema.array(MCPSchema.string("Marker id"), "Markers to remove"),
                    "style": style,
                    "reset_style": MCPSchema.boolean("Remove all style overrides first"),
                ], required: ["topic_id"]), "One entry per topic"),
            ], required: ["updates"]),
            tier: .write
        ) { args in try facade.updateTopics(args) })

        catalog.register(MCPTool(
            name: "move_topics",
            title: "Move topics",
            description: "Move topics (with their subtopics) under another parent, or reorder them under the same parent.",
            inputSchema: MCPSchema.object([
                "map_id": mapID,
                "topic_ids": topicIDs,
                "parent_id": MCPSchema.string("New parent topic id (\"root\" for the central topic)"),
                "index": MCPSchema.integer("Position among the new parent's subtopics, 0-based, counted before the move. Default: at the end", min: 0),
            ], required: ["topic_ids", "parent_id"]),
            tier: .write
        ) { args in try facade.moveTopics(args) })

        catalog.register(MCPTool(
            name: "delete_topics",
            title: "Delete topics",
            description: "Delete topics together with their subtopics, or with keep_children only the topics themselves (their subtopics move up one level). The central topic cannot be deleted. The user can undo it.",
            inputSchema: MCPSchema.object([
                "map_id": mapID,
                "topic_ids": topicIDs,
                "keep_children": MCPSchema.boolean("Keep the subtopics by moving them up one level (default false)"),
            ], required: ["topic_ids"]),
            tier: .delete
        ) { args in try facade.deleteTopics(args) })

        catalog.register(MCPTool(
            name: "fold_topics",
            title: "Collapse or expand",
            description: "Collapse or expand branches: \"collapse\" / \"expand\" the given topics, \"expand_all\", \"collapse_all\" (only main topics stay visible), or \"show_levels\" to show the given number of levels below the central topic.",
            inputSchema: MCPSchema.object([
                "map_id": mapID,
                "action": MCPSchema.enumeration(["collapse", "expand", "expand_all", "collapse_all", "show_levels"], "What to do"),
                "topic_ids": topicIDs,
                "level": MCPSchema.integer("For show_levels: how many levels to show", min: 1),
            ], required: ["action"]),
            tier: .write
        ) { args in try facade.foldTopics(args) })

        catalog.register(MCPTool(
            name: "select_topics",
            title: "Select topics",
            description: "Select topics in the map window and scroll to them, expanding collapsed branches if needed, to point the user at something. Does not change the content.",
            inputSchema: MCPSchema.object([
                "map_id": mapID,
                "topic_ids": topicIDs,
            ], required: ["topic_ids"]),
            tier: .navigate
        ) { args in try facade.selectTopics(args) })

        catalog.register(MCPTool(
            name: "add_relationship",
            title: "Add relationship",
            description: "Connect two topics anywhere in the map with a curved arrow, optionally with a label.",
            inputSchema: MCPSchema.object([
                "map_id": mapID,
                "from_id": MCPSchema.string("Topic id where the arrow starts"),
                "to_id": MCPSchema.string("Topic id the arrow points to"),
                "title": MCPSchema.string("Label shown on the arrow"),
            ], required: ["from_id", "to_id"]),
            tier: .write
        ) { args in try facade.addRelationship(args) })

        catalog.register(MCPTool(
            name: "update_relationship",
            title: "Edit relationship",
            description: "Change a relationship's label, line or arrows. Relationship ids are listed at the end of get_map.",
            inputSchema: MCPSchema.object([
                "map_id": mapID,
                "relationship_id": MCPSchema.string("Relationship id"),
                "title": MCPSchema.string("Label (empty string removes it)"),
                "dashed": MCPSchema.boolean("Dashed line"),
                "arrow_start": MCPSchema.boolean("Arrow head at the start"),
                "arrow_end": MCPSchema.boolean("Arrow head at the end"),
                "color": MCPSchema.nullable(MCPSchema.string("Line color #RRGGBB; null follows the theme")),
            ], required: ["relationship_id"]),
            tier: .write
        ) { args in try facade.updateRelationship(args) })

        catalog.register(MCPTool(
            name: "delete_relationship",
            title: "Delete relationship",
            description: "Remove a relationship arrow. The topics stay.",
            inputSchema: MCPSchema.object([
                "map_id": mapID,
                "relationship_id": MCPSchema.string("Relationship id"),
            ], required: ["relationship_id"]),
            tier: .delete
        ) { args in try facade.deleteRelationship(args) })
    }

    // MARK: - 整张导图 / 文档

    private static func registerMapTools(catalog: MCPCatalog, facade: MCPFacade) {
        let themes = Theme.builtins.map(\.id).joined(separator: ", ")
        let structures = MCPSchema.enumeration(MapStructure.allCases.map(\.rawValue),
                                               "Layout: mindmap (branches on both sides), logic-right, logic-left, org-down (org chart), tree")

        catalog.register(MCPTool(
            name: "set_map_format",
            title: "Change map format",
            description: "Change the whole map's layout structure, theme, spacing, line style or topic width.",
            inputSchema: MCPSchema.object([
                "map_id": mapID,
                "structure": structures,
                "theme": MCPSchema.string("Theme id (\(themes)) or the name of one of the user's custom themes"),
                "spacing": MCPSchema.enumeration(MapSpacing.allCases.map(\.rawValue), "Space between topics"),
                "line_style": MCPSchema.enumeration(LineStyle.allCases.map(\.rawValue) + ["theme"],
                                                    "Branch line style; \"theme\" follows the theme"),
                "topic_max_width": MCPSchema.number("Maximum topic width in points before text wraps (120–600)"),
            ]),
            tier: .write
        ) { args in try facade.setMapFormat(args) })

        catalog.register(MCPTool(
            name: "create_map",
            title: "Create map",
            description: "Open a new map window. 'title' becomes the central topic; 'topics' or a 'markdown' outline become its subtopics (without a title, a Markdown outline with a single top-level item becomes the central topic). The map is not saved to a file until save_map.",
            inputSchema: MCPSchema.object([
                "title": MCPSchema.string("Central topic text"),
                "topics": MCPSchema.array(topicSpec, "Main topics with nested subtopics"),
                "markdown": MCPSchema.string("Markdown outline for the content"),
                "structure": structures,
                "theme": MCPSchema.string("Theme id (\(themes)). Default: the user's default theme"),
            ]),
            tier: .write
        ) { args in try facade.createMap(args) })

        catalog.register(MCPTool(
            name: "open_map",
            title: "Open map",
            description: "Open a .fmind map in a FreeMind window, or import a Markdown, OPML, XMind or text file as a new unsaved map.",
            inputSchema: MCPSchema.object([
                "path": MCPSchema.string("Absolute file path (~ is allowed)"),
            ], required: ["path"]),
            tier: .navigate
        ) { args in try await facade.openMap(args) })

        catalog.register(MCPTool(
            name: "save_map",
            title: "Save map",
            description: "Save a map. Maps that already have a file are also saved automatically; a new map needs 'path' the first time. Existing files are never overwritten.",
            inputSchema: MCPSchema.object([
                "map_id": mapID,
                "path": MCPSchema.string("Where to save, such as ~/Documents/Plan.fmind (.fmind is added if missing)"),
            ]),
            tier: .write
        ) { args in try await facade.saveMap(args) })
    }
}
