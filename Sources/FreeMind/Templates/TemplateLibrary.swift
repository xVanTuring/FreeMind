import AppKit

/// 模板内容的双语文本：按应用当前使用的语言挑选（模板正文量大，不放进 Localizable.strings）。
func LT(_ en: String, _ zh: String) -> String {
    Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? zh : en
}

struct MapTemplate: Identifiable {
    enum Kind { case blank, builtin, user }

    let id: String
    let name: String
    let summary: String
    let kind: Kind
    /// 内置模板：生成导图；用户模板：包文件位置。
    let make: (() -> MindMap)?
    let url: URL?
}

/// 模板库：空白结构、内置内容模板、用户自存模板（`~/Library/Application Support/FreeMind/Templates/*.fmind`）。
final class TemplateLibrary {
    static let shared = TemplateLibrary()

    // MARK: 空白

    func blankTemplates() -> [MapTemplate] {
        MapStructure.allCases.map { s in
            MapTemplate(id: "blank-\(s.rawValue)", name: s.title, summary: L("Blank map"), kind: .blank, make: {
                var map = MindMap.blank(structure: s, theme: Preferences.shared.defaultTheme)
                map.spacing = Preferences.shared.defaultSpacing
                return map
            }, url: nil)
        }
    }

    // MARK: 用户模板

    func userTemplates() -> [MapTemplate] {
        let dir = AppDirectories.templates
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension == DocumentTypes.fileExtension }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                MapTemplate(id: "user-" + url.lastPathComponent, name: url.deletingPathExtension().lastPathComponent,
                            summary: L("My template"), kind: .user, make: nil, url: url)
            }
    }

    func saveTemplate(from document: MindMapDocument, name: String) throws {
        let wrapper = try document.packageSnapshot()
        var url = AppDirectories.templates.appendingPathComponent(AttachmentStore.sanitize(name))
            .appendingPathExtension(DocumentTypes.fileExtension)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = AppDirectories.templates.appendingPathComponent("\(AttachmentStore.sanitize(name)) \(n)")
                .appendingPathExtension(DocumentTypes.fileExtension)
            n += 1
        }
        try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
    }

    func deleteUserTemplate(_ template: MapTemplate) throws {
        guard let url = template.url else { return }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// 读取模板内容（含资源文件）。
    func load(_ template: MapTemplate) throws -> (map: MindMap, resources: [UUID: ResourceFile]) {
        if let make = template.make { return (make(), [:]) }
        guard let url = template.url else { throw CocoaError(.fileReadNoSuchFile) }
        let wrapper = try FileWrapper(url: url, options: .immediate)
        guard let data = wrapper.fileWrappers?[DocumentContent.contentFileName]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var map = try DocumentContent.decode(data).map
        var resources: [UUID: ResourceFile] = [:]
        for (name, entry) in wrapper.fileWrappers?[AttachmentStore.directoryName]?.fileWrappers ?? [:] {
            guard let id = UUID(uuidString: name), let file = entry.fileWrappers?.values.first,
                  let contents = file.regularFileContents else { continue }
            resources[id] = ResourceFile(name: file.preferredFilename ?? file.filename ?? "file", data: contents)
        }
        // 模板里的主题 id 换新，避免多次使用同一模板时 id 重复（资源 id 保持不变即可）。
        map = map.withFreshTopicIDs()
        return (map, resources)
    }

    // MARK: 内置内容模板

    func builtinTemplates() -> [MapTemplate] {
        [
            MapTemplate(id: "getting-started", name: LT("Getting Started", "快速上手"),
                        summary: LT("Learn FreeMind in two minutes", "两分钟学会 FreeMind"), kind: .builtin,
                        make: BuiltinTemplates.gettingStarted, url: nil),
            MapTemplate(id: "project-plan", name: LT("Project Plan", "项目计划"),
                        summary: LT("Goals, milestones, team and risks", "目标、里程碑、分工与风险"), kind: .builtin,
                        make: BuiltinTemplates.projectPlan, url: nil),
            MapTemplate(id: "meeting", name: LT("Meeting Notes", "会议记录"),
                        summary: LT("Agenda, decisions and action items", "议程、决议与待办"), kind: .builtin,
                        make: BuiltinTemplates.meetingNotes, url: nil),
            MapTemplate(id: "swot", name: LT("SWOT Analysis", "SWOT 分析"),
                        summary: LT("Strengths, weaknesses, opportunities, threats", "优势、劣势、机会、威胁"), kind: .builtin,
                        make: BuiltinTemplates.swot, url: nil),
            MapTemplate(id: "weekly", name: LT("Weekly Plan", "周计划"),
                        summary: LT("Plan your week day by day", "按天安排一周"), kind: .builtin,
                        make: BuiltinTemplates.weeklyPlan, url: nil),
            MapTemplate(id: "book", name: LT("Book Notes", "读书笔记"),
                        summary: LT("Key ideas, quotes and reflections", "核心观点、摘抄与思考"), kind: .builtin,
                        make: BuiltinTemplates.bookNotes, url: nil),
            MapTemplate(id: "brainstorm", name: LT("Brainstorm", "头脑风暴"),
                        summary: LT("Collect, group and pick ideas", "发散、归类、筛选想法"), kind: .builtin,
                        make: BuiltinTemplates.brainstorm, url: nil),
            MapTemplate(id: "decision", name: LT("Decision Making", "决策分析"),
                        summary: LT("Compare options with pros and cons", "对比各方案的利弊"), kind: .builtin,
                        make: BuiltinTemplates.decision, url: nil),
            MapTemplate(id: "org", name: LT("Organization Chart", "组织架构"),
                        summary: LT("Teams and reporting lines", "团队与汇报关系"), kind: .builtin,
                        make: BuiltinTemplates.orgChart, url: nil),
        ]
    }
}
