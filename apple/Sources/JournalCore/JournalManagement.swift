import Foundation
import CryptoKit

private struct ArchiveMarker: Codable {
    let schemaVersion: Int
    let activityID: String
}
private struct MoveRecoveryError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension JournalRepository {
    /// Management metadata is separate from schema_version=1 Markdown.
    func loadManagement(into data: inout JournalSnapshot) throws {
        let fm = FileManager.default
        let archive = directory.appendingPathComponent("journal-state/archived")
        if fm.fileExists(atPath: archive.path) {
            try assertWithin(archive, parent: directory); try local(archive)
            for name in try fm.contentsOfDirectory(atPath: archive.path).sorted() where name.hasSuffix(".json") || name.hasSuffix(".json.icloud") {
                let path = "journal-state/archived/" + name
                do {
                    guard !name.hasSuffix(".icloud") else { throw JournalError("归档状态尚未下载，请下载日记库后刷新") }
                    let file = try existing(path); try local(file); try resolveVersions(file)
                    let marker = try JSONDecoder().decode(ArchiveMarker.self, from: read(file))
                    guard marker.schemaVersion == 1, name == marker.activityID + ".json",
                          matches(marker.activityID, "^[a-z0-9]+(?:-[a-z0-9]+)*$") else { throw JournalError("归档标记无效") }
                    data.archivedActivityIDs.insert(marker.activityID)
                } catch { data.issues.append(ContentIssue(file: path, message: error.localizedDescription)) }
            }
        }
        let trash = directory.appendingPathComponent("journal-trash")
        if fm.fileExists(atPath: trash.path) {
            try assertWithin(trash, parent: directory); try local(trash)
            for name in try fm.contentsOfDirectory(atPath: trash.path).sorted() where !name.hasPrefix(".") {
                let path = "journal-trash/" + name
                do {
                    guard validUUID(name) else { throw JournalError("回收站目录 ID 无效") }
                    let file = try existing(path + "/receipt.json"); try local(file)
                    let item = try JSONDecoder().decode(TrashItem.self, from: read(file))
                    try validateReceipt(item)
                    guard item.id == name else { throw JournalError("回收站目录与 ID 不一致") }
                    data.trash.append(item)
                    for stored in item.files {
                        do { try local(existing(path + "/files/" + stored.path)) }
                        catch { data.issues.append(ContentIssue(file: path + "/files/" + stored.path, message: error.localizedDescription)) }
                    }
                } catch { data.issues.append(ContentIssue(file: path, message: error.localizedDescription)) }
            }
        }
        data.trash.sort { $0.deletedAt > $1.deletedAt }
    }

    public func saveActivity(_ input: Activity) throws -> Activity {
        let text = try MarkdownCodec.encode(input)
        var value = try MarkdownCodec.activity(text)
        try coordinate(directory, writing: true) { _ in
            let data = try snapshot()
            guard !data.activities.contains(where: { $0.id != value.id && $0.name.localizedCaseInsensitiveCompare(value.name) == .orderedSame }) else {
                throw JournalError("已有同名活动，请使用不同名称")
            }
            if let old = data.activities.first(where: { $0.id == value.id }), old.metrics != value.metrics {
                try requireComplete(data)
                let removed = Set(old.metrics).subtracting(value.metrics)
                let historical = try data.trash.flatMap { try trashedEntries($0) }
                let impacted = (data.entries + historical).filter { $0.activityID == value.id && !Set($0.metrics?.keys.map { $0 } ?? []).isDisjoint(with: removed) }
                guard impacted.isEmpty else {
                    throw JournalError("不能移除已有记录使用的指标，涉及 \(impacted.count) 条记录。请保留这些指标；新增指标不会影响历史。")
                }
            }
            let folder = try existing("activities"), file = folder.appendingPathComponent(value.id + ".md")
            try assertWithin(file, parent: folder)
            let exists = FileManager.default.fileExists(atPath: file.path)
            if exists { try verify(file, expected: input.hash) }
            else if input.hash != nil { throw JournalError("活动文件已被移动或删除，请重新打开") }
            try atomicWrite(Data(text.utf8), to: file, replacing: exists)
        }
        value.hash = MarkdownCodec.hash(text)
        return value
    }

    public func archiveActivity(_ activity: Activity, archived: Bool) throws {
        try coordinate(directory, writing: true) { _ in
            try verify(existing("activities/\(activity.id).md"), expected: activity.hash)
            let folder = try managementFolder("journal-state/archived")
            let file = folder.appendingPathComponent(activity.id + ".json")
            try assertWithin(file, parent: folder)
            if archived {
                let bytes = try JSONEncoder().encode(ArchiveMarker(schemaVersion: 1, activityID: activity.id))
                try atomicWrite(bytes, to: file, replacing: FileManager.default.fileExists(atPath: file.path))
            } else if FileManager.default.fileExists(atPath: file.path) {
                try local(file); try FileManager.default.removeItem(at: file)
            }
        }
    }

