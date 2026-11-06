import XCTest
@testable import FlowCore

final class ChannelBrowseTests: XCTestCase {
    private let channelID = "UCabcdefghijklmnopqrstuv"
    func testInitialSelectedGridAndTabs() throws {
        let renderer: [String: Any] = ["videoId": "dQw4w9WgXcQ", "title": ["simpleText": "Example"]]
        let tab: [String: Any] = ["tabRenderer": ["title": "Videos", "selected": true, "endpoint": ["browseEndpoint": ["params": "videos-token"]], "content": ["richGridRenderer": ["contents": [["richItemRenderer": ["content": ["videoRenderer": renderer]]]]]]]]
        let root: [String: Any] = ["metadata": ["channelMetadataRenderer": ["title": "Example channel"]], "contents": ["twoColumnBrowseResultsRenderer": ["tabs": [tab]]]]
        let page = try ChannelBrowseParser.parse(JSONSerialization.data(withJSONObject: root), channelID: channelID)
        XCTAssertEqual(page.title, "Example channel")
        XCTAssertEqual(page.tabs.first?.params, "videos-token")
        XCTAssertEqual(page.feed.videos.first?.id, "dQw4w9WgXcQ")
    }
    func testRequestDoesNotMixInitialFieldsWithContinuation() throws {
        let request = try ChannelBrowseClient.request(channelID: channelID, params: "videos", continuation: "next")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["continuation"] as? String, "next")
        XCTAssertNil(body["browseId"])
        XCTAssertNil(body["params"])
        XCTAssertNil(body["query"])
        XCTAssertThrowsError(try ChannelBrowseClient.request(channelID: "invalid"))
    }
    func testUnsupportedChannelRowsKeepTabChoices() throws {
        let tab: [String: Any] = ["tabRenderer": ["title": "Home", "selected": true, "content": ["richGridRenderer": ["contents": [["unsupportedRenderer": true]]]]]]
        let root: [String: Any] = ["contents": ["twoColumnBrowseResultsRenderer": ["tabs": [tab]]]]
        let page = try ChannelBrowseParser.parse(JSONSerialization.data(withJSONObject: root), channelID: channelID)
        XCTAssertEqual(page.tabs.count, 1)
        XCTAssertTrue(page.feed.videos.isEmpty)
        XCTAssertNotNil(page.notice)
    }
    func testUnsupportedInitialContainerPreservesTabs() throws {
        let tab: [String: Any] = ["tabRenderer": ["title": "Home", "selected": true, "content": ["unknownContainer": [:] as [String: Any]]]]
        let root: [String: Any] = ["contents": ["twoColumnBrowseResultsRenderer": ["tabs": [tab]]]]
        let page = try ChannelBrowseParser.parse(JSONSerialization.data(withJSONObject: root), channelID: channelID)
        XCTAssertEqual(page.tabs.count, 1)
        XCTAssertNotNil(page.notice)
    }
}
