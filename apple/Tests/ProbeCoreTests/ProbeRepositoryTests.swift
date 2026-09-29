import Foundation
import XCTest
@testable import ProbeCore

final class ProbeRepositoryTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func testInitializeAndRoundTripUnicodeMarkdown() async throws {
        let url = try directory()
        let repository = ProbeRepository()
        let initialized = try await repository.isInitialized(url)
        XCTAssertFalse(initialized)
        try await repository.initialize(url)
        let text = "# 日常\n\n离线记录 📝\n\n![图片](../assets/example/a.png)\n"
        try await repository.save(text, in: url)
        let snapshot = try await repository.read(url)
        XCTAssertEqual(snapshot.text, text)
        XCTAssertFalse(snapshot.isCloud)
        XCTAssertNotNil(snapshot.modified)
        let reopened = try await ProbeRepository().read(url)
        XCTAssertEqual(reopened.text, text)
    }

    func testRefusesNonemptyDirectoryWithoutChangingIt() async throws {
        let url = try directory()
        let file = url.appendingPathComponent("settings.json")
        let data = Data("personal content".utf8)
        try data.write(to: file)
        do {
            try await ProbeRepository().initialize(url)
            XCTFail("Must refuse real content")
        } catch ProbeError.unsafeDirectory { }
        XCTAssertEqual(try Data(contentsOf: file), data)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.path), ["settings.json"])
    }

    func testRefusesSymbolicLinkDocument() async throws {
        let url = try directory()
        let outside = try directory().appendingPathComponent("outside.md")
        try Data("unchanged".utf8).write(to: outside)
        let repository = ProbeRepository()
        try await repository.initialize(url)
        let file = url.appendingPathComponent("probe.md")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        do {
            try await repository.save("changed", in: url)
            XCTFail("Must refuse symlink")
        } catch ProbeError.unsafeDirectory { }
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "unchanged")
    }

    func testInitializationDoesNotOverwriteExistingProbe() async throws {
        let url = try directory()
        let repository = ProbeRepository()
        try await repository.initialize(url)
        try await repository.save("keep me", in: url)
        do {
            try await repository.initialize(url)
            XCTFail("Must not reinitialize")
        } catch ProbeError.unsafeDirectory { }
        let snapshot = try await repository.read(url)
        XCTAssertEqual(snapshot.text, "keep me")
    }

    func testConflictSelection() throws {
        let current = Date(timeIntervalSince1970: 100)
        XCTAssertNil(try ConflictPolicy.newest(current: current, conflicts: [current, current.addingTimeInterval(-1)]))
        XCTAssertEqual(try ConflictPolicy.newest(current: current, conflicts: [current.addingTimeInterval(1), current.addingTimeInterval(2)]), 1)
        XCTAssertThrowsError(try ConflictPolicy.newest(current: nil, conflicts: [current]))
        XCTAssertThrowsError(try ConflictPolicy.newest(current: current, conflicts: [nil]))
    }
}
