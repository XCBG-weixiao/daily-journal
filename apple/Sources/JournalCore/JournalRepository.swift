import Foundation
import ImageIO
import Darwin

public actor JournalRepository {
    public let directory: URL
    public init(directory: URL) { self.directory = directory.standardizedFileURL }

    public func initialize() throws {
        try coordinate(directory, writing: true) { root in
            let files = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0 != ".DS_Store" }
            guard files.isEmpty else { throw JournalError("新建日记库需要一个空文件夹。已有日记库请使用“打开日记库”。") }
            for folder in ["entries", "activities", "assets"] {
                try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: false)
            }
            try Data("{\"schema_version\":1,\"timezone\":\"Asia/Shanghai\",\"week_starts_on\":1}\n".utf8)
                .write(to: root.appendingPathComponent("settings.json"), options: .atomic)
            for activity in Activity.defaults {
                let value = Activity(id: activity.id, name: activity.name, icon: activity.icon, color: activity.color,
                                     metrics: activity.metrics, body: "记录每一次\(activity.name)。\n")
                try Data(MarkdownCodec.encode(value).utf8).write(to: root.appendingPathComponent("activities/\(value.id).md"), options: .atomic)
            }
        }
    }

    public func snapshot(now: Date = Date()) throws -> JournalSnapshot {
        let settings = try existing("settings.json")
        try local(settings)
        try resolveVersions(settings)
        try MarkdownCodec.validateSettings(read(settings))
        var result = JournalSnapshot()
        for area in ["activities", "entries"] {
            let folder = try existing(area)
            try local(folder)
            let names = try coordinate(folder, writing: false) { try FileManager.default.contentsOfDirectory(atPath: $0.path).filter { $0.hasSuffix(".md") || $0.hasPrefix(".") && $0.hasSuffix(".md.icloud") }.sorted() }
            var ids = Set<String>()
            for name in names {
                let relative = "\(area)/\(name)"
                do {
                    if name.hasSuffix(".icloud") { throw JournalError("iCloud 文件尚未下载，当前数据不完整。请在 Finder 中下载日记库后刷新。") }
                    let url = try existing(relative)
                    try local(url)
                    try resolveVersions(url)
                    let bytes = try read(url)
                    guard let text = String(data: bytes, encoding: .utf8) else { throw JournalError("文件不是有效的 UTF-8 文本") }
                    if area == "activities" {
                        let activity = try MarkdownCodec.activity(text)
                        guard ids.insert(activity.id).inserted else { throw JournalError("重复活动 ID") }
                        guard name == activity.id + ".md" else { throw JournalError("文件名必须与 id 一致") }
                        result.activities.append(activity)
                    } else {
                        let entry = try MarkdownCodec.entry(text, activities: result.activities, now: now)
                        guard ids.insert(entry.id).inserted else { throw JournalError("重复记录 ID") }
                        guard name == entry.id + ".md" else { throw JournalError("文件名必须与 id 一致") }
                        result.entries.append(entry)
                    }
                } catch { result.issues.append(ContentIssue(file: relative, message: error.localizedDescription)) }
            }
        }
        return result
    }

    public func save(_ input: Entry, now: Date = Date()) throws -> Entry {
        let data = try snapshot(now: now)
        var entry = try MarkdownCodec.validated(input, activities: data.activities, now: now)
        let folder = try existing("entries"), file = folder.appendingPathComponent(entry.id + ".md")
        let text = try MarkdownCodec.encode(entry)
        try coordinate(folder, writing: true) { _ in
            try assertWithin(file, parent: folder)
            let exists = FileManager.default.fileExists(atPath: file.path)
            if exists {
                try local(file)
                let old = try String(contentsOf: file, encoding: .utf8)
                guard entry.hash != nil, MarkdownCodec.hash(old) == entry.hash else { throw JournalError("文件已被修改或已存在。当前草稿已保留；请复制正文，关闭编辑器并重新打开记录后合并。") }
            } else if entry.hash != nil { throw JournalError("原文件已被移动或删除。当前草稿已保留，请先确认原文件。") }
            try atomicWrite(Data(text.utf8), to: file, replacing: exists)
        }
        entry.hash = MarkdownCodec.hash(text)
        return entry
    }

    public func importImage(_ bytes: Data, entryID: String) throws -> String {
        guard validUUID(entryID) else { throw JournalError("记录 ID 无效") }
        let ext = try Self.validateImage(bytes)
        let assets = try existing("assets")
        return try coordinate(assets, writing: true) { base in
            let folder = base.appendingPathComponent(entryID)
            try assertWithin(folder, parent: base)
            if !FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            }
            let name = UUID().uuidString.lowercased() + "." + ext
            let file = folder.appendingPathComponent(name)
            try assertWithin(file, parent: base)
            try atomicWrite(bytes, to: file, replacing: false)
            return "../assets/\(entryID)/\(name)"
        }
    }

    public func imageData(_ reference: String) throws -> Data {
        guard matches(reference, "^\\.\\./assets/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/[a-zA-Z0-9._-]+$") else { throw JournalError("图片路径无效：\(reference)") }
        let components = reference.split(separator: "/")
        guard validUUID(String(components[2])) else { throw JournalError("图片记录 ID 无效") }
        let assets = try existing("assets"), url = try existing(String(reference.dropFirst(3)))
        try assertWithin(url, parent: assets)
        try local(url)
        let bytes = try read(url)
        _ = try Self.validateImage(bytes)
        return bytes
    }

    public func requestDownload() throws {
        var enumerationError: Error?
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isUbiquitousItemKey], options: [.skipsHiddenFiles], errorHandler: { _, error in
            enumerationError = error
            return false
        })
        guard let enumerator else { throw JournalError("无法访问日记目录") }
        for case let file as URL in enumerator {
            try assertWithin(file, parent: directory)
            let values = try file.resourceValues(forKeys: [.isUbiquitousItemKey])
            if values.isUbiquitousItem == true { try FileManager.default.startDownloadingUbiquitousItem(at: file) }
        }
        if let enumerationError { throw enumerationError }
    }

    public static func validateImage(_ bytes: Data) throws -> String {
        guard bytes.count <= 10 * 1024 * 1024 else { throw JournalError("图片超过 10 MB") }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil), let type = CGImageSourceGetType(source) as String?,
              let ext = ["public.png": "png", "public.jpeg": "jpg", "org.webmproject.webp": "webp"][type] else { throw JournalError("仅支持实际内容为 PNG、JPG、WebP 的图片") }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= 40_000_000,
              CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary) != nil,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { throw JournalError("图片损坏或超过 4000 万像素") }
        return ext
    }

    private func existing(_ relative: String) throws -> URL {
        let url = directory.appendingPathComponent(relative).standardizedFileURL
        try assertWithin(url, parent: directory)
        _ = try url.resourceValues(forKeys: [.isDirectoryKey])
        return url
    }
}

