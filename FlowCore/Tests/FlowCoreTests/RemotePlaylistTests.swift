import XCTest
@testable import FlowCore
final class RemotePlaylistTests: XCTestCase {
    let id = "PLabcdefghijklmnopqrstuv"
    func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    func lockup(_ id: String = "abcdefghijk") -> [String: Any] {
        ["lockupViewModel": ["contentId": id, "contentType": "LOCKUP_CONTENT_TYPE_VIDEO", "metadata": ["lockupMetadataViewModel": ["title": ["content": "Example"]]]]]
    }
    func testIDsRejectForeignMixPrivateAndInjection() throws {
        XCTAssertEqual(try RemotePlaylistID("https://www.youtube.com/playlist?list=\(id)").value, id)
        for invalid in ["RDabcdefghijk", "WL", "https://evil.test/playlist?list=\(id)", "https://youtube.com:443/playlist?list=\(id)", "PLabc/../123456", "http://youtube.com/playlist?list=\(id)"] { XCTAssertThrowsError(try RemotePlaylistID(invalid)) }
    }
    func testRequestContinuationOmitsBrowseAndParams() throws {
        let parsed = try RemotePlaylistID(id)
        let initial = try RemotePlaylistClient.request(id: parsed, showUnavailable: true)
        let body = try JSONSerialization.jsonObject(with: initial.httpBody!) as! [String: Any]
        XCTAssertEqual(body["browseId"] as? String, "VL" + id)
        XCTAssertEqual(body["params"] as? String, "wgYCCAA=")
        let next = try RemotePlaylistClient.request(id: parsed, continuation: "next", showUnavailable: true)
        let nextBody = try JSONSerialization.jsonObject(with: next.httpBody!) as! [String: Any]
        XCTAssertNil(nextBody["browseId"]); XCTAssertNil(nextBody["params"]); XCTAssertNil(nextBody["query"])
        XCTAssertEqual(nextBody["continuation"] as? String, "next")
    }
    func testModernListAndMalformedSibling() throws {
        let root: [String: Any] = ["header": ["pageHeaderRenderer": ["pageTitle": "A playlist"]], "contents": ["itemSectionRenderer": ["contents": [lockup(), 42, lockup()]]]]
        let page = try RemotePlaylistParser.parse(data(root))
        XCTAssertEqual(page.title, "A playlist"); XCTAssertEqual(page.feed.videos.count, 1); XCTAssertFalse(page.isShortsGrid)
    }
    func testContinuationViewModel() throws {
        let continuation: [String: Any] = ["continuationItemViewModel": ["continuationCommand": ["innertubeCommand": ["continuationCommand": ["token": "token2"]]]]]
        let root: [String: Any] = ["onResponseReceivedActions": [["appendContinuationItemsAction": ["continuationItems": [lockup(), continuation]]]]]
        let page = try RemotePlaylistParser.parse(data(root))
        XCTAssertEqual(page.feed.continuation, "token2"); XCTAssertEqual(page.feed.videos.count, 1)
    }
    func testShortsGridAndLegacyUnavailable() throws {
        let grid: [String: Any] = ["contents": ["itemSectionRenderer": ["contents": [["richGridRenderer": ["contents": [["richItemRenderer": ["content": lockup()]]]]]]]]]
        XCTAssertTrue(try RemotePlaylistParser.parse(data(grid)).isShortsGrid)
        let list: [String: Any] = ["contents": ["playlistVideoListRenderer": ["contents": [["playlistVideoRenderer": ["videoId": "abcdefghijk", "title": ["simpleText": "hidden"], "isPlayable": false]]]]]]
        XCTAssertTrue(try RemotePlaylistParser.parse(data(list)).feed.videos.isEmpty)
    }
    func testUnsupportedVersusExplicitEmpty() throws {
        XCTAssertThrowsError(try RemotePlaylistParser.parse(data(["contents": ["unknown": []]])))
        XCTAssertThrowsError(try RemotePlaylistParser.parse(data(["onResponseReceivedActions": []])))
        let empty: [String: Any] = ["onResponseReceivedActions": [["appendContinuationItemsAction": ["continuationItems": []]]]]
        XCTAssertTrue(try RemotePlaylistParser.parse(data(empty)).feed.videos.isEmpty)
    }
    func testMalformedOnlyAndTraversalBudgetFail() throws {
        let malformed: [String: Any] = ["onResponseReceivedActions": [["appendContinuationItemsAction": ["continuationItems": [42, "not an object"]]]]]
        XCTAssertThrowsError(try RemotePlaylistParser.parse(data(malformed)))
        var nested: [String: Any] = ["playlistVideoListRenderer": ["contents": []]]
        for _ in 0..<50 { nested = ["child": nested] }
        XCTAssertThrowsError(try RemotePlaylistParser.parse(data(["contents": nested])))
    }

    func testEmptyPrimaryAndIgnoreSecondaryRecommendations() throws {
        let primary: [String: Any] = ["sectionListRenderer": ["contents": [["itemSectionRenderer": ["contents": []]]]]]
        let root: [String: Any] = ["contents": ["twoColumnBrowseResultsRenderer": [
            "tabs": [["tabRenderer": ["selected": true, "content": primary]]],
            "secondaryContents": ["itemSectionRenderer": ["contents": [lockup()]]]
        ]]]
        XCTAssertTrue(try RemotePlaylistParser.parse(data(root)).feed.videos.isEmpty)
        let unsupported: [String: Any] = ["contents": ["twoColumnBrowseResultsRenderer": [
            "tabs": [["tabRenderer": ["selected": true, "content": ["unknown": []]]]],
            "secondaryContents": ["itemSectionRenderer": ["contents": [lockup()]]]
        ]]]
        XCTAssertThrowsError(try RemotePlaylistParser.parse(data(unsupported)))
    }

}
