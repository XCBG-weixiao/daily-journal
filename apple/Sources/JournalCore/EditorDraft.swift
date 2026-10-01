import Foundation

/// A local draft preserves the original hash and input for each activity.
public struct EditorDraft: Codable, Equatable, Sendable, Identifiable {
    public var original: Entry
    public var entry: Entry
    public var time: String
    public var tags: String
    public var cover: String
    public var activityID: String
    public var values: [String: [Metric: String]]
    public var mode = "write"
    public var details: Bool
    public var updatedAt = Date()
    public var id: String { entry.id }
    public init(entry: Entry, activities: [Activity]) {
        original = entry; self.entry = entry
        time = entry.startedAt == nil ? "" : JournalDate.time(entry.startedAt)
        tags = entry.tags?.joined(separator: ", ") ?? ""; cover = entry.cover ?? ""
        activityID = entry.activityID ?? activities.first?.id ?? ""
        values = [activityID: Dictionary(uniqueKeysWithValues: (entry.metrics ?? [:]).map { ($0.key, String($0.value)) })]
        details = entry.kind == "journal" || entry.hash != nil || !entry.body.isEmpty || !(entry.tags ?? []).isEmpty || entry.cover != nil
    }
    public var isModified: Bool {
        entry != original || time != (original.startedAt == nil ? "" : JournalDate.time(original.startedAt))
        || tags != (original.tags?.joined(separator: ", ") ?? "") || cover != (original.cover ?? "")
        || (entry.kind == "event" && (activityID != original.activityID || values != [original.activityID ?? activityID: Dictionary(uniqueKeysWithValues: (original.metrics ?? [:]).map { ($0.key, String($0.value)) })]))
    }
    public func candidate(activities: [Activity], now: Date = Date()) throws -> Entry {
        var result = entry
        let clock = time.trimmingCharacters(in: .whitespaces)
        if clock.isEmpty { result.startedAt = nil }
        else {
            guard matches(clock, "^([01][0-9]|2[0-3]):[0-5][0-9]$") else { throw JournalError("时间格式应为 HH:mm，例如 08:30") }
            result.startedAt = clock == JournalDate.time(original.startedAt) && entry.date == original.date
                ? original.startedAt : "\(entry.date)T\(clock):00+08:00"
        }
        result.tags = tags.components(separatedBy: CharacterSet(charactersIn: ",，")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        result.cover = cover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : cover
        if result.kind == "event" {
            guard let activity = activities.first(where: { $0.id == activityID }) else { throw JournalError("请选择活动，或先新建一个活动") }
            result.activityID = activity.id; result.metrics = [:]
            for metric in activity.metrics {
                let text = (values[activityID]?[metric] ?? "").trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    guard let number = Double(text) else { throw JournalError("\(metric.title)：请输入数值") }
                    result.metrics?[metric] = number
                }
            }
            if result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.title = activity.name }
        } else {
            result.activityID = nil; result.metrics = nil
            if result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.title = entry.date + " 日记" }
        }
        return try MarkdownCodec.validated(result, activities: activities, now: now)
    }
    public func copyAsNew() -> EditorDraft {
        var copy = self
        let id = UUID().uuidString.lowercased()
        copy.original.id = id; copy.original.hash = nil
        copy.entry.id = id; copy.entry.hash = nil
        copy.updatedAt = Date()
        return copy
    }
}

public final class DraftCache {
    private let folder: URL
    public init(folder: URL) { self.folder = folder }
    public func save(_ draft: EditorDraft) throws {
        guard validUUID(draft.id) else { throw JournalError("草稿 ID 无效") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: folder.appendingPathComponent(draft.id + ".json"), options: .atomic)
    }
    public func remove(_ id: String) throws {
        guard validUUID(id) else { throw JournalError("草稿 ID 无效") }
        let file = folder.appendingPathComponent(id + ".json")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
    public func all() throws -> [EditorDraft] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") }.map { name in
            let value = try JSONDecoder().decode(EditorDraft.self, from: Data(contentsOf: folder.appendingPathComponent(name)))
            guard name == value.id + ".json", validUUID(value.id), JournalDate.parse(value.entry.date) != nil else { throw JournalError("草稿文件无效：\(name)") }
            return value
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
}
