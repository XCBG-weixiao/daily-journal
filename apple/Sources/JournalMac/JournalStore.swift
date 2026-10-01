import SwiftUI
import AppKit
import JournalCore

@MainActor
final class JournalStore: ObservableObject {
    @Published var snapshot = JournalSnapshot()
    @Published var directory: URL?
    @Published var loaded = false
    @Published var busy = false
    @Published var error: String?
    @Published var status = ""
    @Published var selection = "calendar"
    @Published var selectedEntry: String?
    @Published var editing: Entry?
    @Published var activityEditing: ActivityEditRequest?
    @Published var deletingActivity: Activity?
    @Published var deletingEntry: Entry?
    @Published var showImageCleanup = false
    @Published var drafts: [EditorDraft] = []
    @Published var contextDate = JournalDate.today()
    @Published var query = ""
    @Published var activityFocusMonth = String(JournalDate.today().prefix(7))
    @Published var activityFocusDay: String?
    @Published var revision = 0
    private(set) var repository: JournalRepository?
    private var scoped = false
    private var presenter: JournalPresenter?
    private var refreshTask: Task<Void, Never>?
    private let bookmarkKey = "journal.directory"
    private var refreshPending = false
    private var draftCache: DraftCache?
    private var draftTask: Task<Void, Never>?
    private(set) var currentDraft: EditorDraft?
    private(set) var resumedDraft: EditorDraft?
    var hasEditor: Bool { editing != nil || activityEditing != nil }

