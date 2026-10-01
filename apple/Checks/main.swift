import Foundation
import JournalCore

struct Failure: Error { let message: String }
var passed = 0
@MainActor func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw Failure(message: message) }
    passed += 1; print("PASS \(passed): \(message)"); fflush(stdout)
}
@MainActor func rejects(_ message: String, _ operation: () throws -> Void) throws {
    do { try operation() } catch { passed += 1; print("PASS \(passed): \(message)"); fflush(stdout); return }
    throw Failure(message: "Expected failure: " + message)
}
@MainActor func rejectsAsync(_ message: String, _ operation: () async throws -> Void) async throws {
    do { try await operation() } catch { passed += 1; print("PASS \(passed): \(message)"); fflush(stdout); return }
    throw Failure(message: "Expected failure: " + message)
}

let now = JournalDate.timestamp("2026-09-17T12:00:00+08:00")!
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("DailyJournalChecks-" + UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: false)
defer { do { try fm.removeItem(at: root) } catch { fputs("Temporary directory cleanup failed: \(error)\n", stderr) } }
let repository = JournalRepository(directory: root)
try await repository.initialize()
let initial = try await repository.snapshot(now: now)
try expect(initial.activities.count == 3 && initial.entries.isEmpty && initial.issues.isEmpty, "empty library initialized with original activity definitions")
let id = "10000000-0000-4000-8000-000000000001"
var event = Entry(id: id, kind: "event", title: "晨跑", date: "2026-09-14", startedAt: "2026-09-13T18:00:00Z", activityID: "running", metrics: [.duration: 32, .distance: 5.2], tags: [" 户外 ", "户外"], body: "# 记录\n\n第二段 **正文**\n\n```swift\nlet x = 1\n```\n")
let saved = try await repository.save(event, now: now)
let reopened = try await JournalRepository(directory: root).snapshot(now: now)
try expect(reopened.entries.count == 1 && reopened.entries[0].body.hasSuffix(event.body) && reopened.entries[0].tags == ["户外"], "Markdown write/read/reopen preserves body and normalizes tags")
try expect(reopened.entries[0].metrics?[.distance] == 5.2, "numeric metrics retain precision")
try await rejectsAsync("duplicate ID creation refuses overwrite") { _ = try await repository.save(event, now: now) }
var updated = saved; updated.title = "修改标题"
let updatedSaved = try await repository.save(updated, now: now)
try expect(updatedSaved.hash != saved.hash, "successful edits update content hash")
try await rejectsAsync("stale editor refuses to overwrite newer content") { _ = try await repository.save(saved, now: now) }
let entryFile = root.appendingPathComponent("entries/\(id).md")
let disk = try String(contentsOf: entryFile, encoding: .utf8)
try expect(MarkdownCodec.hash(disk) == updatedSaved.hash, "returned hash equals actual persisted bytes")
try await rejectsAsync("nonempty library never reinitialized") { try await repository.initialize() }
try expect(JournalDate.today(JournalDate.timestamp("2026-09-13T18:00:00Z")!) == "2026-09-14", "Shanghai day conversion")
try expect(JournalDate.parse("2026-02-30") == nil && JournalDate.parse("2024-02-29") != nil, "strict calendar dates and leap years")
try expect(JournalDate.timestamp("2026-02-30T08:00:00Z") == nil && JournalDate.timestamp("2026-09-13T24:00:00Z") == nil, "timestamps reject normalized invalid days and 24-hour overflow")
try expect(JournalDate.monthDays("2026-09").count == 42 && JournalDate.monthDays("2026-09").first == "2026-08-31", "42-cell Monday-first month")
try expect(JournalDate.yearDays(2024).compactMap { $0 }.count == 366 && JournalDate.yearDays(2012).count == 378, "leap-year heatmap and 54-week year")
var missing = event; missing.id = UUID().uuidString.lowercased(); missing.metrics = [:]
var zero = event; zero.id = UUID().uuidString.lowercased(); zero.metrics = [.duration: 0]
let journal = Entry(title: "日记", date: "2026-09-14", body: "今天跑步")
let summary = Summary([event, missing, zero, journal])
try expect(summary.count == 3 && summary.days == 1 && summary.samples[.duration] == 2 && summary.averageDuration == 16 && summary.sums[.pages] == nil, "statistics distinguish missing, zero, journal and multiple events per day")
var untimed = event; untimed.startedAt = nil; untimed.id = "a"
var timed = event; timed.id = "z"
try expect(ordered([untimed, timed]).map(\.id) == ["z", "a"], "untimed records ordered after timed records")
var invalid = event; invalid.date = "2026-09-18"
try rejects("future dates rejected") { _ = try MarkdownCodec.validated(invalid, activities: initial.activities, now: now) }
invalid = event; invalid.startedAt = "2026-09-12T18:00:00Z"
try rejects("timestamp/day mismatch rejected") { _ = try MarkdownCodec.validated(invalid, activities: initial.activities, now: now) }
invalid = event; invalid.metrics = [.pages: 3]
try rejects("unsupported activity metrics rejected") { _ = try MarkdownCodec.validated(invalid, activities: initial.activities, now: now) }
invalid = journal; invalid.activityID = "running"
try rejects("journal cannot carry an activity") { _ = try MarkdownCodec.validated(invalid, activities: initial.activities, now: now) }
let raw = try MarkdownCodec.encode(event)
try rejects("unknown YAML fields rejected") { _ = try MarkdownCodec.entry(raw.replacingOccurrences(of: "schema_version:", with: "extra: true\nschema_version:"), activities: initial.activities, now: now) }
try rejects("duplicate YAML fields rejected") { _ = try MarkdownCodec.entry(raw.replacingOccurrences(of: "schema_version:", with: "title: duplicate\nschema_version:"), activities: initial.activities, now: now) }
let duplicateMetric = raw.replacingOccurrences(of: "  duration_min:", with: "  duration_min: 7\n  duration_min:")
try rejects("duplicate nested YAML fields rejected") { _ = try MarkdownCodec.entry(duplicateMetric, activities: initial.activities, now: now) }
try rejects("quoted numeric metric rejected") { _ = try MarkdownCodec.entry(raw.replacingOccurrences(of: "(?m)^  duration_min:.*$", with: "  duration_min: '32'", options: .regularExpression), activities: initial.activities, now: now) }
let core12 = raw.replacingOccurrences(of: "(?m)^title:.*$", with: "title: yes", options: .regularExpression)
try expect(try MarkdownCodec.entry(core12, activities: initial.activities, now: now).title == "yes", "YAML 1.2 yes remains a string")
for (literal, expected) in [("012", 12.0), ("0x20", 32.0), ("0o40", 32.0), ("1e2", 100.0)] {
    let yaml = raw.replacingOccurrences(of: "(?m)^  duration_min:.*$", with: "  duration_min: " + literal, options: .regularExpression)
    try expect(try MarkdownCodec.entry(yaml, activities: initial.activities, now: now).metrics?[.duration] == expected, "YAML 1.2 numeric literal \(literal)")
}
let sexagesimal = raw.replacingOccurrences(of: "(?m)^  duration_min:.*$", with: "  duration_min: 1:20", options: .regularExpression)
try rejects("YAML 1.1 sexagesimal is not accepted as a metric") { _ = try MarkdownCodec.entry(sexagesimal, activities: initial.activities, now: now) }
invalid = event; invalid.id = "10000000-0000-0000-0000-000000000001"
try rejects("UUID variant matches the web validator") { _ = try MarkdownCodec.validated(invalid, activities: initial.activities, now: now) }
try rejects("invalid YAML does not become an empty record") { _ = try MarkdownCodec.entry("---\n: [broken\n---\n", activities: initial.activities, now: now) }
try rejects("boolean settings version rejected") { try MarkdownCodec.validateSettings(Data("{\"schema_version\":true,\"timezone\":\"Asia/Shanghai\",\"week_starts_on\":1}".utf8)) }
try Data(raw.utf8).write(to: root.appendingPathComponent("entries/z-duplicate.md"))
try Data("---\ninvalid: [\n---\n".utf8).write(to: root.appendingPathComponent("entries/bad.md"))
let issues = try await repository.snapshot(now: now)
try expect(issues.issues.count == 2 && issues.entries.count == 1, "malformed and duplicate records produce located issues without hiding good records")
try expect(issues.issues.contains { $0.message.contains("重复") }, "duplicate IDs reported explicitly")
let args = CommandLine.arguments
let fixtures = URL(fileURLWithPath: args.count > 1 ? args[1] : "../examples/content")
let sample = try await JournalRepository(directory: fixtures).snapshot(now: now)
try expect(sample.entries.count == 8 && sample.activities.count == 3 && sample.issues.isEmpty && sample.isDemo, "all eight original repository examples read unchanged")
let png = try Data(contentsOf: fixtures.appendingPathComponent("assets/00000000-0000-4000-8000-000000000002/demo.png"))
let reference = try await repository.importImage(png, entryID: id)
let image = try await repository.imageData(reference)
try expect(image == png, "image bytes survive validation, import and reload")
try await rejectsAsync("forged image rejected") { _ = try await repository.importImage(Data("not an image".utf8), entryID: id) }
try await rejectsAsync("oversized image rejected") { _ = try await repository.importImage(Data(count: 10 * 1024 * 1024 + 1), entryID: id) }
try await rejectsAsync("image traversal rejected") { _ = try await repository.imageData("../assets/../../settings.json") }
let outside = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: outside, withIntermediateDirectories: false)
defer { do { try fm.removeItem(at: outside) } catch { fputs("Cleanup failed: \(error)\n", stderr) } }
let escapedID = "20000000-0000-4000-8000-000000000001"
try fm.createSymbolicLink(at: root.appendingPathComponent("assets/" + escapedID), withDestinationURL: outside)
try await rejectsAsync("symlink cannot redirect uploaded images outside assets") { _ = try await repository.importImage(png, entryID: escapedID) }
try expect(try fm.contentsOfDirectory(atPath: outside.path).isEmpty, "outside directory remains untouched")
try fm.removeItem(at: entryFile)
let deleted = try await repository.snapshot(now: now)
try expect(deleted.entries.isEmpty, "external deletion appears on refresh")
try await rejectsAsync("editing externally deleted file fails explicitly") { _ = try await repository.save(updatedSaved, now: now) }
if args.count > 2 {
    let export = URL(fileURLWithPath: args[2])
    try fm.createDirectory(at: export, withIntermediateDirectories: true)
    try Data(raw.utf8).write(to: export.appendingPathComponent("native-entry.md"))
}
if args.count > 3 {
    let web = try String(contentsOfFile: args[3], encoding: .utf8)
    let roundtrip = try MarkdownCodec.entry(web, activities: initial.activities, now: now)
    try expect(roundtrip.title == event.title && roundtrip.metrics == event.metrics && roundtrip.body.hasSuffix(event.body), "web-written Markdown roundtrips back into native reader")
}
print("\n\(passed) checks passed. Temporary fixtures only; no personal content modified.")
