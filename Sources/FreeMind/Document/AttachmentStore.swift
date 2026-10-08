import AppKit

/// 文档里的附件 / 图片文件。
///
/// 包内布局：`attachments/<uuid>/<原始文件名>`。保留原文件名，用户“显示包内容”时也能看懂。
/// 内存里按 id 持有 FileWrapper；从磁盘读出的 FileWrapper 是惰性读取的，
/// 保存时 NSDocument 会对没变的文件做硬链接，不会每次自动保存都重写大附件。
final class AttachmentStore {
    static let directoryName = "attachments"

    private var files: [UUID: FileWrapper] = [:]
    private var imageCache: [UUID: NSImage] = [:]
    /// 文档当前位置，惰性读取失败时（例如文档被移动过）从这里兜底读取。
    var packageURL: URL?

    var ids: Set<UUID> { Set(files.keys) }

    func contains(_ id: UUID) -> Bool { files[id] != nil }

    // MARK: 读取

    func load(from directory: FileWrapper?) {
        files.removeAll()
        imageCache.removeAll()
        guard let children = directory?.fileWrappers else { return }
        for (name, child) in children {
            guard let id = UUID(uuidString: name), child.isDirectory, let file = Self.payload(of: child) else { continue }
            files[id] = file
        }
    }

    /// `attachments/<id>/` 里真正的附件文件：忽略 .DS_Store、._xxx 这类隐藏文件。
    private static func payload(of entry: FileWrapper) -> FileWrapper? {
        let candidates = (entry.fileWrappers ?? [:])
            .filter { !$0.key.hasPrefix(".") && $0.value.isRegularFile }
            .sorted { $0.key < $1.key }
        return candidates.first?.value
    }

    func fileName(for id: UUID) -> String? {
        guard let wrapper = files[id] else { return nil }
        return wrapper.preferredFilename ?? wrapper.filename
    }

    func data(for id: UUID) -> Data? {
        guard let wrapper = files[id] else { return nil }
        if let data = wrapper.regularFileContents { return data }
        // 兜底：直接从包里读
        if let packageURL, let name = fileName(for: id) {
            let url = packageURL.appendingPathComponent(Self.directoryName)
                .appendingPathComponent(id.uuidString).appendingPathComponent(name)
            return try? Data(contentsOf: url)
        }
        return nil
    }

    func image(for id: UUID) -> NSImage? {
        if let cached = imageCache[id] { return cached }
        guard let data = data(for: id), let image = NSImage(data: data) else { return nil }
        imageCache[id] = image
        return image
    }

    // MARK: 添加

    static func sanitize(_ name: String) -> String {
        var s = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s == "." || s == ".." { s = "file" }
        return s
    }

    /// 复制一个外部文件进来，返回附件描述。
    func add(fileAt url: URL) throws -> Attachment {
        let data = try Data(contentsOf: url)
        let id = add(data: data, name: url.lastPathComponent)
        return Attachment(id: id, name: Self.sanitize(url.lastPathComponent), size: Int64(data.count))
    }

    @discardableResult
    func add(data: Data, name: String, id: UUID = UUID()) -> UUID {
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = Self.sanitize(name)
        files[id] = wrapper
        imageCache[id] = nil
        return id
    }

    /// 从另一个文档复制资源（跨文档粘贴、模板实例化时用）。
    func adopt(_ ids: Set<UUID>, from other: AttachmentStore) {
        for id in ids where files[id] == nil {
            if let data = other.data(for: id), let name = other.fileName(for: id) {
                add(data: data, name: name, id: id)
            }
        }
    }

    // MARK: 保存

    /// 把被引用的资源同步进 `attachments` 目录。
    /// 未被引用的资源从包里移除，但先把内容读进内存（撤销后还能找回）；读不到内容的不移除，宁可多留一个文件。
    func sync(into root: FileWrapper, referenced: Set<UUID>) {
        var directory = root.fileWrappers?[Self.directoryName]
        if directory?.isDirectory == false, let bad = directory {
            root.removeFileWrapper(bad)
            directory = nil
        }
        if directory == nil {
            guard !referenced.isEmpty else { return }
            let d = FileWrapper(directoryWithFileWrappers: [:])
            d.preferredFilename = Self.directoryName
            root.addFileWrapper(d)
            directory = d
        }
        guard let directory else { return }

        let existing = directory.fileWrappers ?? [:]
        for (name, child) in existing {
            guard let id = UUID(uuidString: name) else { continue }   // 不认识的条目原样保留
            if !referenced.contains(id) {
                if detachFromDisk(id) { directory.removeFileWrapper(child) }
                continue
            }
            // 资源被替换过（同 id 新文件）时重建
            if let file = files[id], !(child.fileWrappers ?? [:]).values.contains(where: { $0 === file }) {
                directory.removeFileWrapper(child)
                directory.addFileWrapper(makeEntry(id: id, file: file))
            }
        }
        for id in referenced where existing[id.uuidString] == nil {
            guard let file = files[id] else { continue }
            directory.addFileWrapper(makeEntry(id: id, file: file))
        }
        if directory.fileWrappers?.isEmpty ?? true { root.removeFileWrapper(directory) }
    }

    private func makeEntry(id: UUID, file: FileWrapper) -> FileWrapper {
        let name = file.preferredFilename ?? file.filename ?? "file"
        let entry = FileWrapper(directoryWithFileWrappers: [name: file])
        entry.preferredFilename = id.uuidString
        return entry
    }

    /// 文件即将从包里移除：把内容读进内存，换成纯内存的 FileWrapper，彻底和磁盘文件脱钩。
    /// 返回 false 表示读不到内容（不能移除，否则撤销后就找不回来了）。
    private func detachFromDisk(_ id: UUID) -> Bool {
        guard files[id] != nil else { return true }   // 内存里本来就没有（例如外部放进来的），可以移除
        guard let data = data(for: id) else { return false }
        let copy = FileWrapper(regularFileWithContents: data)
        copy.preferredFilename = fileName(for: id)
        files[id] = copy
        return true
    }

    // MARK: 打开

    /// 把附件写到临时目录，供“打开 / 快速查看”使用。
    /// 每次都重新写出并设为只读：外部程序的修改不会写回导图，只读能提醒用户这一点，
    /// 也避免下次打开时看到改过的临时副本、误以为已经保存进导图。
    func temporaryURL(for id: UUID) throws -> URL {
        guard let name = fileName(for: id), let data = data(for: id) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("FreeMind-Attachments", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        if fm.fileExists(atPath: url.path) {
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try fm.removeItem(at: url)
        }
        try data.write(to: url)
        try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        return url
    }
}
