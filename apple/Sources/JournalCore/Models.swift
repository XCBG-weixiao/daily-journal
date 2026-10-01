import Foundation

public struct JournalError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public struct JournalConflict: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum Metric: String, CaseIterable, Codable, Sendable {
    case duration = "duration_min", distance = "distance_km", pages
    public var title: String { switch self { case .duration: return "时长"; case .distance: return "距离"; case .pages: return "页数" } }
    public var unit: String { switch self { case .duration: return "min"; case .distance: return "km"; case .pages: return "页" } }
}

public struct Activity: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let icon: String
    public let color: String
    public let metrics: [Metric]
    public let body: String
    public var hash: String?
    public init(id: String, name: String, icon: String, color: String, metrics: [Metric], body: String = "", hash: String? = nil) {
        self.id = id; self.name = name; self.icon = icon; self.color = color; self.metrics = metrics; self.body = body
        self.hash = hash
    }
    public static let defaults: [Activity] = [
        Activity(id: "running", name: "跑步", icon: "🏃", color: "#3D8060", metrics: [.duration, .distance]),
        Activity(id: "badminton", name: "羽毛球", icon: "🏸", color: "#7963B4", metrics: [.duration]),
        Activity(id: "reading", name: "阅读", icon: "📖", color: "#B78030", metrics: [.duration, .pages])
    ]
}

public struct Entry: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var kind: String
    public var title: String
    public var date: String
    public var startedAt: String?
    public var activityID: String?
    public var metrics: [Metric: Double]?
    public var tags: [String]?
    public var cover: String?
    public var body: String
    public var hash: String?
    public init(id: String = UUID().uuidString.lowercased(), kind: String = "journal", title: String = "", date: String = JournalDate.today(), startedAt: String? = nil, activityID: String? = nil, metrics: [Metric: Double]? = nil, tags: [String]? = nil, cover: String? = nil, body: String = "", hash: String? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.date = date; self.startedAt = startedAt
        self.activityID = activityID; self.metrics = metrics; self.tags = tags; self.cover = cover; self.body = body; self.hash = hash
    }
}

public struct ContentIssue: Identifiable, Equatable, Sendable {
    public let file: String
    public let message: String
    public var id: String { file }
    public init(file: String, message: String) { self.file = file; self.message = message }
}

public struct JournalSnapshot: Sendable {
    public var activities: [Activity] = []
    public var entries: [Entry] = []
    public var issues: [ContentIssue] = []
    public var archivedActivityIDs: Set<String> = []
    public var trash: [TrashItem] = []
    public var activeActivities: [Activity] { activities.filter { !archivedActivityIDs.contains($0.id) } }
    public var isDemo: Bool { entries.contains { $0.tags?.contains("示例") == true } }
    public init() {}
}

public struct TrashItem: Identifiable, Equatable, Codable, Sendable {
    public struct File: Equatable, Codable, Sendable {
        public let path: String
        public let hash: String
        public init(path: String, hash: String) { self.path = path; self.hash = hash }
    }
    public let schemaVersion: Int
    public let id: String
    public let title: String
    public let kind: String
    public let deletedAt: Date
    public let files: [File]
    public var recordCount: Int { files.filter { $0.path.hasPrefix("entries/") }.count }
    public init(id: String = UUID().uuidString.lowercased(), title: String, kind: String, deletedAt: Date = Date(), files: [File]) {
        self.schemaVersion = 1; self.id = id; self.title = title; self.kind = kind; self.deletedAt = deletedAt; self.files = files
    }
}

public struct EntryFilter: Sendable {
    public var query = ""
    public var kind = "all"
    public var activityID: String?
    public var start: String?
    public var end: String?
    public var tag: String?
    public init() {}
    public func matches(_ entry: Entry, activities: [Activity]) -> Bool {
        guard kind == "all" || entry.kind == kind,
              activityID == nil || entry.activityID == activityID,
              start == nil || entry.date >= start!, end == nil || entry.date <= end!,
              tag == nil || entry.tags?.contains(tag!) == true else { return false }
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if words.isEmpty { return true }
        let activityName = activities.first { $0.id == entry.activityID }?.name ?? ""
        return ([entry.title, entry.body, activityName] + (entry.tags ?? [])).joined(separator: "\n").localizedCaseInsensitiveContains(words)
    }
}

