import SwiftUI
import AppKit
import MarkdownUI
import JournalCore

private func imageReference(_ url: URL?) throws -> String {
    guard let url, url.scheme == "journal-asset", url.host == "content", url.query == nil, url.fragment == nil,
          url.path.hasPrefix("/assets/") else { throw JournalError("图片路径无效，仅支持日记库中的本地图片") }
    return ".." + url.path
}

struct LocalImageProvider: ImageProvider {
    let repository: JournalRepository
    let revision: Int
    func makeImage(url: URL?) -> some View { JournalImage(repository: repository, url: url, revision: revision) }
}
struct LocalInlineImageProvider: InlineImageProvider {
    let repository: JournalRepository
    let report: (String) -> Void
    func image(with url: URL, label: String) async throws -> Image {
        do {
            let data = try await repository.imageData(imageReference(url))
            guard let image = NSImage(data: data) else { throw JournalError("无法解码图片：\(label)") }
            let ratio = min(1, 28 / image.size.height)
            image.size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
            return Image(nsImage: image)
        } catch {
            await MainActor.run { report(error.localizedDescription) }
            throw error
        }
    }
}
struct JournalImage: View {
    let repository: JournalRepository
    let url: URL?
    let revision: Int
    @State private var image: NSImage?
    @State private var error: String?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 360).clipShape(RoundedRectangle(cornerRadius: 10)) }
            else if let error { Label(error, systemImage: "photo.badge.exclamationmark").font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            else { ProgressView().frame(height: 50) }
        }.task(id: "\(url?.absoluteString ?? "invalid")/\(revision)") {
            image = nil; error = nil
            do {
                let bytes = try await repository.imageData(imageReference(url))
                guard let value = NSImage(data: bytes) else { throw JournalError("无法解码图片") }
                image = value
            } catch { self.error = error.localizedDescription }
        }
    }
}
struct JournalMarkdown: View {
    let text: String
    let repository: JournalRepository
    let revision: Int
    @State private var imageErrors: Set<String> = []
    static let imageBase = URL(string: "journal-asset://content/entries/")!
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Markdown(text, imageBaseURL: Self.imageBase)
                .id(revision)
                .markdownTheme(.gitHub)
                .markdownTextStyle { FontSize(15) }
                .markdownImageProvider(LocalImageProvider(repository: repository, revision: revision))
                .markdownInlineImageProvider(LocalInlineImageProvider(repository: repository) { imageErrors.insert($0) })
                .textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { url in
                    guard ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
                    return .systemAction
                })
            ForEach(imageErrors.sorted(), id: \.self) { message in Label(message, systemImage: "photo.badge.exclamationmark").font(.caption).foregroundStyle(.orange) }
        }.onChange(of: text) { _, _ in imageErrors.removeAll() }
            .onChange(of: revision) { _, _ in imageErrors.removeAll() }
    }
}
struct EntryReader: View {
    @ObservedObject var store: JournalStore
    let entry: Entry
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("关闭阅读", systemImage: "xmark") { store.selectedEntry = nil }.labelStyle(.iconOnly).buttonStyle(.borderless)
                Spacer()
                Button("编辑", systemImage: "pencil") { store.editEntry(entry) }.disabled(store.busy)
                Menu {
                    Button("移入回收站…", systemImage: "trash", role: .destructive) { store.deletingEntry = entry }
                } label: { Image(systemName: "ellipsis.circle") }.disabled(store.busy)
            }.padding(18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    let activity = store.snapshot.activities.first { $0.id == entry.activityID }
                    Text(entry.date + " · " + JournalDate.time(entry.startedAt)).font(.caption).foregroundStyle(.secondary)
                    Text(entry.title).font(.system(size: 27, weight: .semibold)).textSelection(.enabled)
                    HStack { Text(activity.map { $0.icon + " " + $0.name } ?? "✎ 日记").font(.subheadline); Spacer() }
                    if let metrics = entry.metrics, !metrics.isEmpty {
                        HStack { ForEach(Metric.allCases, id: \.self) { metric in if let value = metrics[metric] { MetricTile(title: metric.title, value: numberLabel(value) + " " + metric.unit) } } }
                    }
                    if let tags = entry.tags, !tags.isEmpty {
                        HStack { ForEach(tags, id: \.self) { tag in Button("#" + tag) { store.query = tag; store.selection = "search" }.buttonStyle(.link) } }.font(.caption)
                    }
                    Divider()
                    if let repository = store.repository {
                        if let cover = entry.cover { JournalImage(repository: repository, url: URL(string: cover, relativeTo: JournalMarkdown.imageBase)?.absoluteURL, revision: store.revision) }
                        JournalMarkdown(text: entry.body, repository: repository, revision: store.revision)
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.background(.background)
    }
}
