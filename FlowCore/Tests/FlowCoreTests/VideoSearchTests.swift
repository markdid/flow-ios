import XCTest
@testable import FlowCore

final class VideoSearchTests: XCTestCase {
    private func data(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private var item: [String: Any] {
        ["videoRenderer": ["videoId": "dQw4w9WgXcQ", "title": ["runs": [["text": "Example "] , ["text": "video"]]]]]
    }
    func testFirstPageDeduplicatesAndIgnoresUnrelatedNodes() throws {
        let response: [String: Any] = ["contents": ["twoColumnSearchResultsRenderer": ["primaryContents": ["sectionListRenderer": ["contents": [["itemSectionRenderer": ["contents": [item, item, ["unknownRenderer": item]]]]]]]]]]
        let page = try VideoSearchParser.parse(data(response))
        XCTAssertEqual(page.videos.count, 1)
        XCTAssertEqual(page.videos.first?.title, "Example video")
    }
    func testContinuationPageAndToken() throws {
        let token: [String: Any] = ["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": "next-page"]]]]
        let response: [String: Any] = ["onResponseReceivedCommands": [["appendContinuationItemsAction": ["continuationItems": [item, token]]]]]
        let page = try VideoSearchParser.parse(data(response))
        XCTAssertEqual(page.videos.count, 1)
        XCTAssertEqual(page.continuation, "next-page")
    }
    func testUnknownLayoutAndServiceErrorsAreNotEmptySuccess() throws {
        XCTAssertThrowsError(try VideoSearchParser.parse(data(["unrecognized": true])))
        XCTAssertThrowsError(try VideoSearchParser.parse(data(["error": ["code": 403]])))
    }
    func testRequestOmitsQueryOnContinuation() throws {
        let request = try VideoSearchClient.request(query: "cats", continuation: "token")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["continuation"] as? String, "token")
        XCTAssertNil(body["query"])
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertThrowsError(try VideoSearchClient.request(query: "  "))
    }
    func testMixedArraysKeepValidEntries() throws {
        let entries: [Any] = [NSNull(), 42, item]
        let response: [String: Any] = ["onResponseReceivedCommands": [false, ["appendContinuationItemsAction": ["continuationItems": entries]]] as [Any]]
        let page = try VideoSearchParser.parse(data(response))
        XCTAssertEqual(page.videos.count, 1)
    }
    func testEmptyCommandsAreUnsupportedButEmptyFeedIsValid() throws {
        XCTAssertThrowsError(try VideoSearchParser.parse(data(["onResponseReceivedCommands": []])))
        XCTAssertThrowsError(try VideoSearchParser.parse(data(["onResponseReceivedCommands": [["unknownCommand": true]]])))
        let page = try VideoSearchParser.parse(data(["onResponseReceivedCommands": [["appendContinuationItemsAction": ["continuationItems": []]]]]))
        XCTAssertTrue(page.videos.isEmpty)
    }
    func testUnknownRendererIsReported() throws {
        XCTAssertThrowsError(try VideoSearchParser.parse(data(["onResponseReceivedCommands": [["appendContinuationItemsAction": ["continuationItems": [["unknownRenderer": true]]]]]])))
    }
    func testFilterParsingAndRequest() throws {
        let filter: [String: Any] = ["searchFilterRenderer": ["label": ["simpleText": "This week"], "status": "FILTER_STATUS_SELECTED", "navigationEndpoint": ["searchEndpoint": ["params": "EgIIAw%3D%3D"]]]]
        let group: [String: Any] = ["searchFilterGroupRenderer": ["title": ["simpleText": "Upload date"], "filters": [filter]]]
        let header: [String: Any] = ["searchHeaderRenderer": ["searchFilterButton": ["buttonRenderer": ["command": ["openPopupAction": ["popup": ["searchFilterOptionsDialogRenderer": ["groups": [group]]]]]]]]]
        let page = try VideoSearchParser.parse(data(["header": header, "onResponseReceivedCommands": [["appendContinuationItemsAction": ["continuationItems": [item]]]]]))
        XCTAssertEqual(page.filterGroups.first?.title, "Upload date")
        XCTAssertEqual(page.filterGroups.first?.options.first?.params, "EgIIAw%3D%3D")
        XCTAssertEqual(page.filterGroups.first?.options.first?.selected, true)
        let request = try VideoSearchClient.request(query: "cats", params: "EgIIAw%3D%3D")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["params"] as? String, "EgIIAw%3D%3D")
        let continuation = try VideoSearchClient.request(query: "cats", continuation: "next", params: "old")
        let continuationBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(continuation.httpBody)) as? [String: Any])
        XCTAssertNil(continuationBody["params"])
    }
    func testLockupVideoAndShelfVideoRenderers() throws {
        let lockup: [String: Any] = ["lockupViewModel": ["contentId": "abcdefghijk", "contentType": "LOCKUP_CONTENT_TYPE_VIDEO", "metadata": ["lockupMetadataViewModel": ["title": ["content": "Modern video"]]]]]
        let shelf: [String: Any] = ["shelfRenderer": ["content": ["horizontalListRenderer": ["items": [item]]]]]
        let root: [String: Any] = ["onResponseReceivedCommands": [["appendContinuationItemsAction": ["continuationItems": [lockup, shelf]]]]]
        let page = try VideoSearchParser.parse(data(root))
        XCTAssertEqual(page.videos.map(\.title), ["Modern video", "Example video"])
        XCTAssertEqual(page.presentation["abcdefghijk"]?.thumbnailURL.host, "i.ytimg.com")
    }
}
