import Foundation
import CryptoKit
import Yams

public enum MarkdownCodec {
    // Match the web application's YAML 1.2 scalar semantics: dates and yes/no remain strings.
    private static var resolver: Resolver {
        get throws {
            try Resolver.basic.appending(.null)
                .appending(.bool, "^(?:true|True|TRUE|false|False|FALSE)$")
                .appending(.int, "^(?:[-+]?[0-9]+|0o[0-7]+|0x[0-9a-fA-F]+)$")
                .appending(.float, "^(?:[-+]?(?:\\.[0-9]+|[0-9]+(?:\\.[0-9]*)?)[eE][-+]?[0-9]+|[-+]?(?:\\.[0-9]+|[0-9]+\\.[0-9]*)|[-+]?\\.(?:inf|Inf|INF)|\\.(?:nan|NaN|NAN))$")
        }
    }
    public static func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    private static func decode(_ text: String) throws -> ([String: Node], String) {
        let regex = try NSRegularExpression(pattern: "\\A---\\r?\\n([\\s\\S]*?)\\r?\\n---(?:\\r?\\n|$)")
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { throw JournalError("缺少或未关闭 YAML frontmatter") }
        let yaml = ns.substring(with: match.range(at: 1))
        guard let root = try Yams.compose(yaml: yaml, resolver) else { throw JournalError("YAML 元数据为空") }
        try validateKeys(root)
        return (try mapping(root), ns.substring(from: match.range.length))
    }
    private static func validateKeys(_ node: Node) throws {
        if let map = node.mapping {
            var seen = Set<String>()
            for (key, value) in map {
                guard key.tag == Tag(.str), let name = key.string else { throw JournalError("YAML 字段名必须是字符串") }
                guard seen.insert(name).inserted else { throw JournalError("重复 YAML 字段：\(name)") }
                try validateKeys(value)
            }
        } else if let sequence = node.sequence {
            for value in sequence { try validateKeys(value) }
        }
    }
    private static func mapping(_ node: Node) throws -> [String: Node] {
        guard let mapping = node.mapping else { throw JournalError("元数据必须为对象") }
        return Dictionary(uniqueKeysWithValues: try mapping.map { key, value in
            guard let key = key.string else { throw JournalError("字段名必须为字符串") }; return (key, value)
        })
    }
    private static func exact(_ map: [String: Node], allowed: Set<String>) throws {
        let extra = Set(map.keys).subtracting(allowed)
        if !extra.isEmpty { throw JournalError("未知字段：" + extra.sorted().joined(separator: ", ")) }
    }
    private static func string(_ node: Node?, _ name: String) throws -> String {
        guard let node, node.tag == Tag(.str), let text = node.string else { throw JournalError("\(name)：必须为字符串") }
        return text
    }
    private static func number(_ node: Node?, _ name: String) throws -> Double {
        guard let node, node.tag == Tag(.int) || node.tag == Tag(.float), let text = node.scalar?.string else { throw JournalError("\(name)：必须为有限数值") }
        let number: Double?
        if text.hasPrefix("0x") || text.hasPrefix("0o") {
            let radix = text.hasPrefix("0x") ? 16 : 8
            var accumulated = 0.0
            for character in text.dropFirst(2) {
                guard let digit = Int(String(character), radix: radix) else { throw JournalError("\(name)：无效数值") }
                accumulated = accumulated * Double(radix) + Double(digit)
            }
            number = accumulated
        } else { number = Double(text) }
        guard let value = number, value.isFinite else { throw JournalError("\(name)：必须为有限数值") }
        return value
    }
    private static func strings(_ node: Node?, _ name: String) throws -> [String] {
        guard let sequence = node?.sequence else { throw JournalError("\(name)：必须为字符串数组") }
        return try sequence.map { try string($0, name) }
    }
    private static func version(_ map: [String: Node]) throws {
        guard try number(map["schema_version"], "schema_version") == 1 else { throw JournalError("不支持的 schema_version") }
    }
    public static func activity(_ text: String) throws -> Activity {
        let (map, body) = try decode(text)
        try exact(map, allowed: ["schema_version", "id", "name", "icon", "color", "metrics"]); try version(map)
        let id = try string(map["id"], "id"), name = try string(map["name"], "name").trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = try string(map["icon"], "icon"), color = try string(map["color"], "color")
        guard matches(id, "^[a-z0-9]+(?:-[a-z0-9]+)*$"), !name.isEmpty, !icon.isEmpty, matches(color, "^#[0-9a-fA-F]{6}$") else { throw JournalError("活动 ID、名称、图标或颜色无效") }
        let keys = try strings(map["metrics"], "metrics")
        let metrics = try keys.map { key -> Metric in guard let metric = Metric(rawValue: key) else { throw JournalError("未知指标：\(key)") }; return metric }
        guard Set(metrics).count == metrics.count else { throw JournalError("指标不能重复") }
        return Activity(id: id, name: name, icon: icon, color: color, metrics: metrics, body: body)
    }
    public static func entry(_ text: String, activities: [Activity], now: Date = Date()) throws -> Entry {
        let (map, body) = try decode(text)
        try exact(map, allowed: ["schema_version", "id", "kind", "title", "date", "started_at", "activity_id", "metrics", "tags", "cover"]); try version(map)
        var entry = Entry(id: try string(map["id"], "id"), kind: try string(map["kind"], "kind"), title: try string(map["title"], "title"), date: try string(map["date"], "date"), body: body, hash: hash(text))
        if let node = map["started_at"] { entry.startedAt = try string(node, "started_at") }
        if let node = map["activity_id"] { entry.activityID = try string(node, "activity_id") }
        if let node = map["cover"] { entry.cover = try string(node, "cover") }
        if let node = map["tags"] { entry.tags = try strings(node, "tags") }
        if let node = map["metrics"] {
            let values = try mapping(node)
            try exact(values, allowed: Set(Metric.allCases.map(\.rawValue)))
            entry.metrics = try Dictionary(uniqueKeysWithValues: values.map { (Metric(rawValue: $0.key)!, try number($0.value, $0.key)) })
        }
        return try validated(entry, activities: activities, now: now)
    }
    public static func validated(_ input: Entry, activities: [Activity], now: Date = Date()) throws -> Entry {
        var entry = input
        guard validUUID(entry.id) else { throw JournalError("id：必须为有效 UUID") }
        guard ["event", "journal"].contains(entry.kind) else { throw JournalError("kind：仅支持 event 或 journal") }
        entry.title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.title.isEmpty else { throw JournalError("请输入标题") }
        guard JournalDate.parse(entry.date) != nil else { throw JournalError("date：日期无效") }
        guard entry.date <= JournalDate.today(now) else { throw JournalError("date：不能记录未来日期") }
        if let timestamp = entry.startedAt {
            guard let date = JournalDate.timestamp(timestamp), date <= now, JournalDate.today(date) == entry.date else { throw JournalError("started_at：时间不能在未来，按上海时区换算的日期须与 date 一致") }
        }
        if entry.kind == "journal" {
            guard entry.activityID == nil, entry.metrics == nil else { throw JournalError("journal：不允许 activity_id 或 metrics") }
        } else {
            guard let activity = activities.first(where: { $0.id == entry.activityID }) else { throw JournalError("activity_id：必须引用已有活动") }
            for (key, value) in entry.metrics ?? [:] {
                guard activity.metrics.contains(key) else { throw JournalError("该活动不支持指标：\(key.title)") }
                guard value.isFinite, value >= 0, key != .pages || value.rounded() == value else { throw JournalError("\(key.title)：必须非负，页数必须为整数") }
            }
        }
        if let cover = entry.cover, !matches(cover, "^\\.\\./assets/[0-9a-f-]+/[a-zA-Z0-9._-]+$") { throw JournalError("cover：应为 ../assets/<UUID>/<filename>") }
        if let tags = entry.tags {
            var seen = Set<String>()
            entry.tags = try tags.compactMap { tag in
                let tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tag.isEmpty else { throw JournalError("tags：标签不能为空") }
                return seen.insert(tag).inserted ? tag : nil
            }
        }
        return entry
    }
    public static func encode(_ entry: Entry) throws -> String {
        var meta: [String: Any] = ["schema_version": 1, "id": entry.id, "kind": entry.kind, "title": entry.title, "date": entry.date]
        if let value = entry.startedAt { meta["started_at"] = value }
        if let value = entry.activityID { meta["activity_id"] = value }
        if let value = entry.metrics { meta["metrics"] = Dictionary(uniqueKeysWithValues: value.map { ($0.key.rawValue, $0.value) }) }
        if let value = entry.tags { meta["tags"] = value }
        if let value = entry.cover { meta["cover"] = value }
        return try encode(meta, body: entry.body)
    }
    public static func encode(_ activity: Activity) throws -> String {
        try encode(["schema_version": 1, "id": activity.id, "name": activity.name, "icon": activity.icon, "color": activity.color, "metrics": activity.metrics.map(\.rawValue)], body: activity.body)
    }
    private static func encode(_ meta: [String: Any], body: String) throws -> String {
        "---\n" + (try Yams.dump(object: meta, width: -1, allowUnicode: true, sortKeys: true)) + "---\n" + (body.hasPrefix("\n") ? "" : "\n") + body
    }
    public static func validateSettings(_ data: Data) throws {
        guard let map = try JSONSerialization.jsonObject(with: data) as? [String: Any], Set(map.keys) == ["schema_version", "timezone", "week_starts_on"],
              let version = map["schema_version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1,
              let week = map["week_starts_on"] as? NSNumber, CFGetTypeID(week) != CFBooleanGetTypeID(), week == 1,
              map["timezone"] as? String == "Asia/Shanghai" else { throw JournalError("settings.json：仅支持 schema_version=1、Asia/Shanghai 时区、周一开始，且不能含未知字段") }
    }
}