public enum JournalText {
    public static func imageReferences(_ body: String) -> [String] {
        let pattern = "!\\[[^\\]]*\\]\\((\\.\\./assets/[^\\s)]+)(?:\\s+\"[^\"]*\")?\\)"
        let regex = try! NSRegularExpression(pattern: pattern)
        let text = body as NSString
        return Array(Set(regex.matches(in: body, range: NSRange(location: 0, length: text.length)).map { text.substring(with: $0.range(at: 1)) })).sorted()
    }
    public static func excerpt(_ body: String) -> String {
        body.replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]*\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[#>*`\\[\\]]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func removingImage(_ reference: String, from body: String) -> String {
        let target = NSRegularExpression.escapedPattern(for: reference)
        return body.replacingOccurrences(of: "!\\[[^\\]]*\\]\\(\(target)(?:\\s+\"[^\"]*\")?\\)", with: "", options: .regularExpression)
    }
}

public enum JournalDate {
    public static var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        result.firstWeekday = 2
        return result
    }
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = format; f.isLenient = false
        return f
    }
    public static func today(_ now: Date = Date()) -> String { formatter("yyyy-MM-dd").string(from: now) }
    public static func parse(_ day: String) -> Date? {
        guard matches(day, "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"), let value = formatter("yyyy-MM-dd").date(from: day), today(value) == day else { return nil }
        return value
    }
    public static func timestamp(_ value: String) -> Date? {
        guard matches(value, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\\.[0-9]+)?(Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])$"), parse(String(value.prefix(10))) != nil else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = value.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return f.date(from: value)
    }
    public static func time(_ value: String?) -> String {
        guard let value, let date = timestamp(value) else { return "未设时间" }
        return formatter("HH:mm").string(from: date)
    }
    public static func shift(_ day: String, days: Int) -> String {
        today(calendar.date(byAdding: .day, value: days, to: parse(day)!)!)
    }
    public static func shiftMonth(_ month: String, by amount: Int) -> String {
        String(today(calendar.date(byAdding: .month, value: amount, to: parse(month + "-01")!)!).prefix(7))
    }
    public static func weekday(_ day: String) -> Int { (calendar.component(.weekday, from: parse(day)!) + 5) % 7 }
    public static func monthDays(_ month: String) -> [String] {
        let first = month + "-01", start = shift(first, days: -weekday(first))
        return (0..<42).map { shift(start, days: $0) }
    }
    public static func yearDays(_ year: Int) -> [String?] {
        let first = String(format: "%04d-01-01", year), end = String(format: "%04d-01-01", year + 1)
        let count = calendar.dateComponents([.day], from: parse(first)!, to: parse(end)!).day!
        let before = weekday(first), length = ((before + count + 6) / 7) * 7
        return (0..<length).map { $0 < before || $0 >= before + count ? nil : shift(first, days: $0 - before) }
    }
    public static func label(_ day: String) -> String { formatter("M月d日 EEEE").string(from: parse(day)!) }
}

public func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
public func validUUID(_ value: String) -> Bool {
    matches(value, "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)$")
}
public func numberLabel(_ value: Double?) -> String {
    guard let value else { return "—" }
    return value.formatted(.number.precision(.fractionLength(0...2)))
}

public struct Summary: Sendable {
    public let count: Int
    public let days: Int
    public let sums: [Metric: Double]
    public let samples: [Metric: Int]
    public var averageDuration: Double? {
        guard let total = sums[.duration], let sample = samples[.duration], sample > 0 else { return nil }
        return (total / Double(sample) * 10).rounded() / 10
    }
    public init(_ entries: [Entry]) {
        let events = entries.filter { $0.kind == "event" }
        count = events.count; days = Set(events.map(\.date)).count
        var sums: [Metric: Double] = [:], samples: [Metric: Int] = [:]
        for key in Metric.allCases {
            let values = events.compactMap { $0.metrics?[key] }
            samples[key] = values.count
            if !values.isEmpty { sums[key] = (values.reduce(0, +) * 100).rounded() / 100 }
        }
        self.sums = sums; self.samples = samples
    }
}
public func ordered(_ entries: [Entry]) -> [Entry] {
    entries.sorted {
        if $0.date != $1.date { return $0.date < $1.date }
        let a = $0.startedAt.flatMap(JournalDate.timestamp) ?? .distantFuture
        let b = $1.startedAt.flatMap(JournalDate.timestamp) ?? .distantFuture
        return a == b ? $0.id < $1.id : a < b
    }
}
