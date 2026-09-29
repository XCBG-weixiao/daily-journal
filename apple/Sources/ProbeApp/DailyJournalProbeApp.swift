import SwiftUI
import UniformTypeIdentifiers

@main
struct DailyJournalProbeApp: App {
    @StateObject private var session = ProbeSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ProbeView(session: session)
                .task { await session.restore() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await session.refresh() } }
                }
                #if os(macOS)
                .frame(minWidth: 580, minHeight: 640)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 720, height: 780)
        #endif
    }
}

private struct ProbeView: View {
    @ObservedObject var session: ProbeSession
    @State private var choosingDirectory = false

    var body: some View {
        NavigationStack {
            Form {
                Section("1 · 文件夹授权") {
                    Text("这是原生应用的同步验证工具。请在 iCloud Drive 新建一个空测试文件夹，并在两台设备选择同一个文件夹。")
                    if let name = session.folderName { LabeledContent("已选择", value: name) }
                    Button("选择测试文件夹", systemImage: "folder") { choosingDirectory = true }
                    if session.folderName != nil && !session.initialized {
                        Button("初始化验证目录") { Task { await session.initialize() } }
                    }
                }

                Section("2 · 编辑测试文件 probe.md") {
                    TextEditor(text: $session.draft)
                        .font(.body.monospaced())
                        .frame(minHeight: 150)
                        .disabled(!session.initialized)
                        .accessibilityLabel("测试文件正文")
                    Button("保存到文件", systemImage: "square.and.arrow.down") { Task { await session.save() } }
                        .disabled(!session.initialized)
                    Text("刷新只更新下方磁盘内容，不覆盖正在编辑的文字。保存会覆盖文件；同步冲突采用修改时间较晚的版本。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("3 · 本机读到的文件") {
                    if let snapshot = session.snapshot {
                        Text(snapshot.text).textSelection(.enabled)
                        if let date = snapshot.modified {
                            LabeledContent("修改时间", value: date.formatted(date: .numeric, time: .standard))
                        }
                        LabeledContent("系统识别为 iCloud 文件", value: snapshot.isCloud ? "是" : "否")
                        LabeledContent("系统上传状态", value: uploadLabel(snapshot.uploaded))
                        if snapshot.resolvedConflicts > 0 {
                            Text("本次已按最后修改时间处理 \(snapshot.resolvedConflicts) 个冲突版本。")
                        }
                        Button("将磁盘内容载入编辑区") { session.draft = snapshot.text }
                    } else {
                        Text("尚未读到测试文件。")
                    }
                    Button("刷新文件", systemImage: "arrow.clockwise") { Task { await session.refresh() } }
                        .disabled(session.folderName == nil)
                    Button("请求下载 iCloud 文件", systemImage: "icloud.and.arrow.down") { Task { await session.download() } }
                        .disabled(session.folderName == nil)
                }

                Section("状态") {
                    if session.busy { ProgressView("正在访问文件…") }
                    if let error = session.errorMessage {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                    } else {
                        Text(session.notice).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("日常 · 同步验证")
            .disabled(session.busy)
            .fileImporter(isPresented: $choosingDirectory, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url): Task { await session.select(url) }
                case .failure(let error): session.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func uploadLabel(_ uploaded: Bool?) -> String {
        guard let uploaded else { return "系统未提供" }
        return uploaded ? "已上传（不代表另一端已下载）" : "尚未上传完成"
    }
}
