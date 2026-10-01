import SwiftUI
import AppKit
import JournalCore

struct ActivityEditRequest: Identifiable {
    let id = UUID()
    let activity: Activity?
}
struct ActivityEditor: View {
    @ObservedObject var store: JournalStore
    let request: ActivityEditRequest
    @State private var name: String
    @State private var icon: String
    @State private var color: Color
    @State private var metrics: Set<Metric>
    @State private var description: String
    @State private var error: String?
    @State private var discard = false
    private let id: String
    private let icons = ["🏃", "🏸", "📖", "🏊", "🚴", "🧘", "🏋️", "🎨", "🎹", "🚶", "✍️", "✨"]
    init(store: JournalStore, request: ActivityEditRequest) {
        self.store = store; self.request = request
        id = request.activity?.id ?? "activity-" + UUID().uuidString.lowercased()
        _name = State(initialValue: request.activity?.name ?? "")
        _icon = State(initialValue: request.activity?.icon ?? "✨")
        _color = State(initialValue: Color(hex: request.activity?.color ?? "#3D8060"))
        _metrics = State(initialValue: Set(request.activity?.metrics ?? [.duration]))
        _description = State(initialValue: request.activity?.body ?? "")
    }
    private var used: Set<Metric> {
        Set(store.snapshot.entries.filter { $0.activityID == id }.flatMap { $0.metrics?.keys.map { $0 } ?? [] })
    }
    private var changed: Bool {
        name != (request.activity?.name ?? "") || icon != (request.activity?.icon ?? "✨")
        || colorHex != (request.activity?.color ?? "#3D8060").uppercased()
        || metrics != Set(request.activity?.metrics ?? [.duration]) || description != (request.activity?.body ?? "")
    }
    private var colorHex: String {
        let rgb = NSColor(color).usingColorSpace(.deviceRGB)!
        return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button("取消") { if changed { discard = true } else { store.activityEditing = nil } }.keyboardShortcut(.cancelAction)
                Spacer()
                Text(request.activity == nil ? "新建活动" : "编辑活动").font(.headline)
                Spacer()
                Button("保存活动") { Task { await save() } }.buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || icon.isEmpty || store.busy)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            Form {
                TextField("名称", text: $name)
                HStack {
                    TextField("图标", text: $icon).frame(width: 110)
                    Picker("常用图标", selection: $icon) {
                        ForEach(Array(Set(icons + [icon])).sorted(), id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 85)
                    Spacer()
                    ColorPicker("颜色", selection: $color, supportsOpacity: false)
                }
                Section("记录哪些指标") {
                    ForEach(Metric.allCases, id: \.self) { metric in
                        Toggle(metric.title + " / " + metric.unit, isOn: Binding(
                            get: { metrics.contains(metric) },
                            set: { if $0 { metrics.insert(metric) } else { metrics.remove(metric) } }))
                            .disabled(used.contains(metric))
                    }
                    Text("已有记录使用的指标会保留。新增指标不影响旧记录；所有指标都可以选填。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("活动说明（可选）") {
                    TextEditor(text: $description).frame(minHeight: 80)
                }
            }.formStyle(.grouped)
        }.padding(22).frame(minWidth: 490, idealWidth: 550, minHeight: 500, idealHeight: 570)
            .interactiveDismissDisabled()
            .confirmationDialog("放弃未保存的活动修改？", isPresented: $discard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { store.activityEditing = nil }
                Button("继续编辑", role: .cancel) { }
            }
    }
    private func save() async {
        do {
            let value = Activity(id: id, name: name, icon: icon, color: colorHex, metrics: Metric.allCases.filter { metrics.contains($0) },
                                 body: description, hash: request.activity?.hash)
            try await store.saveActivity(value)
        } catch { self.error = error.localizedDescription }
    }
}
struct ActivityActions: View {
    @ObservedObject var store: JournalStore
    let activity: Activity
    var body: some View {
        Menu {
            Button("编辑活动", systemImage: "pencil") { store.editActivity(activity) }
            Button(store.snapshot.archivedActivityIDs.contains(activity.id) ? "取消归档" : "归档，保留历史", systemImage: "archivebox") {
                Task { await store.setArchived(activity, !store.snapshot.archivedActivityIDs.contains(activity.id)) }
            }
            Divider()
            Button("删除活动…", systemImage: "trash", role: .destructive) { store.deletingActivity = activity }
        } label: { Label("管理活动", systemImage: "ellipsis.circle") }
            .disabled(store.busy || store.hasEditor)
    }
}
struct TrashScreen: View {
    @ObservedObject var store: JournalStore
    @State private var selected: TrashItem?
    @State private var deleting: TrashItem?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeading(title: "回收站", subtitle: "删除的内容可以恢复；这里不会自动清空。图片仍可在恢复后读取。")
                if store.snapshot.trash.isEmpty { ContentUnavailableView("回收站为空", systemImage: "trash") }
                ForEach(store.snapshot.trash) { item in
                    Paper {
                        HStack(spacing: 16) {
                            Image(systemName: item.kind == "activity" ? "square.grid.2x2" : item.kind == "images" ? "photo" : "doc.text").font(.title2).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title).font(.headline)
                                Text(item.deletedAt.formatted(date: .abbreviated, time: .shortened) + (item.recordCount > 0 ? " · \(item.recordCount) 条记录" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("查看") { selected = item }
                            Button("恢复") { Task { await store.restoreTrash(item) } }.disabled(store.busy)
                            Menu {
                                Button("永久删除…", role: .destructive) { deleting = item }
                            } label: { Image(systemName: "ellipsis") }.disabled(store.busy)
                        }
                    }
                }
            }.padding(26)
        }
        .sheet(item: $selected) { item in TrashPreview(store: store, item: item) { selected = nil } }
        .confirmationDialog("永久删除后无法恢复", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let item = deleting {
                Button("永久删除“\(item.title)”", role: .destructive) { Task { await store.deleteTrash(item) }; deleting = nil }
            }
            Button("取消", role: .cancel) { deleting = nil }
        }
    }
}
struct TrashPreview: View {
    @ObservedObject var store: JournalStore
    let item: TrashItem
    let close: () -> Void
    @State private var entries: [Entry] = []
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(item.title).font(.title2.bold()); Spacer(); Button("关闭") { close() }.keyboardShortcut(.cancelAction) }
            if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            ScrollView {
                if let repository = store.repository {
                    if item.kind == "images" {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 16) {
                            ForEach(item.files, id: \.path) { file in TrashedImage(repository: repository, item: item, path: file.path) }
                        }
                    } else if entries.isEmpty && error == nil {
                        Text(item.kind == "activity" ? "此活动没有历史记录，可以恢复活动定义。" : "正在读取…").foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(entries) { entry in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(entry.title).font(.headline); Text(entry.date).font(.caption).foregroundStyle(.secondary)
                                    if let cover = entry.cover {
                                        JournalImage(repository: repository, url: URL(string: cover, relativeTo: JournalMarkdown.imageBase)?.absoluteURL, revision: store.revision)
                                    }
                                    JournalMarkdown(text: entry.body, repository: repository, revision: store.revision)
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }.padding(24).frame(minWidth: 600, idealWidth: 750, minHeight: 420, idealHeight: 620)
        .task {
            do { if let repository = store.repository { entries = try await repository.trashedEntries(item) } }
            catch { self.error = error.localizedDescription }
        }
    }
}
struct TrashedImage: View {
    let repository: JournalRepository
    let item: TrashItem
    let path: String
    @State private var image: NSImage?
    @State private var error: String?
    var body: some View {
        VStack {
            if let image { Image(nsImage: image).resizable().scaledToFit().frame(height: 150) }
            else if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            else { ProgressView() }
            Text(URL(fileURLWithPath: path).lastPathComponent).font(.caption).lineLimit(1)
        }.task {
            do {
                let bytes = try await repository.trashedImageData(item, path: path)
                guard let value = NSImage(data: bytes) else { throw JournalError("图片无法解码") }
                image = value
            } catch { self.error = error.localizedDescription }
        }
    }
}
struct ImageCleanupScreen: View {
    @ObservedObject var store: JournalStore
    @State private var references: [String] = []
    @State private var selected = Set<String>()
    @State private var error: String?
    @State private var loading = true
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("清理未使用图片").font(.title2.bold()); Spacer(); Button("关闭") { store.showImageCleanup = false }.keyboardShortcut(.cancelAction) }
            Text("检查日记、回收站和本机草稿的引用。所选图片会移入回收站，可以恢复。").foregroundStyle(.secondary)
            if loading { ProgressView("检查图片引用…") }
            if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            if !loading && error == nil && references.isEmpty { ContentUnavailableView("没有未使用图片", systemImage: "photo.on.rectangle") }
            ScrollView {
                if let repository = store.repository {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 16) {
                        ForEach(references, id: \.self) { reference in
                            VStack {
                                JournalImage(repository: repository, url: URL(string: reference, relativeTo: JournalMarkdown.imageBase)?.absoluteURL, revision: store.revision).frame(height: 100)
                                Toggle("选择", isOn: Binding(get: { selected.contains(reference) }, set: { if $0 { selected.insert(reference) } else { selected.remove(reference) } })).font(.caption)
                            }.padding(10).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            HStack {
                Button("全选") { selected = Set(references) }.disabled(references.isEmpty)
                Button("取消全选") { selected = [] }
                Spacer()
                Button("移入回收站（\(selected.count) 张）", role: .destructive) { confirm = true }.disabled(selected.isEmpty || store.busy)
            }
        }.padding(24).frame(minWidth: 600, idealWidth: 750, minHeight: 430, idealHeight: 620)
        .task {
            do { references = try await store.repository!.unreferencedImages(protected: store.draftImageReferences) }
            catch { self.error = error.localizedDescription }
            loading = false
        }
        .confirmationDialog("将 \(selected.count) 张未使用图片移入回收站？", isPresented: $confirm, titleVisibility: .visible) {
            Button("移入回收站", role: .destructive) {
                Task { await store.cleanImages(selected.sorted()); store.showImageCleanup = false }
            }
            Button("取消", role: .cancel) { }
        }
    }
}
struct DraftsScreen: View {
    @ObservedObject var store: JournalStore
    @State private var removing: EditorDraft?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeading(title: "本机草稿", subtitle: "未完成的编辑留在这台 Mac，保存后才写入日记库。")
                if store.drafts.isEmpty { ContentUnavailableView("没有未完成的草稿", systemImage: "doc.badge.clock") }
                ForEach(store.drafts) { draft in
                    Paper {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(draft.entry.title.isEmpty ? "未命名记录" : draft.entry.title).font(.headline)
                                Text(draft.entry.date + " · " + draft.updatedAt.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                Text(JournalText.excerpt(draft.entry.body)).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Button("继续编辑") { store.resumeDraft(draft) }
                            Button("丢弃…", role: .destructive) { removing = draft }
                        }
                    }
                }
            }.padding(26)
        }.confirmationDialog("丢弃这份本机草稿？已保存的记录不受影响。", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            if let draft = removing { Button("丢弃草稿", role: .destructive) { store.discardDraft(draft); removing = nil } }
            Button("取消", role: .cancel) { removing = nil }
        }
    }
}
