import SwiftUI
import AppKit
import JournalCore

@main
struct JournalApp: App {
    @StateObject private var store = JournalStore()
    @NSApplicationDelegateAdaptor(JournalAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        Window("日常", id: "journal") {
            JournalRoot(store: store)
                .frame(minWidth: 900, minHeight: 600)
                .tint(Color(hex: "#3D8060"))
                .task { delegate.store = store; await store.restore() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh() } } }
        }
        .defaultSize(width: 1340, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建记录") { store.newEntry() }.keyboardShortcut("n").disabled(!store.loaded || store.hasEditor)
                Button("新建活动…") { store.newActivity() }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(!store.loaded || store.hasEditor)
                Button("打开日记库…") { store.choose(create: false) }.keyboardShortcut("o").disabled(store.hasEditor)
                Button("新建日记库…") { store.choose(create: true) }.disabled(store.hasEditor)
            }
            CommandGroup(after: .newItem) {
                Button("刷新日记库") { Task { await store.refresh() } }.keyboardShortcut("r").disabled(store.busy)
                Button("在 Finder 中显示日记库") { store.reveal() }
            }
            CommandGroup(after: .textEditing) {
                Button("搜索记录") { store.selection = "search" }.keyboardShortcut("f", modifiers: [.command, .shift]).disabled(!store.loaded || store.hasEditor)
            }
        }
    }
}

@MainActor
final class JournalAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: JournalStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if store?.busy == true { return .terminateCancel }
        if store?.editing != nil {
            do { try store?.flushDraft(); return .terminateNow }
            catch {
                let alert = NSAlert(); alert.messageText = "草稿未能保存"
                alert.informativeText = error.localizedDescription; alert.addButton(withTitle: "返回编辑")
                alert.runModal(); return .terminateCancel
            }
        }
        guard store?.activityEditing != nil else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "正在编辑活动"
        alert.informativeText = "退出会丢弃尚未保存的活动设置。"
        alert.addButton(withTitle: "继续编辑"); alert.addButton(withTitle: "丢弃并退出")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    static let journalGreen = Color(hex: "#3D8060")
}

