import Foundation

public enum ProbeError: LocalizedError {
    case unsafeDirectory, notInitialized, notDownloaded(String), missingDate, coordination
    public var errorDescription: String? {
        switch self {
        case .unsafeDirectory: return "请选择单独的空测试文件夹，或本工具已初始化的验证文件夹。不能选择真实日记目录。"
        case .notInitialized: return "请先初始化测试文件夹。"
        case .notDownloaded(let name): return "\(name) 尚未下载到本机，请联网下载后再使用。"
        case .missingDate: return "文件冲突版本缺少修改时间，无法执行最后修改版本策略。"
        case .coordination: return "系统未执行文件协调操作。"
        }
    }
}

public struct ProbeSnapshot: Sendable {
    public let text: String
    public let modified: Date?
    public let isCloud: Bool
    public let uploaded: Bool?
    public let resolvedConflicts: Int
}

// Equal timestamps retain the current version. Dates must exist; never guess a winner.
public enum ConflictPolicy {
    public static func newest(current: Date?, conflicts: [Date?]) throws -> Int? {
        guard var latest = current else { throw ProbeError.missingDate }
        var winner: Int?
        for (index, date) in conflicts.enumerated() {
            guard let date else { throw ProbeError.missingDate }
            if date > latest { latest = date; winner = index }
        }
        return winner
    }
}

// Serializes this app's operations; NSFileCoordinator coordinates with other processes.
public actor ProbeRepository {
    private static let marker = ".daily-journal-probe"
    private static let markerContents = Data("daily-journal-directory-probe-v1\n".utf8)
    private static let document = "probe.md"
    public init() {}

    public func isInitialized(_ directory: URL) throws -> Bool {
        try requireLocal(directory)
        return try coordinated(directory, writing: false) { url in
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            let visible = contents.filter { $0.lastPathComponent != ".DS_Store" }
            if visible.isEmpty { return false }
            let marker = url.appendingPathComponent(Self.marker)
            guard contents.contains(where: { $0.lastPathComponent == Self.marker }) else { throw ProbeError.unsafeDirectory }
            try requireLocal(marker)
            try rejectSymbolicLink(marker)
            guard try Data(contentsOf: marker) == Self.markerContents,
                  visible.allSatisfy({ [Self.marker, Self.document].contains($0.lastPathComponent) })
            else { throw ProbeError.unsafeDirectory }
            return true
        }
    }

    public func initialize(_ directory: URL) throws {
        try requireLocal(directory)
        try coordinated(directory, writing: true) { url in
            let files = try FileManager.default.contentsOfDirectory(atPath: url.path)
            guard files.allSatisfy({ $0 == ".DS_Store" }) else { throw ProbeError.unsafeDirectory }
            try Self.markerContents.write(to: url.appendingPathComponent(Self.marker), options: .atomic)
        }
        try save("# 同步验证\n\n请在 Mac 和 iPhone 分别修改这段文字。\n", in: directory)
    }

    public func save(_ text: String, in directory: URL) throws {
        guard try isInitialized(directory) else { throw ProbeError.notInitialized }
        let file = directory.appendingPathComponent(Self.document)
        if FileManager.default.fileExists(atPath: file.path) {
            try requireLocal(file)
            try rejectSymbolicLink(file)
        }
        try coordinated(file, writing: true) { url in
            try rejectSymbolicLinkIfPresent(url)
            try Data(text.utf8).write(to: url, options: .atomic)
        }
    }

    public func read(_ directory: URL) throws -> ProbeSnapshot {
        guard try isInitialized(directory) else { throw ProbeError.notInitialized }
        let file = directory.appendingPathComponent(Self.document)
        try requireLocal(file)
        try rejectSymbolicLink(file)
        let resolved = try resolveConflicts(file)
        return try coordinated(file, writing: false) { url in
            let text = try String(contentsOf: url, encoding: .utf8)
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isUbiquitousItemKey,
                                                          .ubiquitousItemIsUploadedKey,
                                                          .ubiquitousItemUploadingErrorKey,
                                                          .ubiquitousItemDownloadingErrorKey])
            if let error = values.ubiquitousItemUploadingError { throw error }
            if let error = values.ubiquitousItemDownloadingError { throw error }
            return ProbeSnapshot(text: text, modified: values.contentModificationDate,
                                 isCloud: values.isUbiquitousItem == true,
                                 uploaded: values.ubiquitousItemIsUploaded,
                                 resolvedConflicts: resolved)
        }
    }

    public func requestDownload(_ directory: URL) throws {
        for file in [directory, directory.appendingPathComponent(Self.marker),
                     directory.appendingPathComponent(Self.document)] {
            let values = try file.resourceValues(forKeys: [.isUbiquitousItemKey])
            if values.isUbiquitousItem == true {
                try FileManager.default.startDownloadingUbiquitousItem(at: file)
            }
        }
    }

    private func resolveConflicts(_ file: URL) throws -> Int {
        // A write coordination on every refresh would itself notify file presenters.
        guard !(NSFileVersion.unresolvedConflictVersionsOfItem(at: file) ?? []).isEmpty else { return 0 }
        return try coordinated(file, writing: true) { url in
            let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
            guard !conflicts.isEmpty else { return 0 }
            let currentDate = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let winner = try ConflictPolicy.newest(current: currentDate,
                                                   conflicts: conflicts.map(\.modificationDate))
            if let winner { _ = try conflicts[winner].replaceItem(at: url, options: []) }
            for version in conflicts { version.isResolved = true }
            return conflicts.count
        }
    }
}

private func requireLocal(_ url: URL) throws {
    let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
    if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded {
        throw ProbeError.notDownloaded(url.lastPathComponent)
    }
}

private func rejectSymbolicLink(_ url: URL) throws {
    if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
        throw ProbeError.unsafeDirectory
    }
}

private func rejectSymbolicLinkIfPresent(_ url: URL) throws {
    // lstat-style attributes also detect dangling symbolic links.
    do {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw ProbeError.unsafeDirectory }
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        return // Creating the probe file is an explicit supported operation.
    }
}

private func coordinated<T>(_ url: URL, writing: Bool, operation: (URL) throws -> T) throws -> T {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var result: Result<T, Error>?
    let access: (URL) -> Void = { coordinatedURL in result = Result { try operation(coordinatedURL) } }
    if writing {
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError, byAccessor: access)
    } else {
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError, byAccessor: access)
    }
    if let coordinationError { throw coordinationError }
    guard let result else { throw ProbeError.coordination }
    return try result.get()
}
