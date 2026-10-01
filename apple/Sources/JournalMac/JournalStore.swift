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
    @Published var query = ""
    @Published var activityFocusMonth = String(JournalDate.today().prefix(7))
    @Published var revision = 0
    private(set) var repository: JournalRepository?
    private var scoped = false
    private var presenter: JournalPresenter?
    private var refreshTask: Task<Void, Never>?
    private let bookmarkKey = "journal.directory"
    private var refreshPending = false

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
        guard !busy, editing == nil else { return }
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
            if persist {
                let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            }
            if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
            if scoped { directory?.stopAccessingSecurityScopedResource() }
            directory = url; scoped = acquired; repository = newRepository
            snapshot = data; loaded = true; error = nil; selectedEntry = nil
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
            status = "已刷新 · \(Date().formatted(date: .omitted, time: .shortened))"
        } catch {
            loaded = false; snapshot = JournalSnapshot(); selectedEntry = nil
            self.error = error.localizedDescription
        }
    }
    func newEntry(date: String = JournalDate.today(), activity: String? = nil) {
        guard loaded, !busy else { return }
        editing = Entry(kind: activity == nil ? "journal" : "event", date: date, activityID: activity)
    }
    func save(_ entry: Entry) async throws {
        guard !busy, let repository else { throw JournalError("日记库暂不可用，请稍后重试") }
        busy = true
        defer { finish() }
        let saved = try await repository.save(entry)
        // The file is already committed. Surface a refresh failure separately instead of asking to save twice.
        editing = nil; selectedEntry = saved.id
        do { snapshot = try await repository.snapshot(); loaded = true; revision += 1; error = nil }
        catch { self.error = "文件已保存，但重新读取失败：\(error.localizedDescription)" }
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