    public func trashEntry(_ entry: Entry) throws -> TrashItem {
        try coordinate(directory, writing: true) { _ in
            let path = "entries/\(entry.id).md"
            try verify(existing(path), expected: entry.hash)
            return try moveToTrash(title: entry.title, kind: "entry", paths: [path])
        }
    }

    public func trashActivity(_ activity: Activity, includingEntries: Bool, expectedEntries: [String: String] = [:]) throws -> TrashItem {
        try coordinate(directory, writing: true) { _ in
            let data = try snapshot(); try requireComplete(data)
            let records = data.entries.filter { $0.activityID == activity.id }
            guard includingEntries || records.isEmpty else { throw JournalError("此活动有 \(records.count) 条记录。可以归档保留历史，或明确选择连同记录一起删除。") }
            guard Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.hash!) }) == expectedEntries else { throw JournalError("活动记录已变化，请刷新后重新确认删除数量") }
            for record in records { try verify(existing("entries/\(record.id).md"), expected: record.hash) }
            let path = "activities/\(activity.id).md"
            try verify(existing(path), expected: activity.hash)
            var paths = [path] + records.map { "entries/\($0.id).md" }
            let marker = "journal-state/archived/\(activity.id).json"
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(marker).path) { paths.append(marker) }
            return try moveToTrash(title: activity.name, kind: "activity", paths: paths)
        }
    }

    public func trashedEntries(_ item: TrashItem) throws -> [Entry] {
        let data = try snapshot()
        var activities = data.activities
        for file in item.files where file.path.hasPrefix("activities/") {
            let activity = try MarkdownCodec.activity(trashText(item, file: file))
            activities.removeAll { $0.id == activity.id }; activities.append(activity)
        }
        return try item.files.filter { $0.path.hasPrefix("entries/") }.map {
            try MarkdownCodec.entry(trashText(item, file: $0), activities: activities)
        }
    }
    public func trashedImageData(_ item: TrashItem, path: String) throws -> Data {
        guard let file = item.files.first(where: { $0.path == path }), path.hasPrefix("assets/") else { throw JournalError("回收站图片不存在") }
        let bytes = try trashBytes(item, file: file)
        _ = try Self.validateImage(bytes)
        return bytes
    }

    public func restoreTrash(_ item: TrashItem) throws {
        try coordinate(directory, writing: true) { _ in
            try validateReceipt(item)
            try verifyReceipt(item)
            let _ = try trashedEntries(item)
            var moves: [(URL, URL)] = []
            for file in item.files {
                _ = try trashBytes(item, file: file)
                let source = try existing("journal-trash/\(item.id)/files/\(file.path)")
                let destination = directory.appendingPathComponent(file.path)
                try assertWithin(destination, parent: directory)
                guard !FileManager.default.fileExists(atPath: destination.path) else { throw JournalError("恢复位置已有文件，未覆盖：\(file.path)") }
                _ = try managementFolder(destination.deletingLastPathComponent().path.replacingOccurrences(of: directory.path + "/", with: ""))
                moves.append((source, destination))
            }
            try moveFiles(moves)
            try FileManager.default.removeItem(at: existing("journal-trash/\(item.id)"))
        }
    }

    public func permanentlyDeleteTrash(_ item: TrashItem) throws {
        try coordinate(directory, writing: true) { _ in
            try verifyReceipt(item)
            try FileManager.default.removeItem(at: existing("journal-trash/\(item.id)"))
        }
    }

    public func unreferencedImages(protected: Set<String> = []) throws -> [String] {
        let data = try snapshot(); try requireComplete(data)
        var texts = data.entries.map { $0.body + "\n" + ($0.cover ?? "") }
        for item in data.trash {
            for file in item.files where file.path.hasSuffix(".md") {
                texts.append(try trashText(item, file: file))
            }
        }
        let assets = try existing("assets")
        var result: [String] = []
        for id in try FileManager.default.contentsOfDirectory(atPath: assets.path) where validUUID(id) {
            let folder = try existing("assets/" + id); try local(folder)
            for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where matches(name, "^[a-zA-Z0-9._-]+\\.(png|jpg|jpeg|webp)$") {
                let reference = "../assets/\(id)/\(name)"
                if !protected.contains(reference), !texts.contains(where: { $0.contains(reference) }) { result.append(reference) }
            }
        }
        return result.sorted()
    }

    public func trashUnusedImages(_ references: [String], protected: Set<String> = []) throws -> TrashItem {
        try coordinate(directory, writing: true) { _ in
            let available = Set(try unreferencedImages(protected: protected))
            guard !references.isEmpty, Set(references).isSubset(of: available) else { throw JournalError("图片引用已变化，请重新检查后清理") }
            return try moveToTrash(title: "\(references.count) 张未使用图片", kind: "images", paths: references.map { String($0.dropFirst(3)) })
        }
    }

    private func requireComplete(_ data: JournalSnapshot) throws {
        guard data.issues.isEmpty else { throw JournalError("日记库有未读取或无效文件，请先解决文件问题再执行此操作，以免遗漏历史引用") }
    }
    private func verify(_ url: URL, expected: String?) throws {
        try local(url)
        guard let expected, MarkdownCodec.hash(try String(contentsOf: url, encoding: .utf8)) == expected else { throw JournalError("文件已变化，请刷新并重新打开后重试") }
    }
    private func managementFolder(_ relative: String) throws -> URL {
        let folder = directory.appendingPathComponent(relative)
        try assertWithin(folder, parent: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try local(folder)
        return folder
    }
    private func validateReceipt(_ item: TrashItem) throws {
        guard item.schemaVersion == 1, validUUID(item.id), ["entry", "activity", "images"].contains(item.kind),
              !item.files.isEmpty, Set(item.files.map(\.path)).count == item.files.count else { throw JournalError("回收站清单无效") }
        for file in item.files {
            guard matches(file.hash, "^[a-f0-9]{64}$"),
                  matches(file.path, "^(entries/[a-fA-F0-9-]+\\.md|activities/[a-z0-9-]+\\.md|journal-state/archived/[a-z0-9-]+\\.json|assets/[a-fA-F0-9-]+/[a-zA-Z0-9._-]+)$") else { throw JournalError("回收站文件路径无效：\(file.path)") }
        }
    }
    private func trashBytes(_ item: TrashItem, file: TrashItem.File) throws -> Data {
        try validateReceipt(item)
        let url = try existing("journal-trash/\(item.id)/files/\(file.path)"); try local(url)
        let bytes = try read(url)
        guard digest(bytes) == file.hash else { throw JournalError("回收站文件已变化：\(file.path)") }
        return bytes
    }
    private func verifyReceipt(_ item: TrashItem) throws {
        let receipt = try existing("journal-trash/\(item.id)/receipt.json"); try local(receipt)
        let current = try JSONDecoder().decode(TrashItem.self, from: read(receipt))
        guard current == item else { throw JournalError("回收站项目已变化，请刷新后重试") }
    }
    private func trashText(_ item: TrashItem, file: TrashItem.File) throws -> String {
        guard let text = String(data: try trashBytes(item, file: file), encoding: .utf8) else { throw JournalError("回收站文件不是 UTF-8 文本：\(file.path)") }
        return text
    }
    private func moveToTrash(title: String, kind: String, paths: [String]) throws -> TrashItem {
        let fm = FileManager.default
        let files = try paths.map { path -> TrashItem.File in
            let file = try existing(path); try local(file)
            return TrashItem.File(path: path, hash: digest(try read(file)))
        }
        let item = TrashItem(title: title, kind: kind, files: files)
        let folder = try managementFolder("journal-trash/\(item.id)")
        var moves: [(URL, URL)] = []
        for path in paths {
            let destination = folder.appendingPathComponent("files/" + path)
            try assertWithin(destination, parent: folder)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            moves.append((try existing(path), destination))
        }
        do {
            try atomicWrite(JSONEncoder().encode(item), to: folder.appendingPathComponent("receipt.json"), replacing: false)
            try moveFiles(moves)
        } catch {
            if !(error is MoveRecoveryError) { try fm.removeItem(at: folder) }
            throw error
        }
        return item
    }
    private func moveFiles(_ moves: [(URL, URL)]) throws {
        var completed: [(URL, URL)] = []
        do {
            for move in moves { try FileManager.default.moveItem(at: move.0, to: move.1); completed.append(move) }
        } catch {
            let original = error
            for move in completed.reversed() {
                do { try FileManager.default.moveItem(at: move.1, to: move.0) }
                catch { throw MoveRecoveryError(message: "文件移动失败且恢复未完成：\(original.localizedDescription)；\(error.localizedDescription)。请保留回收站目录并检查文件。") }
            }
            throw original
        }
    }
}

private func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
