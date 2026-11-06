import XCTest
@testable import FlowCore
final class VideoCommentsTests: XCTestCase {
    typealias Object = [String: Any]
    func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    func command(_ token: String) -> Object { ["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": token]]]] }
    func response(_ items: [Any], mutations: [Any] = []) -> Object {
        ["onResponseReceivedEndpoints": [["appendContinuationItemsAction": ["continuationItems": items]]], "frameworkUpdates": ["entityBatchUpdate": ["mutations": mutations]]]
    }
    func legacy(_ id: String = "c1") -> Object {
        ["commentThreadRenderer": ["comment": ["commentRenderer": ["commentId": id, "authorText": ["simpleText": "A"], "contentText": ["runs": [["text": "Hello "], ["text": "world"]]], "voteCount": ["simpleText": "12"], "publishedTimeText": ["simpleText": "1 day ago"]]]]]
    }
    func testSeedOnlyUsesCommentsSection() throws {
        let root: Object = ["contents": ["twoColumnWatchNextResults": ["results": ["results": ["contents": [
            ["itemSectionRenderer": ["sectionIdentifier": "recommendations", "contents": [command("wrong")]]],
            ["itemSectionRenderer": ["sectionIdentifier": "comment-item-section", "contents": [command("comments")]]]
        ]]]]]]
        XCTAssertEqual(try VideoCommentsParser.seed(data(root)).token, "comments")
        XCTAssertThrowsError(try VideoCommentsParser.seed(data(["contents": ["comments": command("wrong")]])))
    }
    func testLegacyMalformedSiblingAndDedup() throws {
        let page = try VideoCommentsParser.parse(data(response([legacy(), 42, legacy(), command("next")])))
        XCTAssertEqual(page.comments.count, 1); XCTAssertEqual(page.comments.first?.text, "Hello world")
        XCTAssertEqual(page.comments.first?.likes, "12"); XCTAssertEqual(page.continuation, "next")
    }
    func testModernMutationAndReplyButton() throws {
        let thread: Object = ["commentThreadRenderer": ["renderingPriority": "RENDERING_PRIORITY_PINNED_COMMENT", "commentViewModel": ["commentViewModel": ["commentKey": "entity"]], "replies": ["commentRepliesRenderer": ["contents": [["continuationItemRenderer": ["button": ["buttonRenderer": ["command": ["continuationCommand": ["token": "replies"]]]]]]]]]]]
        let mutation: Object = ["entityKey": "entity", "payload": ["commentEntityPayload": ["properties": ["commentId": "modern", "content": ["content": "Plain <script>text</script>"], "publishedTime": "today"], "author": ["displayName": "Creator"], "toolbar": ["likeCountNotliked": "5"]]]]
        let page = try VideoCommentsParser.parse(data(response([thread], mutations: [mutation])))
        XCTAssertEqual(page.comments.first?.id, "modern"); XCTAssertEqual(page.comments.first?.author, "Creator")
        XCTAssertEqual(page.comments.first?.text, "Plain <script>text</script>")
        XCTAssertEqual(page.comments.first?.repliesToken, "replies"); XCTAssertEqual(page.comments.first?.pinned, true)
    }
    func testReplyModernUnwrappedAndLegacy() throws {
        let model: Object = ["commentViewModel": ["commentKey": "reply"]]
        let mutation: Object = ["entityKey": "reply", "payload": ["commentEntityPayload": ["properties": ["commentId": "r1", "content": ["content": "Reply"]]]]]
        let legacyReply: Object = ["commentRenderer": ["commentId": "r2", "contentText": ["simpleText": "Old reply"]]]
        let page = try VideoCommentsParser.parse(data(response([model, legacyReply], mutations: [mutation])), replies: true)
        XCTAssertEqual(page.comments.map(\.id), ["r1", "r2"])
        XCTAssertThrowsError(try VideoCommentsParser.parse(data(response([model], mutations: [mutation]))))
    }
    func testSplitHeaderReloadAndAppendWithSort() throws {
        let header: Object = ["commentsHeaderRenderer": ["commentsCount": ["simpleText": "10 comments"], "sortMenu": ["sortFilterSubMenuRenderer": ["subMenuItems": [["title": "Newest", "selected": true, "serviceEndpoint": ["continuationCommand": ["token": "new"]]], ["title": "Missing token"]]]]]]
        let root: Object = ["onResponseReceivedEndpoints": [["reloadContinuationItemsCommand": ["continuationItems": [header]]], ["appendContinuationItemsAction": ["continuationItems": [legacy()]]]]]
        let page = try VideoCommentsParser.parse(data(root))
        XCTAssertEqual(page.comments.count, 1); XCTAssertEqual(page.totalText, "10 comments")
        XCTAssertEqual(page.sorts.count, 1); XCTAssertEqual(page.sorts.first?.selected, true); XCTAssertEqual(page.sorts.first?.token, "new")
    }
    func testExplicitEmptyVersusUnsupportedAndMissingEntity() throws {
        XCTAssertTrue(try VideoCommentsParser.parse(data(response([]))).comments.isEmpty)
        XCTAssertThrowsError(try VideoCommentsParser.parse(data(["onResponseReceivedEndpoints": []])))
        XCTAssertThrowsError(try VideoCommentsParser.parse(data(response([42, ["unknown": "shape"]]))))
        let missing: Object = ["commentThreadRenderer": ["commentViewModel": ["commentKey": "missing"]]]
        XCTAssertThrowsError(try VideoCommentsParser.parse(data(response([["commentsHeaderRenderer": [:]], missing]))))
    }
    func testRequestUsesReadOnlyNextAndExclusiveFields() throws {
        let first = try VideoCommentsClient.request(videoID: "abcdefghijk")
        XCTAssertEqual(first.url?.path, "/youtubei/v1/next")
        let body = try JSONSerialization.jsonObject(with: first.httpBody!) as! Object
        XCTAssertEqual(body["videoId"] as? String, "abcdefghijk"); XCTAssertNil(body["query"]); XCTAssertNil(body["continuation"])
        let more = try VideoCommentsClient.request(continuation: "token")
        let next = try JSONSerialization.jsonObject(with: more.httpBody!) as! Object
        XCTAssertEqual(next["continuation"] as? String, "token"); XCTAssertNil(next["videoId"])
        XCTAssertThrowsError(try VideoCommentsClient.request())
        XCTAssertThrowsError(try VideoCommentsClient.request(videoID: "abcdefghijk", continuation: "token"))
        XCTAssertThrowsError(try VideoCommentsClient.request(videoID: "abcdefghijk&other=1"))
        XCTAssertThrowsError(try VideoCommentsClient.request(continuation: ""))
    }
    func testPanelFallbackHeader() throws {
        let root: Object = ["contents": ["twoColumnWatchNextResults": ["results": ["results": ["contents": [["itemSectionRenderer": ["sectionIdentifier": "comment-item-section", "contents": [command("seed")]]]]]]]],
            "engagementPanels": [["engagementPanelSectionListRenderer": ["panelIdentifier": "engagement-panel-comments-section", "header": ["engagementPanelTitleHeaderRenderer": ["contextualInfo": ["simpleText": "20 comments"], "menu": ["sortFilterSubMenuRenderer": ["subMenuItems": [["title": "Top", "serviceEndpoint": ["continuationCommand": ["token": "top"]]]]]]]]]]]]
        let seed = try VideoCommentsParser.seed(data(root))
        XCTAssertEqual(seed.totalText, "20 comments"); XCTAssertEqual(seed.sorts.first?.token, "top")
    }
    func testEmptyPinTextDoesNotCreatePinnedBadge() throws {
        let item: Object = ["commentThreadRenderer": ["commentViewModel": ["commentKey": "entity", "pinnedText": ["content": "  "]]]]
        let mutation: Object = ["entityKey": "entity", "payload": ["commentEntityPayload": ["properties": ["commentId": "id", "content": ["content": "text"]]]]]
        XCTAssertFalse(try VideoCommentsParser.parse(data(response([item], mutations: [mutation]))).comments[0].pinned)
    }

    func testOversizedTokensRejectedDuringParsing() throws {
        let huge = String(repeating: "x", count: 100_001)
        let header: Object = ["commentsHeaderRenderer": ["sortMenu": ["sortFilterSubMenuRenderer": ["subMenuItems": [["title": "Huge", "serviceEndpoint": ["continuationCommand": ["token": huge]]]]]]]]
        var threaded = legacy()
        var thread = threaded["commentThreadRenderer"] as! Object
        thread["replies"] = ["commentRepliesRenderer": ["contents": [command(huge)]]]
        threaded["commentThreadRenderer"] = thread
        let page = try VideoCommentsParser.parse(data(response([threaded, command(huge), header])))
        XCTAssertNil(page.continuation); XCTAssertNil(page.comments[0].repliesToken); XCTAssertTrue(page.sorts.isEmpty)
        XCTAssertEqual(page.omittedEntries, 1)
        let seed: Object = ["contents": ["twoColumnWatchNextResults": ["results": ["results": ["contents": [["itemSectionRenderer": ["sectionIdentifier": "comment-item-section", "contents": [command(huge)]]]]]]]]]
        XCTAssertThrowsError(try VideoCommentsParser.seed(data(seed)))
    }
    func testMixedUnsupportedCommentsAreMarkedPartial() throws {
        let missing: Object = ["commentThreadRenderer": ["commentViewModel": ["commentKey": "missing"]]]
        let page = try VideoCommentsParser.parse(data(response([legacy(), missing, 42])))
        XCTAssertEqual(page.comments.count, 1); XCTAssertEqual(page.omittedEntries, 2)
    }

}
