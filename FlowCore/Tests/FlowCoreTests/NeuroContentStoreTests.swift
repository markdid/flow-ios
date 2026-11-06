// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import FlowCore

final class NeuroContentStoreTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testRoundTripStrongestTopicsAndReplacement() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("content.json")
        let store = try NeuroContentStore(fileURL: file, keySpace: "ios-test-v1")
        let topics = Dictionary(uniqueKeysWithValues: (1...15).map { ("topic\($0)", Double($0) / 15) })
        try await store.put(videoID: "video", topics: topics, now: Date(timeIntervalSince1970: 10))
        let stored = await store.topics(for: "video")
        XCTAssertEqual(stored?.count, 12)
        XCTAssertNil(stored?["topic1"])
        let restored = try NeuroContentStore(fileURL: file, keySpace: "ios-test-v1")
        let reopened = await restored.snapshot()
        XCTAssertEqual(reopened["video"]?.topics, stored)
        try await store.put(videoID: "video", topics: ["new": 1])
        let replaced = await store.topics(for: "video")
        XCTAssertEqual(replaced, ["new": 1])
        try await store.remove(videoID: "video")
        let empty = await store.snapshot()
        XCTAssertTrue(empty.isEmpty)
    }
    func testCorruptAndIncompatibleFilesArePreserved() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("content.json")
        let invalid = Data("not json".utf8)
        try invalid.write(to: file)
        XCTAssertThrowsError(try NeuroContentStore(fileURL: file, keySpace: "ios-test-v1"))
        XCTAssertEqual(try Data(contentsOf: file), invalid)
        try FileManager.default.removeItem(at: file)
        let store = try NeuroContentStore(fileURL: file, keySpace: "ios-test-v1")
        try await store.put(videoID: "video", topics: ["guitar": 1])
        let original = try Data(contentsOf: file)
        XCTAssertThrowsError(try NeuroContentStore(fileURL: file, keySpace: "different")) {
            XCTAssertEqual($0 as? NeuroContentStore.StoreError, .incompatibleKeySpace)
        }
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    func testInvalidInputsAndFailedWriteDoNotChangeSnapshot() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("content.json")
        let store = try NeuroContentStore(fileURL: file, keySpace: "ios-test-v1")
        try await store.put(videoID: "video", topics: ["guitar": 1])
        do { try await store.put(videoID: "bad", topics: ["guitar": .nan]); XCTFail("Expected rejection") } catch {}
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        do { try await store.put(videoID: "new", topics: ["piano": 1]); XCTFail("Expected failed write") } catch {}
        let snapshot = await store.snapshot()
        XCTAssertEqual(Set(snapshot.keys), ["video"])
    }
    func testPrunesByWriteTimeNotReadTimeAndClearPersists() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("content.json")
        // Seed a valid bounded fixture to avoid 1,500 filesystem writes in a unit test.
        let entries = Dictionary(uniqueKeysWithValues: (0..<1500).map { index in
            ("video\(index)", ["topics": ["guitar": 1.0], "updatedAt": Double(index)] as [String: Any])
        })
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "keySpace": "ios-test-v1", "entries": entries])
        try data.write(to: file)
        let store = try NeuroContentStore(fileURL: file, keySpace: "ios-test-v1")
        _ = await store.topics(for: "video0")
        try await store.put(videoID: "new", topics: ["piano": 1], now: Date(timeIntervalSinceReferenceDate: 2000))
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.count, 1500)
        XCTAssertNil(snapshot["video0"])
        XCTAssertNotNil(snapshot["new"])
        try await store.clear()
        let restored = try NeuroContentStore(fileURL: file, keySpace: "ios-test-v1")
        let cleared = await restored.snapshot()
        XCTAssertTrue(cleared.isEmpty)
    }
}