    func restore() async {
        guard directory == nil else { return }
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            await open(url, create: false)
        } catch { self.error = "无法恢复目录授权，请重新选择日记库。\n" + error.localizedDescription }
    }

    func choose(create: Bool) {
        guard !busy, !hasEditor else { return }
        let panel = NSOpenPanel()
        panel.title = create ? "选择空文件夹，创建日记库" : "打开日记库"
        panel.message = create ? "将在空文件夹创建 Markdown 日记库和跑步、羽毛球、阅读活动。" : "选择包含 settings.json、entries、activities 和 assets 的文件夹。"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = create
        panel.prompt = create ? "创建日记库" : "打开"
        if panel.runModal() == .OK, let url = panel.url { Task { await open(url, create: create) } }
    }

    private func open(_ url: URL, create: Bool, persist: Bool = true) async {
        guard !busy else { return }
        busy = true
        defer { finish() }
        let acquired = url.startAccessingSecurityScopedResource()
        let newRepository = JournalRepository(directory: url)
        do {
            if create { try await newRepository.initialize() }
            let data = try await newRepository.snapshot()
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let cache = DraftCache(folder: support.appendingPathComponent("DailyJournal/drafts/" + MarkdownCodec.hash(url.standardizedFileURL.path)))
            if persist {
                let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            }
            if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
            if scoped { directory?.stopAccessingSecurityScopedResource() }
            directory = url; scoped = acquired; repository = newRepository
            snapshot = data; loaded = true; error = nil; selectedEntry = nil
            selection = "calendar"; contextDate = JournalDate.today()
            draftCache = cache
            do { drafts = try cache.all() }
            catch { self.error = "草稿读取失败：\(error.localizedDescription)"; drafts = [] }
            revision += 1; status = "已读取 \(data.entries.count) 条记录"
            let watcher = JournalPresenter(url: url) { [weak self] in
                Task { @MainActor in self?.scheduleRefresh() }
            }
            presenter = watcher; NSFileCoordinator.addFilePresenter(watcher)
        } catch {
            if acquired { url.stopAccessingSecurityScopedResource() }
            self.error = error.localizedDescription
        }
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await self?.refresh()
        }
    }
    func refresh() async {
        guard let repository else { return }
        guard !busy else { refreshPending = true; return }
        busy = true
        defer { finish() }
        do {
            let data = try await repository.snapshot()
            snapshot = data; error = nil; loaded = true; revision += 1
            if let id = selectedEntry, !data.entries.contains(where: { $0.id == id }) { selectedEntry = nil }
            if selection.hasPrefix("activity:"), !data.activities.contains(where: { "activity:" + $0.id == selection }) { selection = "activities" }
            status = "已刷新 · \(Date().formatted(date: .omitted, time: .shortened))"
        } catch {
            loaded = false; snapshot = JournalSnapshot(); selectedEntry = nil
            self.error = error.localizedDescription
        }
    }
    func newEntry(date: String? = nil, activity: String? = nil, kind: String? = nil) {
        guard loaded, !busy, !hasEditor else { return }
        let chosen = kind == "journal" ? nil : activity ?? (selection.hasPrefix("activity:") ? String(selection.dropFirst(9)) : kind == "event" ? snapshot.activeActivities.first?.id : nil)
        if kind == "event" && chosen == nil { error = "请先在“我的活动”旁点击 + 新建活动"; return }
        if let chosen, snapshot.archivedActivityIDs.contains(chosen) { error = "此活动已归档，请先取消归档后添加记录"; return }
        resumedDraft = nil; currentDraft = nil
        let contextual = ["calendar", "timeline"].contains(selection) || selection.hasPrefix("activity:")
        editing = Entry(kind: chosen == nil ? "journal" : "event", date: min(date ?? (contextual ? contextDate : JournalDate.today()), JournalDate.today()), activityID: chosen)
    }
    func editEntry(_ entry: Entry) {
        guard !busy, !hasEditor else { return }
        if let draft = drafts.first(where: { $0.id == entry.id }) { resumeDraft(draft); return }
        resumedDraft = nil; currentDraft = nil; editing = entry
    }
    func save(_ entry: Entry) async throws {
        guard !busy, let repository else { throw JournalError("日记库暂不可用，请稍后重试") }
        busy = true
        defer { finish() }
        let saved = try await repository.save(entry)
        // The file is already committed. Surface a refresh failure separately instead of asking to save twice.
        editing = nil; selectedEntry = saved.id
        draftTask?.cancel()
        var cleanupError: String?
        do { try draftCache?.remove(currentDraft?.id ?? entry.id); drafts = try draftCache?.all() ?? [] }
        catch { cleanupError = "记录已保存，但草稿清理失败：\(error.localizedDescription)" }
        currentDraft = nil; resumedDraft = nil
        do { snapshot = try await repository.snapshot(); loaded = true; revision += 1; error = cleanupError }
        catch { self.error = [cleanupError, "文件已保存，但重新读取失败：\(error.localizedDescription)"].compactMap { $0 }.joined(separator: "\n") }
        status = "已保存到本机 · " + saved.title
    }
    func download() async {
        guard !busy, let repository else { return }
        busy = true
        defer { finish() }
        do { try await repository.requestDownload(); status = "已请求系统下载，请稍后刷新" }
        catch { self.error = error.localizedDescription }
    }
    func reveal() { if let directory { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path) } }
    func revealIssue(_ issue: ContentIssue) {
        guard let directory else { return }
        let file = directory.appendingPathComponent(issue.file)
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }
    func newActivity() {
        guard loaded, !busy, !hasEditor else { return }
        activityEditing = ActivityEditRequest(activity: nil)
    }
    func editActivity(_ activity: Activity) {
        guard !busy, !hasEditor else { return }
        activityEditing = ActivityEditRequest(activity: activity)
    }
    func saveActivity(_ activity: Activity) async throws {
        guard !busy, let repository else { throw JournalError("日记库暂不可用") }
        busy = true; defer { finish() }
        _ = try await repository.saveActivity(activity)
        activityEditing = nil
        await reloadAfterWrite("已保存活动 · " + activity.name)
    }
    func setArchived(_ activity: Activity, _ archived: Bool) async {
        await manage(status: archived ? "已归档，历史记录已保留" : "已取消归档") { repository in
            try await repository.archiveActivity(activity, archived: archived)
        }
    }
    func trash(_ entry: Entry) async {
        await manage(status: "记录已移入回收站") { repository in _ = try await repository.trashEntry(entry) }
    }
    func trash(_ activity: Activity) async {
        let records = Dictionary(uniqueKeysWithValues: snapshot.entries.filter { $0.activityID == activity.id }.map { ($0.id, $0.hash!) })
        await manage(status: "活动及其记录已移入回收站") { repository in _ = try await repository.trashActivity(activity, includingEntries: true, expectedEntries: records) }
    }
    func restoreTrash(_ item: TrashItem) async {
        await manage(status: "已恢复 · " + item.title) { repository in try await repository.restoreTrash(item) }
    }
    func deleteTrash(_ item: TrashItem) async {
        await manage(status: "已永久删除 · " + item.title) { repository in try await repository.permanentlyDeleteTrash(item) }
    }
    func cleanImages(_ references: [String]) async {
        let protected = draftImageReferences
        await manage(status: "未使用图片已移入回收站") { repository in _ = try await repository.trashUnusedImages(references, protected: protected) }
    }
    var draftImageReferences: Set<String> {
        Set((drafts + (currentDraft.map { [$0] } ?? [])).flatMap { JournalText.imageReferences($0.entry.body) + ($0.cover.isEmpty ? [] : [$0.cover]) })
    }
    private func manage(status: String, operation: (JournalRepository) async throws -> Void) async {
        guard !busy, !hasEditor, let repository else { return }
        busy = true; defer { finish() }
        do { try await operation(repository); await reloadAfterWrite(status) }
        catch { self.error = error.localizedDescription }
    }
    private func reloadAfterWrite(_ message: String) async {
        do {
            snapshot = try await repository!.snapshot(); revision += 1; loaded = true; error = nil
            if let id = selectedEntry, !snapshot.entries.contains(where: { $0.id == id }) { selectedEntry = nil }
            if selection.hasPrefix("activity:"), !snapshot.activities.contains(where: { "activity:" + $0.id == selection }) { selection = "activities" }
        } catch { self.error = "操作已保存，但刷新失败：\(error.localizedDescription)" }
        status = message
    }
    func keepDraft(_ draft: EditorDraft) {
        currentDraft = draft
        draftTask?.cancel()
        draftTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            do { try self?.flushDraft() }
            catch { self?.error = "本地草稿保存失败：\(error.localizedDescription)" }
        }
    }
    func flushDraft() throws {
        draftTask?.cancel()
        guard let currentDraft, let draftCache else { return }
        if currentDraft.isModified { try draftCache.save(currentDraft) }
        else { try draftCache.remove(currentDraft.id) }
        drafts = try draftCache.all()
    }
    func closeEditor(keepingDraft: Bool) throws {
        draftTask?.cancel()
        if keepingDraft { try flushDraft() }
        else if let id = editing?.id { try draftCache?.remove(id); drafts = try draftCache?.all() ?? [] }
        editing = nil; currentDraft = nil; resumedDraft = nil
    }
    func resumeDraft(_ draft: EditorDraft) {
        guard loaded, !busy, !hasEditor else { return }
        resumedDraft = draft; currentDraft = draft; editing = draft.original
    }
    func discardDraft(_ draft: EditorDraft) {
        do { try draftCache?.remove(draft.id); drafts = try draftCache?.all() ?? [] }
        catch { self.error = error.localizedDescription }
    }
    private func finish() {
        busy = false
        if refreshPending { refreshPending = false; scheduleRefresh() }
    }
}

final class JournalPresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 1; return q }()
    let changed: () -> Void
    init(url: URL, changed: @escaping () -> Void) { presentedItemURL = url; self.changed = changed }
    func presentedItemDidChange() { changed() }
    func presentedItemDidMove(to newURL: URL) { changed() }
    func presentedSubitemDidChange(at url: URL) { changed() }
    func presentedSubitemDidAppear(at url: URL) { changed() }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { changed() }
    func presentedSubitem(at url: URL, didGain version: NSFileVersion) { changed() }
    func presentedSubitem(at url: URL, didResolve version: NSFileVersion) { changed() }
    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) { changed(); completionHandler(nil) }
    func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping (Error?) -> Void) { changed(); completionHandler(nil) }
}
