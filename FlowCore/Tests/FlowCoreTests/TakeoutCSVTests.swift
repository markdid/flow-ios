import XCTest
@testable import FlowCore
final class TakeoutCSVTests: XCTestCase {
    let channel = "UCabcdefghijklmnopqrstuv"
    func parse(_ text: String) throws -> TakeoutPreview { try TakeoutCSV.preview(Data(text.utf8), importedAt: Date(timeIntervalSince1970: 100)) }
    func testSubscriptionsBOMQuotedNamesCRLFAndDedup() throws {
        let csv = "\u{FEFF}Channel Id,Channel Url,Channel Title\r\n\(channel),https://www.youtube.com/channel/\(channel),\"Name, with \"\"quotes\"\"\"\r\n\(channel),https://youtube.com/channel/\(channel)/,Duplicate\r\n"
        guard case .subscriptions(let rows, let skipped) = try parse(csv) else { return XCTFail("subscriptions") }
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows[0].name, "Name, with \"quotes\"")
        XCTAssertEqual(rows[0].subscribedAt, Date(timeIntervalSince1970: 100)); XCTAssertEqual(skipped, 1)
    }
    func testSubscriptionURLMustMatchIDAndSafeHost() throws {
        let csv = "Id,URL,Name\n\(channel),https://youtube.com/channel/\(channel),Valid\n\(channel),https://evil.test/channel/\(channel),Foreign\n\(channel),https://youtube.com/channel/\(channel)?x=1,Query\n\(channel),https://youtube.com/channel/UC0123456789012345678901,Mismatch\n"
        guard case .subscriptions(let rows, let skipped) = try parse(csv) else { return XCTFail("subscriptions") }
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(skipped, 3)
    }
    func testPlaylistOrderDedupAndTimestampValidation() throws {
        let csv = "Video ID,Time Added\nabcdefghijk,2026-11-06T10:20:30Z\n01234567890,2026-11-06T10:20:30.123456789+01:00\nabcdefghijk,\nlmnopqrstuv,2026-02-31T10:20:30Z\nzyxwvutsrqp,2026-11-06T24:00:00Z\n"
        guard case .playlist(let rows, let skipped) = try parse(csv) else { return XCTFail("playlist") }
        XCTAssertEqual(rows.map(\.id), ["abcdefghijk", "01234567890"]); XCTAssertEqual(skipped, 3)
    }
    func testMalformedCSVRejectsWholeFile() {
        for csv in ["a,b\nabcdefghijk,\"unclosed", "a,b\nabcdefghijk,bad\"quote", "a,b\nabcdefghijk,\"closed\"junk", "a,b\nabcdefghijk,\"nul\u{0000}\""] { XCTAssertThrowsError(try parse(csv)) }
        XCTAssertThrowsError(try TakeoutCSV.preview(Data([0xff, 0xfe])))
    }
    func testQuotedMultilineNameRejectedAsRowNotMisparsed() throws {
        let csv = "Id,URL,Name\n\(channel),https://youtube.com/channel/\(channel),Valid\nUC0123456789012345678901,https://youtube.com/channel/UC0123456789012345678901,\"bad\nname\"\n"
        guard case .subscriptions(let rows, let skipped) = try parse(csv) else { return XCTFail("subscriptions") }
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(skipped, 1)
    }
    func testLocalizedHeadersAndUnsupportedFormats() throws {
        guard case .playlist = try parse("動画 ID,追加時刻\nabcdefghijk,\n") else { return XCTFail("localized header") }
        for csv in ["Video ID,Time Added", "abcdefghijk,\n01234567890,", "a,b\nbad,", "a,b,c\nabcdefghijk,Title,Artist"] { XCTAssertThrowsError(try parse(csv)) }
    }
    func testLimitsDoNotSilentlyTruncate() {
        XCTAssertThrowsError(try TakeoutCSV.preview(Data(repeating: 65, count: TakeoutCSV.maximumBytes + 1)))
        XCTAssertThrowsError(try parse("a,b\n" + String(repeating: "abcdefghijk,\n", count: TakeoutCSV.maximumRows + 1)))
        XCTAssertThrowsError(try parse(String(repeating: "x", count: 16_001) + ",b\nabcdefghijk,"))
        XCTAssertThrowsError(try parse(String(repeating: "a,", count: 33) + "b\nabcdefghijk,"))
    }
    func testAtomicPlaylistImportPreservesExistingMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.json")
        let repository = try LibraryRepository(fileURL: url)
        let existing = try VideoReference(url: URL(string: "https://youtu.be/abcdefghijk")!, title: "Real title")
        _ = try await repository.apply(.saveVideo(existing))
        guard case .playlist(let videos, _) = try parse("Video ID,Time Added\nabcdefghijk,\n01234567890,\n") else { return XCTFail("playlist") }
        let playlist = LocalPlaylist(id: "import", name: "Imported", videoIDs: videos.map(\.id))
        let imported = try await repository.apply(.importPlaylist(playlist: playlist, videos: videos))
        XCTAssertEqual(imported.videos(in: "import").map(\.title), ["Real title", "01234567890"])
        let reopened = try LibraryRepository(fileURL: url)
        let restored = await reopened.snapshot(); XCTAssertEqual(restored, imported)
        do { _ = try await repository.apply(.importPlaylist(playlist: playlist, videos: videos)); XCTFail("duplicate must fail") } catch { }
        do {
            _ = try await repository.apply(.importPlaylist(playlist: LocalPlaylist(id: "mismatch", name: "Wrong", videoIDs: videos.map(\.id).reversed()), videos: videos))
            XCTFail("mismatched order must fail")
        } catch { }
        do {
            _ = try await repository.apply(.importPlaylist(playlist: LocalPlaylist(id: LocalPlaylist.watchLaterID, name: "Built in", videoIDs: videos.map(\.id)), videos: videos))
            XCTFail("built-in import must fail")
        } catch { }
        let unchanged = await repository.snapshot(); XCTAssertEqual(unchanged, imported)
    }
    func testFailedImportPersistenceLeavesMemoryUnchanged() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.json")
        let repository = try LibraryRepository(fileURL: url); let before = await repository.snapshot()
        let original = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: url); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        guard case .playlist(let videos, _) = try parse("Video ID,Time Added\nabcdefghijk,\n") else { return XCTFail("playlist") }
        do { _ = try await repository.apply(.importPlaylist(playlist: LocalPlaylist(id: "new", name: "New", videoIDs: videos.map(\.id)), videos: videos)); XCTFail("write must fail") } catch { }
        let after = await repository.snapshot(); XCTAssertEqual(before, after)
        try FileManager.default.removeItem(at: url); try original.write(to: url)
    }
    func testCancelledPreparationDoesNotReturnPreview() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try TakeoutCSV.preview(Data("Video ID,Time Added\nabcdefghijk,\n".utf8))
        }
        do { _ = try await task.value; XCTFail("cancelled parsing must fail") }
        catch is CancellationError { }
    }

}
