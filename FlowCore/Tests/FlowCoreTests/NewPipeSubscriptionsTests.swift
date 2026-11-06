import Foundation
import XCTest
@testable import FlowCore

final class NewPipeSubscriptionsTests: XCTestCase {
    private let channel = "UCabcdefghijklmnopqrstuv"
    func testPreviewFiltersDeduplicatesAndReportsUnresolvedHandles() throws {
        let data = try JSONSerialization.data(withJSONObject: ["subscriptions": [
            ["service_id": 0, "url": "https://www.youtube.com/channel/\(channel)", "name": " Example "],
            ["url": "youtube.com/channel/\(channel)", "name": "Duplicate"],
            ["url": "https://youtube.com/@example", "name": "Handle"],
            ["url": "https://youtube.com/user/example", "name": "Legacy"],
            ["url": "https://youtube.com.evil.test/channel/\(channel)", "name": "Spoof"],
            ["service_id": 1, "url": "https://youtube.com/channel/\(channel)", "name": "Other service"]
        ]])
        let preview = try NewPipeSubscriptions.preview(data)
        XCTAssertEqual(preview.subscriptions.map(\.id), [channel])
        XCTAssertEqual(preview.subscriptions.first?.name, "Example")
        XCTAssertEqual(preview.unresolvedURLs.count, 2)
        XCTAssertEqual(preview.skipped, 3)
    }
    func testWrongFormatAndCredentialURLsDoNotImport() throws {
        XCTAssertThrowsError(try NewPipeSubscriptions.preview(Data("{}".utf8)))
        let data = try JSONSerialization.data(withJSONObject: ["subscriptions": [["url": "https://user@youtube.com/channel/\(channel)"]]])
        XCTAssertTrue(try NewPipeSubscriptions.preview(data).subscriptions.isEmpty)
    }
    func testExportRoundTripAndExactNewPipeKeys() throws {
        let exported = try NewPipeSubscriptions.export([LocalSubscription(id: channel, name: "Example"), LocalSubscription(id: "@unresolved", name: "Handle")])
        XCTAssertEqual(exported.skipped, 1)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: exported.data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["app_version", "app_version_int", "subscriptions"])
        let items = try XCTUnwrap(object["subscriptions"] as? [[String: Any]])
        XCTAssertEqual(Set(items[0].keys), ["service_id", "url", "name"])
        XCTAssertEqual(try NewPipeSubscriptions.preview(exported.data).subscriptions.first?.id, channel)
    }
    func testAtomicImportPreservesPreferencesAndRejectsWholeInvalidBatch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try LibraryRepository(fileURL: directory.appendingPathComponent("library.json"))
        let oldDate = Date(timeIntervalSince1970: 10)
        _ = try await repository.apply(.subscribe(LocalSubscription(id: channel, name: "Old", subscribedAt: oldDate, isMusic: true, notificationsEnabled: true)))
        let merged = try await repository.apply(.importSubscriptions([LocalSubscription(id: channel, name: "New")]))
        XCTAssertEqual(merged.subscriptions.first?.name, "New")
        XCTAssertEqual(merged.subscriptions.first?.subscribedAt, oldDate)
        XCTAssertEqual(merged.subscriptions.first?.notificationsEnabled, true)
        do {
            _ = try await repository.apply(.importSubscriptions([LocalSubscription(id: channel, name: "Must not save"), LocalSubscription(id: "invalid", name: "Bad")]))
            XCTFail("Invalid batch should fail")
        } catch LibraryError.invalidData { }
        let after = await repository.snapshot()
        XCTAssertEqual(after, merged)
    }
    func testExportRejectsOverLimitWithoutTruncation() throws {
        let subscription = LocalSubscription(id: channel, name: "Example")
        XCTAssertThrowsError(try NewPipeSubscriptions.export(Array(repeating: subscription, count: NewPipeSubscriptions.maximumEntries + 1)))
        let tooLong = LocalSubscription(id: channel, name: String(repeating: "x", count: NewPipeSubscriptions.maximumBytes + 1))
        XCTAssertThrowsError(try NewPipeSubscriptions.export([tooLong]))
    }
    func testMalformedTypedEntryRejectsWholePreview() throws {
        let data = try JSONSerialization.data(withJSONObject: ["subscriptions": [
            ["url": "https://youtube.com/channel/\(channel)", "name": "Valid"],
            ["url": "https://youtube.com/channel/\(channel)", "name": 123]
        ]])
        XCTAssertThrowsError(try NewPipeSubscriptions.preview(data))
    }
}
