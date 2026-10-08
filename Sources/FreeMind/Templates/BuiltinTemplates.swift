import Foundation

/// 内置模板内容。
enum BuiltinTemplates {
    /// 小工具：双语主题。
    private static func t(_ en: String, _ zh: String, _ children: [Topic] = [], note: (String, String)? = nil,
                          markers: [String] = [], labels: [(String, String)] = [], collapsed: Bool = false) -> Topic {
        var topic = Topic(title: LT(en, zh), children: children)
        if let note { topic.note = LT(note.0, note.1) }
        topic.markers = markers.map(MarkerID.init(rawValue:)).sorted()
        topic.labels = labels.map { LT($0.0, $0.1) }
        topic.collapsed = collapsed
        return topic
    }

    static func gettingStarted() -> MindMap {
        let root = t("Welcome to FreeMind", "欢迎使用 FreeMind", [
            t("Add topics", "添加主题", [
                t("Tab: add a subtopic", "Tab：添加子主题", markers: ["priority-1"]),
                t("Return: add a sibling topic", "Return：添加同级主题", markers: ["priority-2"]),
                t("⇧Return: add a topic before", "⇧Return：在前面插入主题"),
                t("⌘Return: add a parent topic", "⌘Return：插入父主题"),
                t("Click the + next to a selected topic", "点选中主题旁边的 + 按钮"),
            ], note: ("Select a topic first, then use these keys. New topics start in edit mode, so just type.",
                      "先选中一个主题，再按这些键。新主题会直接进入编辑状态，接着打字就行。")),
            t("Edit text", "编辑文字", [
                t("Space or double-click to edit", "空格或双击进入编辑"),
                t("Or simply start typing", "选中后直接打字也可以"),
                t("Return to finish, ⇧Return for a new line", "Return 完成，⇧Return 换行"),
                t("Esc to cancel", "Esc 放弃修改"),
            ]),
            t("Organize", "整理结构", [
                t("Drag a topic onto another topic", "把主题拖到另一个主题上"),
                t("⌥↑ / ⌥↓ to reorder", "⌥↑ / ⌥↓ 调整顺序"),
                t("⌥← / ⌥→ to promote or demote", "⌥← / ⌥→ 升级或降级"),
                t("⌘/ to collapse or expand a branch", "⌘/ 折叠或展开分支", [
                    t("Collapsed state is saved with the file", "折叠状态会随文件保存"),
                ], collapsed: true),
                t("Arrow keys move the selection", "方向键移动选中项"),
            ]),
            t("Add details", "丰富内容", [
                t("⌥⌘N note", "⌥⌘N 备注", note: ("Notes can hold longer text. Click the note icon on a topic to read it.",
                                                   "备注可以写长文字。点主题上的备注图标就能查看。")),
                t("⌘K hyperlink", "⌘K 超链接"),
                t("⌥⌘A attachment, or drop files on a topic", "⌥⌘A 附件，或直接把文件拖到主题上",
                  note: ("Attachments are copied into the .fmind file, so the map stays complete when you move or share it.",
                         "附件会复制进 .fmind 文件里，移动或分享导图时附件不会丢。")),
                t("⇧⌘I image", "⇧⌘I 图片"),
                t("⌘1 – ⌘6 priority", "⌘1 – ⌘6 优先级", markers: ["priority-3"]),
                t("Markers and labels", "标记和标签", markers: ["task-50", "star-yellow"], labels: [("tip", "提示")]),
                t("⌘L connects two topics", "⌘L 用联系线连接两个主题"),
            ]),
            t("Look & feel", "外观", [
                t("⌥⌘I shows the format panel", "⌥⌘I 打开右侧格式面板"),
                t("Structure: mind map, logic, org, tree", "结构：思维导图、逻辑图、组织结构图、树状图"),
                t("Themes change the whole map", "主题一键改变整张图的配色"),
                t("⌘+ / ⌘- / ⌘0 / ⌘9 zoom", "⌘+ / ⌘- / ⌘0 / ⌘9 缩放"),
            ]),
            t("Files", "文件", [
                t("Saved as a .fmind package", "保存为 .fmind 包格式"),
                t("Import Markdown, OPML and XMind", "导入 Markdown、OPML、XMind"),
                t("Export Markdown, OPML, PNG and PDF", "导出 Markdown、OPML、PNG、PDF"),
                t("File ▸ Save as Template", "文件 ▸ 存为模板"),
            ]),
        ], note: ("This map is a quick tour. Try the shortcuts right here — you can always open it again from Help ▸ Getting Started.",
                  "这张导图就是一份快速指南，可以直接在上面试试各种操作。以后也能从“帮助 ▸ 快速上手”再次打开。"))
        var map = MindMap(root: root, structure: .mindMap, theme: .classic)
        // 演示联系线：从“添加主题”指向“文件”
        map.relationships = [Relationship(from: root.children[0].id, to: root.children[5].id,
                                          title: LT("then save", "最后保存"))]
        return map
    }

