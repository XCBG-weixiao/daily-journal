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

// Management operations use a second disposable library.
let managedRoot = fm.temporaryDirectory.appendingPathComponent("DailyJournalManagement-" + UUID().uuidString)
try fm.createDirectory(at: managedRoot, withIntermediateDirectories: false)
defer { do { try fm.removeItem(at: managedRoot) } catch { fputs("Cleanup failed: \(error)\n", stderr) } }
let managed = JournalRepository(directory: managedRoot)
try await managed.initialize()
let createdActivity = try await managed.saveActivity(Activity(id: "swimming", name: "游泳", icon: "🏊", color: "#3D8060", metrics: [.duration, .distance], body: "每次游泳"))
try expect(createdActivity.hash != nil && createdActivity.id == "swimming", "activity created with schema-v1 Markdown and a hash")
try await rejectsAsync("duplicate activity name rejected") {
    _ = try await managed.saveActivity(Activity(id: "swimming-other", name: "游泳", icon: "🏊", color: "#3D8060", metrics: []))
}
try await rejectsAsync("duplicate activity ID refuses overwrite without hash") {
    _ = try await managed.saveActivity(Activity(id: "swimming", name: "另一活动", icon: "🏊", color: "#3D8060", metrics: []))
}
let swimming = try await managed.save(Entry(kind: "event", title: "游泳记录", date: "2026-09-14", activityID: createdActivity.id, metrics: [.duration: 25, .distance: 0.5], body: "泳池训练"))
let renamed = try await managed.saveActivity(Activity(id: createdActivity.id, name: "泳池训练", icon: "🏊", color: "#7963B4", metrics: createdActivity.metrics, body: createdActivity.body, hash: createdActivity.hash))
let renamedData = try await managed.snapshot()
try expect(renamedData.entries.count == 1 && renamedData.entries[0].activityID == renamed.id, "renaming preserves IDs and historical records")
try await rejectsAsync("stale activity editor cannot overwrite a rename") { _ = try await managed.saveActivity(createdActivity) }
try await rejectsAsync("cannot remove metrics used by historical records") {
    _ = try await managed.saveActivity(Activity(id: renamed.id, name: renamed.name, icon: renamed.icon, color: renamed.color, metrics: [.duration], hash: renamed.hash))
}
try await managed.archiveActivity(renamed, archived: true)
let archived = try await JournalRepository(directory: managedRoot).snapshot()
try expect(archived.archivedActivityIDs.contains(renamed.id) && !archived.activeActivities.contains(where: { $0.id == renamed.id }) && archived.entries.count == 1, "archive persists across reopen and retains records and statistics")
try await rejectsAsync("archived activity refuses new records at the storage boundary") {
    _ = try await managed.save(Entry(kind: "event", title: "新记录", date: "2026-09-14", activityID: renamed.id))
}
let archivedEdit = try await managed.save(swimming)
try expect(archivedEdit.hash != nil, "existing archived records remain editable")
try await managed.archiveActivity(renamed, archived: false)
let asyncCheck1 = try await managed.snapshot().activeActivities.contains(where: { $0.id == renamed.id })
try expect(asyncCheck1, "unarchive restores activity picker availability")
try await rejectsAsync("activity with records cannot be deleted as an empty category") { _ = try await managed.trashActivity(renamed, includingEntries: false) }
let imported = try await managed.importImage(png, entryID: swimming.id)
var pictured = swimming; pictured.body += "\n![泳池](\(imported))"; pictured.cover = imported
let picturedSaved = try await managed.save(pictured)
let recordTrash = try await managed.trashEntry(picturedSaved)
let afterTrash = try await managed.snapshot()
try expect(afterTrash.entries.isEmpty && afterTrash.trash.count == 1, "record deletion moves Markdown to visible recoverable trash")
let asyncCheck2 = try await managed.imageData(imported) == png
try expect(asyncCheck2, "deletion retains original images for recovery")
let preview = try await managed.trashedEntries(recordTrash)
try expect(preview.first?.body.hasSuffix(picturedSaved.body) == true && preview.first?.hash == picturedSaved.hash && preview.first?.metrics == picturedSaved.metrics, "trash preview preserves body and metrics")
let asyncCheck3 = try await managed.unreferencedImages().isEmpty
try expect(asyncCheck3, "cleanup protects images referenced by trash")
try await rejectsAsync("metric change also protects trashed records") {
    _ = try await managed.saveActivity(Activity(id: renamed.id, name: renamed.name, icon: renamed.icon, color: renamed.color, metrics: [.duration], hash: renamed.hash))
}
try await managed.restoreTrash(recordTrash)
let restored = try await managed.snapshot()
try expect(restored.entries.first?.hash == picturedSaved.hash && restored.trash.isEmpty, "restoration returns exact original Markdown and removes receipt")
try await rejectsAsync("stale deletion cannot remove a modified record") { _ = try await managed.trashEntry(swimming) }
try await managed.archiveActivity(renamed, archived: true)
try await rejectsAsync("category deletion requires the confirmed current record set") { _ = try await managed.trashActivity(renamed, includingEntries: true) }
let categoryTrash = try await managed.trashActivity(renamed, includingEntries: true, expectedEntries: [picturedSaved.id: picturedSaved.hash!])
let deletedCategory = try await managed.snapshot()
try expect(!deletedCategory.activities.contains(where: { $0.id == renamed.id }) && deletedCategory.entries.isEmpty && deletedCategory.issues.isEmpty && categoryTrash.recordCount == 1, "category deletion moves definition and all related records without orphaning history")
try await managed.restoreTrash(categoryTrash)
let restoredCategory = try await managed.snapshot()
try expect(restoredCategory.activities.contains(where: { $0.id == renamed.id }) && restoredCategory.entries.count == 1 && restoredCategory.archivedActivityIDs.contains(renamed.id), "category restoration restores definition, records, archive state and images")
let collisionTrash = try await managed.trashEntry(restoredCategory.entries[0])
_ = try await managed.save(Entry(id: swimming.id, title: "同 ID 新记录", date: "2026-09-14"))
try await rejectsAsync("restore refuses existing destinations without overwriting") { try await managed.restoreTrash(collisionTrash) }
let asyncCheck4 = try await managed.trashedEntries(collisionTrash).count == 1
try expect(asyncCheck4, "failed restoration leaves the original trash recoverable")
try await managed.permanentlyDeleteTrash(collisionTrash)
let asyncCheck5 = try await managed.snapshot().trash.isEmpty
try expect(asyncCheck5, "explicit permanent deletion removes only the selected trash item")
let orphan = try await managed.importImage(png, entryID: UUID().uuidString.lowercased())
let unused = try await managed.unreferencedImages(protected: [imported])
try expect(unused == [orphan], "cleanup finds orphan images while respecting local draft protection")
let cleaned = try await managed.trashUnusedImages([orphan], protected: [imported])
let asyncCheck6 = try await managed.trashedImageData(cleaned, path: String(orphan.dropFirst(3))) == png
try expect(asyncCheck6, "unused images are moved to recoverable trash with unchanged bytes")
try await managed.restoreTrash(cleaned)
let asyncCheck7 = try await managed.imageData(orphan) == png
try expect(asyncCheck7, "image cleanup can be undone from trash")
let emptyActivity = try await managed.saveActivity(Activity(id: "empty-activity", name: "没有记录的活动", icon: "✨", color: "#3D8060", metrics: []))
let emptyTrash = try await managed.trashActivity(emptyActivity, includingEntries: false)
let emptyDeleted = try await managed.snapshot()
try expect(emptyTrash.recordCount == 0 && !emptyDeleted.activities.contains { $0.id == emptyActivity.id }, "unused activity can be deleted without fabricating records")
try await managed.restoreTrash(emptyTrash)
let emptyRestored = try await managed.snapshot()
try expect(emptyRestored.activities.contains { $0.id == emptyActivity.id && $0.metrics.isEmpty }, "empty activity restoration preserves its original definition")
var filter = EntryFilter(); filter.query = "泳池训练"
var searchOnlyActivity = picturedSaved; searchOnlyActivity.title = "早晨"; searchOnlyActivity.body = "完成训练"
try expect(filter.matches(searchOnlyActivity, activities: [renamed]) && !filter.matches(searchOnlyActivity, activities: []), "search includes activity name when title and body do not contain it")
filter.query = ""; filter.activityID = renamed.id; filter.start = "2026-09-14"; filter.end = "2026-09-14"
try expect(filter.matches(picturedSaved, activities: [renamed]), "activity and inclusive date filters combine correctly")
filter.end = "2026-09-13"
try expect(!filter.matches(picturedSaved, activities: [renamed]), "date filter excludes records outside range")
filter = EntryFilter(); filter.tag = "不存在"
try expect(!filter.matches(picturedSaved, activities: [renamed]), "tag filter requires an exact tag")
var draft = EditorDraft(entry: Entry(kind: "event", date: "2026-09-14", activityID: renamed.id), activities: [renamed])
draft.values[renamed.id] = [.duration: "20", .distance: "0.75"]
draft.activityID = "reading"; draft.values["reading"] = [.pages: "12"]
draft.activityID = renamed.id
let quick = try draft.candidate(activities: [renamed], now: now)
try expect(quick.metrics?[.distance] == 0.75 && quick.title == renamed.name, "activity switches preserve input and quick records use an explicit default title")
let cache = DraftCache(folder: managedRoot.appendingPathComponent("local-drafts"))
try cache.save(draft)
let recoveredDraft = try DraftCache(folder: managedRoot.appendingPathComponent("local-drafts")).all()[0]
try expect(recoveredDraft == draft && recoveredDraft.values["reading"]?[.pages] == "12", "draft survives cache reopen with all activity inputs")
var conflictDraft = EditorDraft(entry: picturedSaved, activities: [renamed]); conflictDraft.entry.body = "未保存正文"
try cache.save(conflictDraft)
let conflictCopy = conflictDraft.copyAsNew()
try expect(conflictCopy.entry.id != conflictDraft.entry.id && conflictCopy.entry.hash == nil && conflictCopy.entry.body == conflictDraft.entry.body, "conflicting draft can be copied to a new UUID without dropping content")
try cache.remove(draft.id)
try expect(try cache.all().count == 1, "discard removes only the selected local draft")
try expect(JournalText.imageReferences("![泳池](\(imported))\n![第二次](\(imported))") == [imported], "image manager deduplicates image references")
try expect(!JournalText.removingImage(imported, from: picturedSaved.body).contains(imported), "removing image markup leaves no duplicate reference")
try expect(JournalText.excerpt("# 今天\n![图片](\(imported))\n**训练**").contains("训练") && !JournalText.excerpt(picturedSaved.body).contains("../assets"), "record excerpts omit Markdown image syntax")
if args.count > 2 {
    // Export the actual managed library for the original web parser to inspect.
    try await managed.archiveActivity(renamed, archived: false)
    _ = try await managed.save(quick)
    let exported = URL(fileURLWithPath: args[2]).appendingPathComponent("native-management")
    if fm.fileExists(atPath: exported.path) { try fm.removeItem(at: exported) }
    try fm.copyItem(at: managedRoot, to: exported)
}
print("\n\(passed) checks passed. Temporary fixtures only; no personal content modified.")
