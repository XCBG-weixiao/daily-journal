import SwiftUI
import AppKit
import UniformTypeIdentifiers
import JournalCore

struct EntryEditor: View {
    @ObservedObject var store: JournalStore
    let entry: Entry
    @State private var draft: EditorDraft
    @StateObject private var textController = EditorTextController()
    @State private var error: String?
    @State private var saving = false
    @State private var uploading = false
    @State private var cancelPrompt = false
    @State private var conflict = false
    @State private var disk: Entry?
    @State private var showDisk = false
    @FocusState private var focusedMetric: Metric?

    init(store: JournalStore, entry: Entry) {
        self.store = store; self.entry = entry
        _draft = State(initialValue: store.resumedDraft ?? EditorDraft(entry: entry, activities: store.snapshot.activeActivities))
    }
    private var chosen: Activity? { store.snapshot.activities.first { $0.id == draft.activityID } }
    private var available: [Activity] {
        store.snapshot.activities.filter { !store.snapshot.archivedActivityIDs.contains($0.id) || $0.id == draft.original.activityID }
    }
    private var references: [String] {
        Array(Set(JournalText.imageReferences(draft.entry.body) + (draft.cover.isEmpty ? [] : [draft.cover]))).sorted()
    }
    private var validation: String? {
        do { _ = try draft.candidate(activities: store.snapshot.activities); return nil }
        catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { cancel() }.keyboardShortcut(.cancelAction).disabled(saving || uploading)
                Spacer()
                Text(entry.hash == nil ? (draft.entry.kind == "event" ? "记录活动" : "写日记") : "编辑记录").font(.headline)
                Spacer()
                Button(saving ? "保存中…" : "保存") { Task { await save(asNew: false) } }
                    .buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command)
                    .disabled(saving || uploading || validation != nil || store.busy)
            }.padding(18)
            Divider()
            if let error {
                VStack(alignment: .leading, spacing: 10) {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                    if conflict {
                        HStack {
                            Button("查看磁盘版本") { Task { await loadDisk() } }
                            Button("另存为新记录") { Task { await save(asNew: true) } }.disabled(saving || uploading)
                            Text("当前内容已保留为本地草稿").foregroundStyle(.secondary)
                        }
                    }
                }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.red.opacity(0.06))
            }
            fields
            if let validation {
                Label(validation, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 10)
            }
            if draft.details {
                detailedEditor
            } else {
                HStack {
                    Button("添加说明、图片和标签", systemImage: "text.badge.plus") { draft.details = true }
                    Spacer()
                    Text("只填指标也可以保存；标题默认使用活动名称。").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
        }
        .frame(minWidth: 760, idealWidth: draft.details ? 980 : 800, maxWidth: 1100,
               minHeight: draft.details ? 540 : 280, idealHeight: draft.details ? 700 : 330)
        .interactiveDismissDisabled()
        .onAppear {
            textController.configure(text: draft.entry.body, changed: { draft.entry.body = $0 })
            store.keepDraft(draft)
            if entry.hash == nil && draft.entry.kind == "event" { focusedMetric = chosen?.metrics.first }
        }
        .onChange(of: draft) { _, value in
            var latest = value; latest.updatedAt = Date(); store.keepDraft(latest)
        }
        .onDisappear { textController.disconnect() }
        .confirmationDialog("如何处理尚未保存的内容？", isPresented: $cancelPrompt, titleVisibility: .visible) {
            Button("保留草稿，稍后继续") { close(keeping: true) }
            Button("放弃修改", role: .destructive) { close(keeping: false) }
            Button("继续编辑", role: .cancel) { }
        }
        .sheet(isPresented: $showDisk) {
            if let disk, let repository = store.repository {
                ConflictReview(draft: draft, disk: disk, activities: store.snapshot.activities, repository: repository, revision: store.revision) { showDisk = false }
            }
        }
    }
    private var fields: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Picker("类型", selection: $draft.entry.kind) {
                    Text("日记").tag("journal"); Text("活动").tag("event")
                }.frame(width: 130)
                if draft.entry.kind == "event" {
                    Picker("活动", selection: $draft.activityID) {
                        ForEach(available) { a in
                            Text(a.icon + " " + a.name + (store.snapshot.archivedActivityIDs.contains(a.id) ? "（已归档）" : "")).tag(a.id)
                        }
                    }.frame(minWidth: 140, maxWidth: 200)
                }
                DatePicker("日期", selection: Binding(
                    get: { JournalDate.parse(draft.entry.date)! },
                    set: { draft.entry.date = JournalDate.today($0) }), in: ...Date(), displayedComponents: .date)
                    .environment(\.timeZone, JournalDate.calendar.timeZone).environment(\.calendar, JournalDate.calendar).frame(width: 190)
                TextField("时间 HH:mm（可选）", text: $draft.time).textFieldStyle(.roundedBorder).frame(width: 155)
                Spacer(minLength: 0)
            }
            if draft.entry.kind == "event" {
                if let chosen {
                    HStack(spacing: 16) {
                        ForEach(chosen.metrics, id: \.self) { metric in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(metric.title + " / " + metric.unit).font(.caption).foregroundStyle(.secondary)
                                TextField("未填写", text: Binding(
                                    get: { draft.values[draft.activityID]?[metric] ?? "" },
                                    set: { draft.values[draft.activityID, default: [:]][metric] = $0 }))
                                    .textFieldStyle(.roundedBorder).frame(width: 110).focused($focusedMetric, equals: metric)
                            }
                        }
                        Spacer()
                    }
                } else {
                    Text("还没有活动。先取消此记录，在“我的活动”旁点击 + 创建。").font(.caption).foregroundStyle(.orange)
                }
            }
            TextField(draft.entry.kind == "event" ? "\(chosen?.name ?? "活动")（默认标题，可修改）" : "\(draft.entry.date) 日记（默认标题，可修改）",
                      text: $draft.entry.title)
                .font(.title2.weight(.semibold)).textFieldStyle(.plain).accessibilityLabel("标题")
        }.padding(20)
    }
    private var detailedEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("编辑模式", selection: $draft.mode) {
                    Text("Markdown").tag("write"); Text("分栏").tag("split"); Text("预览").tag("preview")
                }.pickerStyle(.segmented).frame(width: 255)
                Spacer()
                Button(uploading ? "添加中…" : "添加图片", systemImage: "photo.badge.plus") { chooseImages() }
                    .disabled(uploading || saving)
            }.padding(.horizontal, 20).padding(.bottom, 12)
            Divider()
            HSplitView {
                if draft.mode != "preview" {
                    MarkdownTextEditor(controller: textController, text: $draft.entry.body,
                                       importFiles: { urls in Task { await importImages(urls) } },
                                       importBytes: { bytes in Task { await importImageBytes(bytes, alt: "粘贴的图片") } })
                        .frame(minWidth: draft.mode == "split" ? 280 : 600, maxWidth: .infinity, maxHeight: .infinity)
                }
                if draft.mode != "write", let repository = store.repository {
                    ScrollView {
                        JournalMarkdown(text: draft.entry.body, repository: repository, revision: store.revision)
                            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(minWidth: draft.mode == "split" ? 280 : 600, maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(minHeight: 190, maxHeight: .infinity)
            Divider()
            if !references.isEmpty, let repository = store.repository {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(references, id: \.self) { reference in
                            VStack(spacing: 5) {
                                JournalImage(repository: repository,
                                             url: URL(string: reference, relativeTo: JournalMarkdown.imageBase)?.absoluteURL,
                                             revision: store.revision).frame(width: 74, height: 55).clipped()
                                Menu {
                                    Button(draft.cover == reference ? "取消封面" : "设为封面") { draft.cover = draft.cover == reference ? "" : reference }
                                    Button("从正文移除") {
                                        let text = JournalText.removingImage(reference, from: draft.entry.body)
                                        textController.replace(text)
                                        if draft.cover == reference { draft.cover = "" }
                                    }
                                } label: { Text(draft.cover == reference ? "封面 ✓" : "图片").font(.caption) }
                            }
                        }
                    }.padding(.horizontal, 18).padding(.vertical, 8)
                }
                Divider()
            }
            HStack {
                Text("标签").font(.caption)
                TextField("用逗号分隔，例如：户外, 公园", text: $draft.tags).textFieldStyle(.roundedBorder)
                Text("可多选图片、拖入或粘贴；每张最多 10 MB。").font(.caption2).foregroundStyle(.secondary)
            }.padding(18)
            Text("编辑内容会保留为本机草稿；保存后写入日记库。").font(.caption2).foregroundStyle(.secondary).padding(.bottom, 12)
        }
    }
    private func save(asNew: Bool) async {
        saving = true; error = nil; conflict = false
        defer { saving = false }
        do {
            var candidate = try draft.candidate(activities: store.snapshot.activities)
            if asNew { candidate.id = UUID().uuidString.lowercased(); candidate.hash = nil }
            try await store.save(candidate)
        } catch {
            self.error = error.localizedDescription; conflict = error is JournalConflict
            do { try store.flushDraft() } catch { self.error = "\(self.error ?? "")\n草稿保存失败：\(error.localizedDescription)" }
        }
    }
    private func cancel() {
        if draft.isModified { cancelPrompt = true } else { close(keeping: false) }
    }
    private func close(keeping: Bool) {
        do { try store.closeEditor(keepingDraft: keeping) } catch { self.error = error.localizedDescription }
    }
    private func loadDisk() async {
        guard let repository = store.repository else { return }
        do {
            let snapshot = try await repository.snapshot()
            guard let latest = snapshot.entries.first(where: { $0.id == entry.id }) else {
                throw JournalError("磁盘记录不存在或未能读取。当前草稿可以另存为新记录。")
            }
            disk = latest; showDisk = true
        } catch { self.error = error.localizedDescription }
    }
    private func chooseImages() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .webP]; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { Task { await importImages(panel.urls) } }
    }
    private func importImages(_ urls: [URL]) async {
        guard !uploading, !saving, let repository = store.repository else { return }
        uploading = true; error = nil
        defer { uploading = false }
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                guard let size, size <= 10 * 1024 * 1024 else { throw JournalError("图片超过 10 MB 或无法读取大小：\(url.lastPathComponent)") }
                let bytes = try Data(contentsOf: url)
                let reference = try await repository.importImage(bytes, entryID: draft.entry.id)
                insertImage(reference, alt: url.deletingPathExtension().lastPathComponent)
            } catch {
                self.error = "\(url.lastPathComponent)：\(error.localizedDescription)"
                if access { url.stopAccessingSecurityScopedResource() }
                break
            }
            if access { url.stopAccessingSecurityScopedResource() }
        }
    }
    private func importImageBytes(_ bytes: Data, alt: String) async {
        guard !uploading, !saving, let repository = store.repository else { return }
        uploading = true; error = nil
        defer { uploading = false }
        do { insertImage(try await repository.importImage(bytes, entryID: draft.entry.id), alt: alt) }
        catch { self.error = error.localizedDescription }
    }
    private func insertImage(_ reference: String, alt: String) {
        let label = alt.replacingOccurrences(of: "[\\[\\]\\\\\\r\\n]", with: "", options: .regularExpression)
        draft.details = true
        draft.mode = "split"
        textController.configure(text: draft.entry.body, changed: { draft.entry.body = $0 })
        textController.insert("\n![\(label)](\(reference))\n")
    }
}