    static func projectPlan() -> MindMap {
        let root = t("Project Plan", "项目计划", [
            t("Goals", "目标", [
                t("Business goal", "业务目标"),
                t("Success metrics", "衡量指标"),
            ]),
            t("Scope", "范围", [
                t("In scope", "包含"),
                t("Out of scope", "不包含"),
            ]),
            t("Milestones", "里程碑", [
                t("Kick-off", "启动", markers: ["task-100"]),
                t("Design", "设计", markers: ["task-50"]),
                t("Build", "开发", markers: ["task-0"]),
                t("Launch", "上线", markers: ["task-0", "flag-red"]),
            ]),
            t("Team", "团队", [
                t("Owner", "负责人", markers: ["symbol-person"]),
                t("Members", "成员"),
            ]),
            t("Risks", "风险", [
                t("Risk 1", "风险 1", markers: ["priority-1"]),
                t("Mitigation", "应对措施"),
            ]),
            t("Resources", "资源", [
                t("Budget", "预算", markers: ["symbol-money"]),
                t("Tools", "工具"),
            ]),
        ])
        return MindMap(root: root, structure: .logicRight, theme: .fresh)
    }

    static func meetingNotes() -> MindMap {
        let root = t("Meeting Notes", "会议记录", [
            t("Info", "基本信息", [
                t("Date & time", "时间", markers: ["symbol-time"]),
                t("Attendees", "参会人", markers: ["symbol-person"]),
                t("Goal of the meeting", "会议目的"),
            ]),
            t("Agenda", "议程", [
                t("Topic 1", "议题 1"),
                t("Topic 2", "议题 2"),
                t("Topic 3", "议题 3"),
            ]),
            t("Discussion", "讨论要点", [
                t("Key point", "要点"),
                t("Open question", "待确认问题", markers: ["symbol-question"]),
            ]),
            t("Decisions", "决议", [
                t("Decision 1", "决议 1", markers: ["symbol-check"]),
            ]),
            t("Action items", "待办事项", [
                t("Task — owner — due date", "任务 — 负责人 — 截止日期", markers: ["task-0"]),
                t("Task — owner — due date", "任务 — 负责人 — 截止日期", markers: ["task-0"]),
            ]),
        ])
        return MindMap(root: root, structure: .mindMap, theme: .ocean)
    }

    static func swot() -> MindMap {
        var strengths = t("Strengths", "优势", [t("Internal advantage", "内部优势"), t("Unique resource", "独特资源")])
        strengths.style.branchColor = "#30A46C"
        var weaknesses = t("Weaknesses", "劣势", [t("Internal limitation", "内部不足"), t("Missing capability", "能力短板")])
        weaknesses.style.branchColor = "#F76B15"
        var opportunities = t("Opportunities", "机会", [t("Market trend", "市场趋势"), t("New demand", "新需求")])
        opportunities.style.branchColor = "#0090FF"
        var threats = t("Threats", "威胁", [t("Competitor", "竞争对手"), t("External risk", "外部风险")])
        threats.style.branchColor = "#E5484D"
        let root = t("SWOT Analysis", "SWOT 分析", [strengths, weaknesses, threats, opportunities])
        return MindMap(root: root, structure: .mindMap, theme: .rainbow)
    }

