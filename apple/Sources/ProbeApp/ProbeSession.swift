import Foundation
import SwiftUI
#if SWIFT_PACKAGE
import ProbeCore
#endif

@MainActor
final class ProbeSession: ObservableObject {
    @Published var folderName: String?
    @Published var draft = ""
    @Published var snapshot: ProbeSnapshot?
    @Published var initialized = false
    @Published var busy = false
    @Published var errorMessage: String?
    @Published var notice = "选择专门用于验证的空文件夹。"
    private let repository = ProbeRepository()
    private var directory: URL?
    private var presenter: DirectoryPresenter?
    private var refreshRequested = false
    private let bookmarkKey = "daily-journal-probe.directory-bookmark"

    func restore() async {
        guard directory == nil, let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var stale = false
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
            #else
            let options: URL.BookmarkResolutionOptions = [.withoutUI]
            #endif
            let url = try URL(resolvingBookmarkData: data, options: options,
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            await select(url)
        } catch {
            errorMessage = "无法恢复文件夹授权，请重新选择原测试文件夹：\(error.localizedDescription)"
        }
    }

    func select(_ url: URL) async {
        guard !busy else { return }
        busy = true
        defer { finishOperation() }
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "未获得文件夹访问权限，请通过系统文件选择器重新选择。"
            return
        }
        do {
            #if os(macOS)
            let options: URL.BookmarkCreationOptions = [.withSecurityScope]
            #else
            let options: URL.BookmarkCreationOptions = [.minimalBookmark]
            #endif
            let bookmark = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
            if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
            directory?.stopAccessingSecurityScopedResource()
            directory = url
            folderName = url.lastPathComponent
            snapshot = nil
            draft = ""
            initialized = false
            errorMessage = nil
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            let presenter = DirectoryPresenter(url: url) { [weak self] in
                Task { @MainActor in await self?.refresh() }
            }
            self.presenter = presenter
            NSFileCoordinator.addFilePresenter(presenter)
        } catch {
            url.stopAccessingSecurityScopedResource()
            errorMessage = error.localizedDescription
            return
        }
        await load()
        draft = snapshot?.text ?? ""
    }

    func refresh() async {
        guard directory != nil else { return }
        if busy { refreshRequested = true; return }
        busy = true
        defer { finishOperation() }
        await load()
    }

    private func load() async {
        guard let directory else { return }
        do {
            initialized = try await repository.isInitialized(directory)
            snapshot = initialized ? try await repository.read(directory) : nil
            errorMessage = nil
            notice = initialized ? "已读取本机文件。另一台设备是否收到更新，请在另一端确认。" : "空文件夹已授权，请初始化。"
        } catch {
            snapshot = nil
            errorMessage = error.localizedDescription
        }
    }

    func initialize() async {
        guard !busy, let directory else { return }
        busy = true
        defer { finishOperation() }
        do {
            try await repository.initialize(directory)
            await load()
            draft = snapshot?.text ?? ""
        } catch { errorMessage = error.localizedDescription }
    }

    func save() async {
        guard !busy, let directory else { return }
        busy = true
        defer { finishOperation() }
        do {
            try await repository.save(draft, in: directory)
            await load()
            if errorMessage == nil { notice = "已保存到本机。iCloud 上传状态由系统报告。" }
        } catch { errorMessage = error.localizedDescription }
    }

    func download() async {
        guard !busy, let directory else { return }
        busy = true
        defer { finishOperation() }
        do {
            try await repository.requestDownload(directory)
            notice = "已请求系统下载，请稍后刷新。"
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func finishOperation() {
        busy = false
        if refreshRequested {
            refreshRequested = false
            Task { await refresh() }
        }
    }
}