struct ConflictReview: View {
    let draft: EditorDraft
    let disk: Entry
    let activities: [Activity]
    let repository: JournalRepository
    let revision: Int
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("当前草稿与磁盘版本").font(.title2.bold())
            Text("这里只比较内容，关闭不会覆盖任何版本。可以返回编辑器继续修改，或另存为新记录。").foregroundStyle(.secondary)
            HSplitView {
                column("当前草稿", entry: draft.entry, time: draft.time, tags: draft.tags,
                       activityID: draft.entry.kind == "event" ? draft.activityID : nil,
                       metrics: draft.values[draft.activityID] ?? [:], cover: draft.cover)
                column("磁盘版本", entry: disk, time: JournalDate.time(disk.startedAt), tags: (disk.tags ?? []).joined(separator: ", "),
                       activityID: disk.activityID, metrics: (disk.metrics ?? [:]).mapValues { numberLabel($0) }, cover: disk.cover ?? "")
            }
            HStack { Spacer(); Button("返回草稿") { close() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(minWidth: 760, idealWidth: 920, minHeight: 480, idealHeight: 600)
    }
    private func column(_ label: String, entry: Entry, time: String, tags: String, activityID: String?, metrics: [Metric: String], cover: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(label).font(.headline); Text(entry.title).font(.title3)
                Text(entry.date + " · " + time).font(.caption)
                Text(activityID.flatMap { id in activities.first { $0.id == id }?.name } ?? (entry.kind == "journal" ? "日记" : activityID ?? "未选择活动")).font(.callout)
                if entry.kind == "event" {
                    ForEach(Metric.allCases, id: \.self) { metric in
                        if let value = metrics[metric], !value.isEmpty { Text("\(metric.title)：\(value) \(metric.unit)").font(.caption) }
                    }
                }
                Text(tags).font(.caption).foregroundStyle(.secondary)
                if !cover.isEmpty { JournalImage(repository: repository, url: URL(string: cover, relativeTo: JournalMarkdown.imageBase)?.absoluteURL, revision: revision).frame(maxHeight: 140) }
                Divider()
                JournalMarkdown(text: entry.body, repository: repository, revision: revision)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minWidth: 340)
    }
}