struct JournalRoot: View {
    @ObservedObject var store: JournalStore
    @State private var showIssues = false
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "book.closed.fill").font(.title).foregroundStyle(Color.journalGreen)
                    VStack(alignment: .leading) { Text("日常").font(.title2.bold()); Text("留住每一天").font(.caption).foregroundStyle(.secondary) }
                }.padding(22)
                List(selection: $store.selection) {
                    Section("回顾") {
                        Label("月历", systemImage: "calendar").tag("calendar")
                        Label("七日时间轴", systemImage: "clock").tag("timeline")
                        Label("活动", systemImage: "square.grid.2x2").tag("activities")
                        Label("全部记录", systemImage: "books.vertical").tag("history")
                        Label("搜索", systemImage: "magnifyingglass").tag("search")
                        Label("本机草稿 · \(store.drafts.count)", systemImage: "doc.badge.clock").tag("drafts")
                        Label("回收站 · \(store.snapshot.trash.count)", systemImage: "trash").tag("trash")
                    }
                    Section("我的活动") {
                        ForEach(store.snapshot.activeActivities) { activity in
                            Text("\(activity.icon)  \(activity.name)").tag("activity:" + activity.id)
                                .contextMenu { ActivityActions(store: store, activity: activity) }
                        }
                        Button("新建活动", systemImage: "plus") { store.newActivity() }.disabled(!store.loaded || store.busy)
                    }
                    if !store.snapshot.archivedActivityIDs.isEmpty {
                        Section("已归档") {
                            ForEach(store.snapshot.activities.filter { store.snapshot.archivedActivityIDs.contains($0.id) }) { activity in
                                Text("\(activity.icon)  \(activity.name)").foregroundStyle(.secondary).tag("activity:" + activity.id)
                                    .contextMenu { ActivityActions(store: store, activity: activity) }
                            }
                        }
                    }
                }.listStyle(.sidebar)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    if let directory = store.directory {
                        Label(directory.lastPathComponent, systemImage: "folder").font(.caption).lineLimit(1)
                        Text(store.status).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    HStack {
                        Button("打开日记库", systemImage: "folder") { store.choose(create: false) }
                            .labelStyle(.iconOnly).help("打开日记库")
                        Button("在 Finder 中显示", systemImage: "arrow.up.forward.square") { store.reveal() }
                            .labelStyle(.iconOnly).disabled(store.directory == nil)
                        Spacer()
                        if store.busy { ProgressView().controlSize(.small) }
                    }.buttonStyle(.borderless)
                }.padding(18)
            }.navigationSplitViewColumnWidth(min: 185, ideal: 205, max: 250)
        } detail: {
            VStack(spacing: 0) {
                if let error = store.error {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(error).textSelection(.enabled)
                        Spacer()
                        Button("关闭") { store.error = nil }
                    }.font(.callout).padding(12).background(Color.red.opacity(0.10))
                }
                if !store.snapshot.issues.isEmpty {
                    HStack {
                        Label("数据不完整 · \(store.snapshot.issues.count) 个文件问题", systemImage: "exclamationmark.triangle.fill")
                        Spacer(); Button("查看问题") { showIssues = true }
                    }.font(.callout).padding(10).background(Color.orange.opacity(0.12))
                }
                if store.snapshot.isDemo {
                    Text("当前日记库包含示例记录").font(.caption).foregroundStyle(.secondary).padding(6)
                }
                if store.loaded { workspace } else { welcome }
            }
            .toolbar {
                ToolbarItemGroup {
                    if store.loaded {
                        Button("刷新", systemImage: "arrow.clockwise") { Task { await store.refresh() } }.disabled(store.busy)
                        Menu {
                            Button("在 Finder 中显示日记库") { store.reveal() }
                            Button("下载 iCloud 文件") { Task { await store.download() } }
                            Button("清理未使用图片…") { store.showImageCleanup = true }.disabled(store.busy)
                            Button("新建日记库…") { store.choose(create: true) }
                        } label: { Label("日记库", systemImage: "folder") }
                        Button("新建记录", systemImage: "square.and.pencil") { store.newEntry() }.disabled(store.busy)
                        Menu {
                            Button("写日记") { store.newEntry(kind: "journal") }
                            Button("记录活动…") { store.newEntry(kind: "event") }
                            Divider()
                            Button("新建活动…") { store.newActivity() }
                        } label: { Image(systemName: "chevron.down") }.disabled(store.busy)
                    }
                }
            }
        }
        .sheet(item: $store.editing) { entry in EntryEditor(store: store, entry: entry) }
        .sheet(item: $store.activityEditing) { request in ActivityEditor(store: store, request: request) }
        .sheet(isPresented: $store.showImageCleanup) { ImageCleanupScreen(store: store) }
        .confirmationDialog("删除记录后可以在回收站恢复", isPresented: Binding(get: { store.deletingEntry != nil }, set: { if !$0 { store.deletingEntry = nil } }), titleVisibility: .visible) {
            if let entry = store.deletingEntry {
                Button("将“\(entry.title)”移入回收站", role: .destructive) { Task { await store.trash(entry) }; store.deletingEntry = nil }
            }
            Button("取消", role: .cancel) { store.deletingEntry = nil }
        }
        .confirmationDialog(activityDeletionMessage, isPresented: Binding(get: { store.deletingActivity != nil }, set: { if !$0 { store.deletingActivity = nil } }), titleVisibility: .visible) {
            if let activity = store.deletingActivity {
                let count = store.snapshot.entries.filter { $0.activityID == activity.id }.count
                if count > 0 { Button("归档活动，保留历史") { Task { await store.setArchived(activity, true) }; store.deletingActivity = nil } }
                Button(count == 0 ? "将活动移入回收站" : "将活动和 \(count) 条记录移入回收站", role: .destructive) {
                    Task { await store.trash(activity) }; store.deletingActivity = nil
                }
            }
            Button("取消", role: .cancel) { store.deletingActivity = nil }
        }
        .sheet(isPresented: $showIssues) {
            VStack(alignment: .leading, spacing: 16) {
                Text("文件问题").font(.title2.bold())
                Text("以下文件未计入视图和统计。请修正原文件后刷新，不会自动改写原文件。")
                List(store.snapshot.issues) { issue in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(issue.file).bold(); Text(issue.message).foregroundStyle(.secondary)
                        Button("在 Finder 中查看") { store.revealIssue(issue) }
                    }.textSelection(.enabled)
                }
                HStack { Spacer(); Button("完成") { showIssues = false }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 640, height: 430)
        }
        .onChange(of: store.selection) { _, _ in store.selectedEntry = nil }
    }
    private var activityDeletionMessage: String {
        guard let activity = store.deletingActivity else { return "删除活动" }
        let count = store.snapshot.entries.filter { $0.activityID == activity.id }.count
        return count == 0 ? "将“\(activity.name)”移入回收站？" : "“\(activity.name)”有 \(count) 条历史记录。归档可保留历史；一起删除后可在回收站恢复。"
    }
    private var workspace: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 850 {
                HSplitView {
                    screen.frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
                    if let entry = readingEntry {
                        EntryReader(store: store, entry: entry).frame(minWidth: 300, idealWidth: 400, maxWidth: 540, maxHeight: .infinity)
                    }
                }
            } else {
                ZStack {
                    screen.opacity(readingEntry == nil ? 1 : 0).allowsHitTesting(readingEntry == nil)
                    if let entry = readingEntry { EntryReader(store: store, entry: entry).background(Color(nsColor: .windowBackgroundColor)) }
                }
            }
        }
    }
    private var readingEntry: Entry? { store.snapshot.entries.first { $0.id == store.selectedEntry } }
    @ViewBuilder private var screen: some View {
                switch store.selection {
                case "calendar": CalendarScreen(store: store)
                case "timeline": TimelineScreen(store: store)
                case "activities": ActivitiesScreen(store: store)
                case "history": HistoryScreen(store: store, search: false)
                case "search": HistoryScreen(store: store, search: true)
                case "trash": TrashScreen(store: store)
                case "drafts": DraftsScreen(store: store)
                default:
                    if let activity = store.snapshot.activities.first(where: { store.selection == "activity:" + $0.id }) {
                        ActivityScreen(store: store, activity: activity).id(activity.id + store.activityFocusMonth)
                    } else { ContentUnavailableView("活动不存在", systemImage: "folder.badge.questionmark") }
                }
    }
    private var welcome: some View {
        VStack(spacing: 22) {
            Image(systemName: "book.closed").font(.system(size: 58, weight: .light)).foregroundStyle(Color.journalGreen)
            Text("把日子，慢慢记下来。").font(.largeTitle.bold())
            Text("日记、活动和图片，保存在你选择的文件夹里。\n可直接打开已有 Markdown 日记库，也可以从空白开始。")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(6)
            HStack(spacing: 14) {
                Button("打开已有日记库…") { store.choose(create: false) }.controlSize(.large)
                Button("新建日记库…") { store.choose(create: true) }.buttonStyle(.borderedProminent).controlSize(.large)
            }.disabled(store.busy)
            Text("本地文件夹可离线使用；选择 iCloud Drive 文件夹后由系统同步。").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }
}