    static func weeklyPlan() -> MindMap {
        let days: [(String, String)] = [("Monday", "周一"), ("Tuesday", "周二"), ("Wednesday", "周三"), ("Thursday", "周四"),
                                        ("Friday", "周五"), ("Weekend", "周末")]
        let root = t("This Week", "本周计划", [
            t("Focus", "本周重点", [t("Most important outcome", "最重要的成果", markers: ["star-yellow"])]),
        ] + days.map { day in
            t(day.0, day.1, [t("Task", "任务", markers: ["task-0"])])
        } + [
            t("Review", "复盘", [t("What went well", "做得好的"), t("What to improve", "可以改进的")]),
        ])
        return MindMap(root: root, structure: .logicRight, theme: .candy)
    }

    static func bookNotes() -> MindMap {
        let root = t("Book Title", "书名", [
            t("About the book", "书籍信息", [
                t("Author", "作者"), t("Why I read it", "为什么读"),
            ]),
            t("Key ideas", "核心观点", [
                t("Idea 1", "观点 1", markers: ["symbol-idea"]),
                t("Idea 2", "观点 2", markers: ["symbol-idea"]),
                t("Idea 3", "观点 3", markers: ["symbol-idea"]),
            ]),
            t("Quotes", "精彩摘抄", [
                t("Quote", "摘抄", note: ("Page number and context", "页码和上下文")),
            ]),
            t("My thoughts", "我的思考", [
                t("Agree", "认同", markers: ["symbol-like"]),
                t("Question", "疑问", markers: ["symbol-question"]),
            ]),
            t("Apply", "行动", [
                t("Something to try", "想尝试的事", markers: ["task-0"]),
            ]),
        ])
        return MindMap(root: root, structure: .mindMap, theme: .paper)
    }

    static func brainstorm() -> MindMap {
        let root = t("Problem to solve", "要解决的问题", [
            t("Ideas", "想法", [
                t("Idea", "想法"), t("Idea", "想法"), t("Crazy idea", "大胆的想法", markers: ["symbol-idea"]),
            ]),
            t("Constraints", "限制条件", [
                t("Time", "时间", markers: ["symbol-time"]), t("Budget", "预算", markers: ["symbol-money"]),
            ]),
            t("Evaluate", "评估", [
                t("Impact", "影响"), t("Effort", "投入"),
            ]),
            t("Next steps", "下一步", [
                t("Prototype", "做原型", markers: ["priority-1"]),
            ]),
        ])
        return MindMap(root: root, structure: .mindMap, theme: .sunset)
    }

    static func decision() -> MindMap {
        func option(_ en: String, _ zh: String) -> Topic {
            t(en, zh, [
                t("Pros", "优点", [t("Pro", "优点", markers: ["symbol-like"])]),
                t("Cons", "缺点", [t("Con", "缺点", markers: ["symbol-dislike"])]),
                t("Cost", "成本", markers: ["symbol-money"]),
            ])
        }
        let root = t("Decision", "决策", [
            t("Context", "背景", [t("Why decide now", "为什么现在要决定")]),
            option("Option A", "方案 A"),
            option("Option B", "方案 B"),
            option("Option C", "方案 C"),
            t("Decision & reason", "结论与理由", markers: ["flag-green"]),
        ])
        return MindMap(root: root, structure: .logicRight, theme: .business)
    }

    static func orgChart() -> MindMap {
        let root = t("CEO", "总经理", [
            t("Product", "产品部", [t("Design", "设计组"), t("Research", "用户研究")]),
            t("Engineering", "技术部", [t("Frontend", "前端组"), t("Backend", "后端组"), t("QA", "测试组")]),
            t("Marketing", "市场部", [t("Brand", "品牌"), t("Growth", "增长")]),
            t("Operations", "运营部", [t("Support", "客服"), t("Finance", "财务")]),
        ])
        return MindMap(root: root, structure: .orgChart, theme: .business)
    }
}
