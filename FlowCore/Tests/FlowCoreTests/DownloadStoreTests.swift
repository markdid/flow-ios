import Foundation
import XCTest
@testable import FlowCore

final class DownloadStoreTests: XCTestCase {
    private func video() throws -> VideoReference { try VideoReference(url: XCTUnwrap(URL(string: "https://youtu.be/abcdefghijk")), title: "Example") }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    func testPolicyRejectsHLSRangeAndForeignHosts() throws {
        let valid = try XCTUnwrap(URL(string: "https://r1.googlevideo.com/videoplayback?x=1"))
        XCTAssertEqual(try DownloadPolicy.kind(for: PlaybackSource(id: "18", url: valid, label: "MP4", kind: .video)), .video)
        XCTAssertThrowsError(try DownloadPolicy.kind(for: PlaybackSource(id: "hls", url: valid, label: "HLS", kind: .hls)))
        let ranged = try XCTUnwrap(URL(string: "https://r1.googlevideo.com/videoplayback?range=0-20"))
        XCTAssertThrowsError(try DownloadPolicy.kind(for: PlaybackSource(id: "18", url: ranged, label: "MP4", kind: .video)))
        let foreign = try XCTUnwrap(URL(string: "https://googlevideo.com.evil.test/video.mp4"))
        XCTAssertThrowsError(try DownloadPolicy.kind(for: PlaybackSource(id: "18", url: foreign, label: "MP4", kind: .video)))
    }
    func testResponseChecksStatusMIMEAndCompleteness() throws {
        XCTAssertNoThrow(try DownloadPolicy.validateResponse(status: 200, mimeType: "video/mp4", expectedBytes: 20, actualBytes: 20, kind: .video))
        XCTAssertNoThrow(try DownloadPolicy.validateResponse(status: 200, mimeType: "audio/mp4", expectedBytes: -1, actualBytes: 20, kind: .audio))
        XCTAssertThrowsError(try DownloadPolicy.validateResponse(status: 206, mimeType: "video/mp4", expectedBytes: 20, actualBytes: 20, kind: .video))
        XCTAssertThrowsError(try DownloadPolicy.validateResponse(status: 200, mimeType: "text/html", expectedBytes: 20, actualBytes: 20, kind: .video))
        XCTAssertThrowsError(try DownloadPolicy.validateResponse(status: 200, mimeType: "video/mp4", expectedBytes: 20, actualBytes: 19, kind: .video))
        XCTAssertThrowsError(try DownloadPolicy.validateResponse(status: 200, mimeType: "video/mp4", expectedBytes: -1, actualBytes: DownloadPolicy.maximumBytes + 1, kind: .video))
    }
    func testCommitReopenAndDeleteAreConsistent() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let temp = root.appendingPathComponent("transfer.tmp")
        try Data("fixture-bytes-not-a-real-media-file".utf8).write(to: temp)
        let store = try DownloadStore(directory: root.appendingPathComponent("Downloads"))
        let records = try await store.commit(temporaryFile: temp, video: video(), kind: .video)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.filename, record.id.uuidString.lowercased() + ".mp4")
        let local = try await store.fileURL(for: record.id)
        XCTAssertEqual(try Data(contentsOf: local), try Data(contentsOf: temp))
        let reopened = try DownloadStore(directory: root.appendingPathComponent("Downloads"))
        let restored = await reopened.snapshot()
        XCTAssertEqual(restored, records)
        let removed = try await reopened.remove(record.id)
        XCTAssertTrue(removed.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temp.path))
    }
    func testIndexFailureRollsBackNewMedia() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try DownloadStore(directory: root)
        let temp = root.appendingPathComponent("transfer.tmp")
        try Data([1, 2, 3]).write(to: temp)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("downloads-v1.json"), withIntermediateDirectories: false)
        do { _ = try await store.commit(temporaryFile: temp, video: video(), kind: .audio); XCTFail("Expected persist failure") }
        catch { }
        let snapshot = await store.snapshot()
        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasSuffix(".m4a") })
    }
    func testRejectsSymlinkInputAndPreservesCorruptIndex() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try DownloadStore(directory: root)
        let target = root.appendingPathComponent("target")
        let link = root.appendingPathComponent("link")
        try Data([1]).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        do { _ = try await store.commit(temporaryFile: link, video: video(), kind: .audio); XCTFail("Expected symlink rejection") }
        catch DownloadError.emptyFile { }
        let index = root.appendingPathComponent("downloads-v1.json")
        try Data("corrupt".utf8).write(to: index)
        XCTAssertThrowsError(try DownloadStore(directory: root))
        XCTAssertEqual(try String(contentsOf: index, encoding: .utf8), "corrupt")
    }
    private func journal(_ kind: String, record: DownloadedMedia, root: URL, originalFileExisted: Bool? = nil) throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
        var payload: [String: Any] = ["version": 1, "kind": kind, "record": object]
        if let originalFileExisted { payload["originalFileExisted"] = originalFileExisted }
        try JSONSerialization.data(withJSONObject: payload).write(to: root.appendingPathComponent("download-operation-v1.json"))
    }
    private func emptyIndex(_ root: URL) throws {
        try JSONSerialization.data(withJSONObject: ["version": 1, "records": []])
            .write(to: root.appendingPathComponent("downloads-v1.json"))
    }
    private func fixture(_ root: URL) async throws -> DownloadedMedia {
        let store = try DownloadStore(directory: root)
        let temp = root.appendingPathComponent("fixture.tmp")
        try Data([1, 2, 3]).write(to: temp)
        let records = try await store.commit(temporaryFile: temp, video: video(), kind: .video)
        return try XCTUnwrap(records.first)
    }
    func testCrashBeforeDeleteIndexCommitRestoresDeterministicStaging() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let record = try await fixture(root)
        try journal("delete", record: record, root: root)
        let final = root.appendingPathComponent(record.filename)
        let staged = root.appendingPathComponent("pending-delete-" + record.filename)
        try FileManager.default.moveItem(at: final, to: staged)
        let reopened = try DownloadStore(directory: root)
        let records = await reopened.snapshot()
        XCTAssertEqual(records, [record])
        XCTAssertTrue(FileManager.default.fileExists(atPath: final.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    }
    func testCrashAfterDeleteIndexCommitFinishesCleanup() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let record = try await fixture(root)
        try journal("delete", record: record, root: root)
        let staged = root.appendingPathComponent("pending-delete-" + record.filename)
        try FileManager.default.moveItem(at: root.appendingPathComponent(record.filename), to: staged)
        try emptyIndex(root)
        let reopened = try DownloadStore(directory: root)
        let records = await reopened.snapshot()
        XCTAssertTrue(records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("download-operation-v1.json").path))
    }
    func testCrashAfterAddFileBeforeIndexCompletesCommit() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let record = try await fixture(root)
        try emptyIndex(root)
        try journal("add", record: record, root: root)
        let reopened = try DownloadStore(directory: root)
        let records = await reopened.snapshot()
        XCTAssertEqual(records, [record])
        let local = try await reopened.fileURL(for: record.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: local.path))
    }
    func testIncompleteOrAmbiguousStagingIsPreserved() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let record = try await fixture(root)
        try emptyIndex(root)
        try journal("add", record: record, root: root)
        let final = root.appendingPathComponent(record.filename)
        let staged = root.appendingPathComponent("pending-add-" + record.filename)
        try Data([1]).write(to: staged)
        XCTAssertThrowsError(try DownloadStore(directory: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: final.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
        try FileManager.default.removeItem(at: final)
        let recovered = try DownloadStore(directory: root)
        let count = try await recovered.recoveredTransferCount()
        XCTAssertEqual(count, 1)
        let preserved = root.appendingPathComponent("Recovery/add-" + record.id.uuidString.lowercased()).appendingPathComponent(staged.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: preserved), Data([1]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("download-operation-v1.json").path))
        let recoveredRecords = await recovered.snapshot()
        XCTAssertTrue(recoveredRecords.isEmpty)
        let next = try await recovered.commit(temporaryFile: root.appendingPathComponent("fixture.tmp"), video: video(), kind: .video)
        XCTAssertEqual(next.count, 1)
    }
    func testCancelledTaskBeforeCommitCreatesNoMediaOrJournal() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try DownloadStore(directory: root)
        let temp = root.appendingPathComponent("fixture.tmp")
        try Data([1, 2, 3]).write(to: temp)
        let item = try video()
        let work = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.commit(temporaryFile: temp, video: item, kind: .video)
        }
        do { _ = try await work.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        let records = await store.snapshot()
        XCTAssertTrue(records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("download-operation-v1.json").path))
    }
    func testInterruptedDeletionOfAlreadyMissingFileCompletesSafely() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let record = try await fixture(root)
        try FileManager.default.removeItem(at: root.appendingPathComponent(record.filename))
        try journal("delete", record: record, root: root, originalFileExisted: false)
        let reopened = try DownloadStore(directory: root)
        let records = await reopened.snapshot()
        XCTAssertTrue(records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("download-operation-v1.json").path))
    }
}
