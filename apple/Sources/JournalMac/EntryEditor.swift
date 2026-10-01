import SwiftUI
import AppKit
import UniformTypeIdentifiers
import JournalCore

struct EntryEditor: View {
    @ObservedObject var store: JournalStore
    let entry: Entry
    @State private var draft: Entry
    @State private var time: String
    @State private var tags: String
    @State private var cover: String
    @State private var values: [Metric: String]
    @State private var activity: String
    @State private var mode = "split"
    @State private var error: String?
    @State private var saving = false
    @State private var uploading = false
    @State private var insertion: TextInsertion?
    @State private var discard = false
    init(store: JournalStore, entry: Entry) {
        self.store = store; self.entry = entry
        _draft = State(initialValue: entry)
        _time = State(initialValue: entry.startedAt == nil ? "" : JournalDate.time(entry.startedAt))
        _tags = State(initialValue: entry.tags?.joined(separator: ", ") ?? "")
        _cover = State(initialValue: entry.cover ?? "")
        _values = State(initialValue: Dictionary(uniqueKeysWithValues: (entry.metrics ?? [:]).map { ($0.key, String($0.value)) }))
        _activity = State(initialValue: entry.activityID ?? store.snapshot.activities.first?.id ?? "")
    }
    private var chosen: Activity? { store.snapshot.activities.first { $0.id == activity } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { cancel() }.keyboardShortcut(.cancelAction).disabled(saving || uploading)
                Spacer()
                Text(entry.hash == nil ? "记录此刻" : "编辑记录").font(.headline)
                Spacer()
                Button(saving ? "保存中…" : "保存记录") { Task { await save() } }
                    .buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command).disabled(saving || uploading)
            }.padding(18)
            Divider()
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.red.opacity(0.06)) }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    Picker("类型", selection: $draft.kind) { Text("日记").tag("journal"); Text("活动").tag("event") }.frame(width: 135)
                    if draft.kind == "event" {
                        Picker("活动", selection: $activity) { ForEach(store.snapshot.activities) { a in Text(a.icon + " " + a.name).tag(a.id) } }.frame(width: 160)
                    }
                    DatePicker("日期", selection: Binding(get: { JournalDate.parse(draft.date)! }, set: { draft.date = JournalDate.today($0) }), in: ...Date(), displayedComponents: .date)
                        .environment(\.timeZone, JournalDate.calendar.timeZone).environment(\.calendar, JournalDate.calendar).frame(width: 190)
                    TextField("时间 HH:mm（可选）", text: $time).frame(width: 170).textFieldStyle(.roundedBorder)
                    Spacer(minLength: 0)
                }
                if draft.kind == "event" {
                    if let chosen {
                        HStack(spacing: 16) {
                            ForEach(chosen.metrics, id: \.self) { metric in
                                HStack { Text(metric.title).font(.caption); TextField("未填写", text: Binding(get: { values[metric] ?? "" }, set: { values[metric] = $0 })).textFieldStyle(.roundedBorder).frame(width: 85); Text(metric.unit).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                        }
                    } else { Text("日记库没有可用活动定义，请先在 activities 文件夹添加活动。").font(.caption).foregroundStyle(.orange) }
                }
                TextField("为这段记录起个标题", text: $draft.title).font(.title2.weight(.semibold)).textFieldStyle(.plain).accessibilityLabel("标题")
            }.padding(20)
            HStack {
                Picker("编辑模式", selection: $mode) { Text("Markdown").tag("write"); Text("分栏").tag("split"); Text("预览").tag("preview") }.pickerStyle(.segmented).frame(width: 255)
                Spacer()
                Button(uploading ? "添加中…" : "添加图片", systemImage: "photo.badge.plus") { chooseImage() }.disabled(uploading || saving)
            }.padding(.horizontal, 20).padding(.bottom, 12)
            Divider()
            HSplitView {
                if mode != "preview" {
                    MarkdownTextEditor(text: $draft.body, insertion: insertion, importFile: { url in Task { await importImage(url) } })
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                }
                if mode != "write", let repository = store.repository {
                    ScrollView { JournalMarkdown(text: draft.body, repository: repository, revision: store.revision).padding(22).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(minHeight: 250)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("标签").font(.caption); TextField("用逗号分隔，例如：户外, 公园", text: $tags).textFieldStyle(.roundedBorder) }
                HStack { Text("封面").font(.caption); TextField("可选：../assets/记录ID/图片名.png", text: $cover).textFieldStyle(.roundedBorder) }
                Text("支持拖入 PNG / JPG / WebP，每张最多 10 MB。取消编辑不会自动删除已添加的图片。").font(.caption2).foregroundStyle(.secondary)
            }.padding(18)
        }.frame(width: 1000, height: 780).interactiveDismissDisabled()
            .onChange(of: activity) { _, _ in values = [:] }
            .confirmationDialog("放弃未保存的修改？", isPresented: $discard) {
                Button("放弃修改", role: .destructive) { store.editing = nil }
                Button("继续编辑", role: .cancel) { }
            }
    }
    private func candidate() throws -> Entry {
        var value = draft
        let clock = time.trimmingCharacters(in: .whitespaces)
        if clock.isEmpty { value.startedAt = nil }
        else {
            guard matches(clock, "^([01][0-9]|2[0-3]):[0-5][0-9]$") else { throw JournalError("时间格式应为 HH:mm，例如 08:30") }
            value.startedAt = clock == JournalDate.time(entry.startedAt) && draft.date == entry.date ? entry.startedAt : "\(draft.date)T\(clock):00+08:00"
        }
        value.tags = tags.components(separatedBy: CharacterSet(charactersIn: ",，")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        value.cover = cover.isEmpty ? nil : cover
        if value.kind == "event" {
            guard let chosen else { throw JournalError("请选择活动") }
            value.activityID = chosen.id; value.metrics = [:]
            for metric in chosen.metrics {
                let text = (values[metric] ?? "").trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    guard let number = Double(text) else { throw JournalError("\(metric.title)：请输入数值") }
                    value.metrics?[metric] = number
                }
            }
        } else { value.activityID = nil; value.metrics = nil }
        return value
    }
    private func save() async {
        saving = true; error = nil
        defer { saving = false }
        do { try await store.save(candidate()) } catch { self.error = error.localizedDescription }
    }
    private func cancel() {
        let originalTime = entry.startedAt == nil ? "" : JournalDate.time(entry.startedAt)
        let originalValues = Dictionary(uniqueKeysWithValues: (entry.metrics ?? [:]).map { ($0.key, String($0.value)) })
        if draft != entry || time != originalTime || tags != (entry.tags?.joined(separator: ", ") ?? "") || cover != (entry.cover ?? "") || values != originalValues || (entry.kind == "event" && activity != entry.activityID) { discard = true }
        else { store.editing = nil }
    }
    private func chooseImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .webP]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { Task { await importImage(url) } }
    }
    private func importImage(_ url: URL) async {
        guard !uploading, !saving, let repository = store.repository else { return }
        uploading = true; error = nil
        defer { uploading = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard let size, size <= 10 * 1024 * 1024 else { throw JournalError("图片超过 10 MB 或无法读取文件大小") }
            let bytes = try Data(contentsOf: url)
            let reference = try await repository.importImage(bytes, entryID: draft.id)
            let alt = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "[\\[\\]\\\\\\r\\n]", with: "", options: .regularExpression)
            insertion = TextInsertion(text: "\n![\(alt)](\(reference))\n")
            mode = "split"
        } catch { self.error = error.localizedDescription }
    }
}

struct TextInsertion { let id = UUID(); let text: String }
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    let insertion: TextInsertion?
    let importFile: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let view = FileDropTextView()
        view.isRichText = false; view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false; view.isAutomaticTextReplacementEnabled = false
        view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        view.textContainerInset = NSSize(width: 16, height: 16)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.string = text; view.delegate = context.coordinator; view.importFile = importFile
        view.setAccessibilityLabel("Markdown 正文")
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? FileDropTextView else { return }
        view.importFile = importFile
        if view.string != text { view.string = text }
        if let insertion, context.coordinator.lastInsertion != insertion.id {
            context.coordinator.lastInsertion = insertion.id
            view.insertText(insertion.text, replacementRange: view.selectedRange())
            let value = view.string
            DispatchQueue.main.async { context.coordinator.parent.text = value }
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        var lastInsertion: UUID?
        init(_ parent: MarkdownTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let view = notification.object as? NSTextView { parent.text = view.string } }
    }
}
final class FileDropTextView: NSTextView {
    var importFile: ((URL) -> Void)?
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return .copy }
        return super.draggingEntered(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], let url = urls.first { importFile?(url); return true }
        return super.performDragOperation(sender)
    }
}
