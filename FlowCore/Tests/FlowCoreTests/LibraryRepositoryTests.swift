// SPDX-License-Identifier: GPL-3.0-only
// Swift adaptation tests, 2026-11-06.
import Foundation
import XCTest
@testable import FlowCore

final class LibraryRepositoryTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("collection.json")
    }
    private func video(_ id: String = "abcdefghijk") throws -> VideoReference {
        try VideoReference(url: XCTUnwrap(URL(string: "https://youtu.be/\(id)")), title: id)
    }

    func testPlaylistMembershipOrderingAndCascade() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LibraryRepository(fileURL: url)
        let first = try video(), second = try video("01234567890")
        _ = try await store.apply(.createPlaylist(LocalPlaylist(id: "custom", name: "Queue")))
        _ = try await store.apply(.addToPlaylist(video: first, playlistID: "custom"))
        _ = try await store.apply(.addToPlaylist(video: second, playlistID: "custom"))
        _ = try await store.apply(.addToPlaylist(video: first, playlistID: "custom"))
        let reordered = try await store.apply(.reorderPlaylist(id: "custom", videoIDs: [second.id, first.id]))
        XCTAssertEqual(reordered.videos(in: "custom").map(\.id), [second.id, first.id])
        do {
            _ = try await store.apply(.reorderPlaylist(id: "custom", videoIDs: [first.id]))
            XCTFail("Partial reorder should fail")
        } catch LibraryError.invalidData { }
        let unchanged = await store.snapshot()
        XCTAssertEqual(unchanged, reordered)
        let deleted = try await store.apply(.deleteVideo(first.id))
        XCTAssertEqual(deleted.videos(in: "custom").map(\.id), [second.id])
        let reopened = try LibraryRepository(fileURL: url)
        let restored = await reopened.snapshot()
        XCTAssertEqual(restored, deleted)
    }

    func testHistoryPauseClampingAndStaleUpdates() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LibraryRepository(fileURL: url)
        let item = try video()
        let optionalSession = await store.beginWatch(videoID: item.id)
        let session = try XCTUnwrap(optionalSession)
        let now = Date(timeIntervalSince1970: 100)
        let state = try await store.apply(.recordWatch(video: item, entry: LocalWatchEntry(videoID: item.id, position: 200, duration: 100, watchedAt: now), session: session))
        XCTAssertEqual(state.history.first?.progress, 1)
        let stale = try await store.apply(.recordWatch(video: item, entry: LocalWatchEntry(videoID: item.id, position: 10, duration: 100, watchedAt: now.addingTimeInterval(-1)), session: session))
        XCTAssertEqual(stale, state)
        _ = try await store.apply(.pauseHistory(true))
        _ = try await store.apply(.clearHistory)
        let paused = try await store.apply(.recordWatch(video: item, entry: LocalWatchEntry(videoID: item.id, position: 20, duration: 100), session: session))
        XCTAssertTrue(paused.history.isEmpty)
    }

    func testBuiltInsAndSubscriptionUpdates() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LibraryRepository(fileURL: url)
        let item = try video()
        let saved = try await store.apply(.addToPlaylist(video: item, playlistID: LocalPlaylist.watchLaterID))
        XCTAssertEqual(saved.videos(in: LocalPlaylist.watchLaterID), [item])
        do {
            _ = try await store.apply(.deletePlaylist(LocalPlaylist.watchLaterID))
            XCTFail("Built-in playlist should be protected")
        } catch LibraryError.protectedPlaylist { }
        let date = Date(timeIntervalSince1970: 50)
        _ = try await store.apply(.subscribe(LocalSubscription(id: "UCchannel", name: "Original", subscribedAt: date)))
        let updated = try await store.apply(.subscribe(LocalSubscription(id: "UCchannel", name: "New", notificationsEnabled: true)))
        XCTAssertEqual(updated.subscriptions.count, 1)
        XCTAssertEqual(updated.subscriptions.first?.subscribedAt, date)
        XCTAssertEqual(updated.subscriptions.first?.name, "New")
    }

    func testLegacyMigrationIsOneTimeAndPreservesSource() async throws {
        let url = temporaryURL(), item = try video()
        let legacy = url.deletingLastPathComponent().appendingPathComponent("library.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = try JSONEncoder().encode([item, item])
        try original.write(to: legacy)
        let store = try LibraryRepository(fileURL: url, legacyBookmarksURL: legacy)
        let migrated = await store.snapshot()
        XCTAssertEqual(migrated.videos, [item])
        _ = try await store.apply(.deleteVideo(item.id))
        let reopened = try LibraryRepository(fileURL: url, legacyBookmarksURL: legacy)
        let restored = await reopened.snapshot()
        XCTAssertTrue(restored.videos.isEmpty)
        XCTAssertEqual(try Data(contentsOf: legacy), original)
    }

    func testCorruptAndFutureFilesArePreserved() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for contents in ["not json", "{\"schemaVersion\":99}"] {
            let data = Data(contents.utf8)
            try data.write(to: url)
            XCTAssertThrowsError(try LibraryRepository(fileURL: url))
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    func testFailedWriteDoesNotPublishChanges() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LibraryRepository(fileURL: url)
        let before = await store.snapshot()
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        do {
            _ = try await store.apply(.saveVideo(video()))
            XCTFail("Cannot atomically replace a directory with a file")
        } catch { }
        let after = await store.snapshot()
        XCTAssertEqual(before, after)
    }
    func testInvalidatedPlaybackCannotResurrectDeletedState() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LibraryRepository(fileURL: url)
        let item = try video()
        let invalidators: [LibraryCommand] = [.clearHistory, .removeHistory(item.id), .deleteVideo(item.id), .pauseHistory(true)]
        for invalidator in invalidators {
            _ = try await store.apply(.pauseHistory(false))
            let optionalSession = await store.beginWatch(videoID: item.id)
            let session = try XCTUnwrap(optionalSession)
            _ = try await store.apply(.recordWatch(video: item, entry: LocalWatchEntry(videoID: item.id, position: 10, duration: 100), session: session))
            let deleted = try await store.apply(invalidator)
            // A new timestamp does not grant a delayed callback permission to recreate data.
            let delayed = try await store.apply(.recordWatch(video: item, entry: LocalWatchEntry(videoID: item.id, position: 20, duration: 100, watchedAt: Date().addingTimeInterval(1000)), session: session))
            XCTAssertEqual(delayed, deleted)
            _ = try await store.apply(.pauseHistory(false))
            let unpaused = await store.snapshot()
            let oldSession = try await store.apply(.recordWatch(video: item, entry: LocalWatchEntry(videoID: item.id, position: 30, duration: 100), session: session))
            XCTAssertEqual(oldSession, unpaused)
            let newOptional = await store.beginWatch(videoID: item.id)
            let newSession = try XCTUnwrap(newOptional)
            let resumed = try await store.apply(.recordWatch(video: item, entry: LocalWatchEntry(videoID: item.id, position: 40, duration: 100), session: newSession))
            XCTAssertEqual(resumed.history.first?.position, 40)
        }
        let optionalSession = await store.beginWatch(videoID: item.id)
        let oldSession = try XCTUnwrap(optionalSession)
        let reopened = try LibraryRepository(fileURL: url)
        let before = await reopened.snapshot()
        let after = try await reopened.apply(.recordWatch(video: item, entry: LocalWatchEntry(videoID: item.id, position: 50, duration: 100), session: oldSession))
        XCTAssertEqual(before, after)
    }

    func testDecodedDuplicateVideosDoNotTrapDuringLookup() throws {
        let item = try video()
        var malformed = LibrarySnapshot()
        malformed.videos = [item, item]
        malformed.playlists = [LocalPlaylist(id: "custom", name: "Queue", videoIDs: [item.id])]
        let decoded = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(malformed))
        XCTAssertEqual(decoded.videos(in: "custom"), [item])
        XCTAssertThrowsError(try decoded.validated())
    }

}