private func assertWithin(_ url: URL, parent: URL) throws {
    let root = parent.resolvingSymlinksInPath().standardizedFileURL.path
    let target = url.resolvingSymlinksInPath().standardizedFileURL.path
    guard target.hasPrefix(root + "/") else { throw JournalError("路径超出允许的内容目录：\(url.lastPathComponent)") }
}

private func local(_ file: URL) throws {
    let values = try file.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
                                                 .ubiquitousItemDownloadingErrorKey, .ubiquitousItemUploadingErrorKey])
    if let error = values.ubiquitousItemDownloadingError { throw error }
    if let error = values.ubiquitousItemUploadingError { throw error }
    if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded {
        throw JournalError("文件尚未下载，离线时不可用：\(file.lastPathComponent)。请联网后点击“下载 iCloud 文件”。")
    }
}

private func read(_ url: URL) throws -> Data { try coordinate(url, writing: false) { try Data(contentsOf: $0) } }

private func atomicWrite(_ data: Data, to file: URL, replacing: Bool) throws {
    let temp = file.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
    try data.write(to: temp, options: .withoutOverwriting)
    let result = replacing ? Darwin.rename(temp.path, file.path) : Darwin.link(temp.path, file.path)
    let savedErrno = errno
    if !replacing || result != 0 { _ = Darwin.unlink(temp.path) }
    guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(savedErrno)) }
}

private func resolveVersions(_ file: URL) throws {
    guard !(NSFileVersion.unresolvedConflictVersionsOfItem(at: file) ?? []).isEmpty else { return }
    try coordinate(file, writing: true) { url in
        let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        guard !versions.isEmpty else { return }
        guard var latest = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { throw JournalError("缺少文件修改时间，无法处理冲突") }
        var winner: NSFileVersion?
        for version in versions {
            guard let date = version.modificationDate else { throw JournalError("冲突版本缺少修改时间") }
            if date > latest { latest = date; winner = version }
        }
        if let winner {
            _ = try winner.replaceItem(at: url, options: [])
            try FileManager.default.setAttributes([.modificationDate: latest], ofItemAtPath: url.path)
        }
        for version in versions { version.isResolved = true }
    }
}

private func coordinate<T>(_ url: URL, writing: Bool, operation: (URL) throws -> T) throws -> T {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var error: NSError?, result: Result<T, Error>?
    let access: (URL) -> Void = { location in result = Result { try operation(location) } }
    if writing { coordinator.coordinate(writingItemAt: url, options: [], error: &error, byAccessor: access) }
    else { coordinator.coordinate(readingItemAt: url, options: [], error: &error, byAccessor: access) }
    if let error { throw error }
    guard let result else { throw JournalError("系统未执行文件协调操作") }
    return try result.get()
}
