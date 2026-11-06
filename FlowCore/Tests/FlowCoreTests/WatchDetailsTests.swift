import XCTest
@testable import FlowCore
final class WatchDetailsTests: XCTestCase {
    typealias Object = [String: Any]
    func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    func root(_ contents: [Any] = [], related: [Any]? = nil, panels: [Any] = []) -> Object {
        var watch: Object = ["results": ["results": ["contents": contents]]]
        if let related { watch["secondaryResults"] = ["secondaryResults": ["results": related]] }
        return ["contents": ["twoColumnWatchNextResults": watch], "engagementPanels": panels]
    }
    func compact(_ id: String = "abcdefghijk") -> Object { ["compactVideoRenderer": ["videoId": id, "title": ["simpleText": "Related"]]] }
    func panel(_ items: [Any], id: String = "engagement-panel-structured-description") -> Object {
        ["engagementPanelSectionListRenderer": ["panelIdentifier": id, "content": ["structuredDescriptionContentRenderer": ["items": items]]]]
    }
    func testPrimaryDescriptionAndServerFormattedCounts() throws {
        let primary: Object = ["videoPrimaryInfoRenderer": ["title": ["runs": [["text": "Title"]]], "dateText": ["simpleText": "Premiered Nov 1"], "viewCount": ["videoViewCountRenderer": ["viewCount": ["simpleText": "1.2M views"], "originalViewCount": "0"]]]]
        let secondary: Object = ["videoSecondaryInfoRenderer": ["attributedDescription": ["content": "Text <script>not executable</script>"]]]
        let details = try WatchDetailsParser.parse(data(root([primary, secondary], related: [])))
        XCTAssertEqual(details.title, "Title"); XCTAssertEqual(details.views, "1.2M views")
        XCTAssertEqual(details.description, "Text <script>not executable</script>"); XCTAssertEqual(details.published, "Premiered Nov 1")
        XCTAssertTrue(details.related.isEmpty); XCTAssertNil(details.relatedNotice)
    }
    func testStructuredFallbackFactoidsAndValidatedChannel() throws {
        let items: [Any] = [
            ["expandableVideoDescriptionBodyRenderer": ["attributedDescriptionBodyText": ["content": "Fallback"]]],
            ["videoDescriptionHeaderRenderer": ["factoid": [["factoidRenderer": ["value": ["simpleText": "123"], "label": ["simpleText": "Likes"]]], ["wrapper": ["factoid": ["factoidRenderer": ["value": "Today", "label": "Published"]]]]]]],
            ["videoDescriptionInfocardsSectionRenderer": ["sectionTitle": "Channel", "sectionSubtitle": "10 subscribers", "channelEndpoint": ["browseEndpoint": ["browseId": "UCabcdefghijklmnopqrstuv"]]]]
        ]
        let details = try WatchDetailsParser.parse(data(root(panels: [panel(items)])))
        XCTAssertEqual(details.description, "Fallback"); XCTAssertEqual(details.facts.count, 2)
        XCTAssertEqual(details.channel?.id, "UCabcdefghijklmnopqrstuv"); XCTAssertEqual(details.channel?.subscribers, "10 subscribers")
    }
    func testUnrelatedPanelsNotUsedAndUnsafeChannelNotNavigable() throws {
        let secondary: Object = ["videoSecondaryInfoRenderer": ["owner": ["videoOwnerRenderer": ["title": ["runs": [["text": "Owner"]]], "navigationEndpoint": ["browseEndpoint": ["browseId": "javascript:bad"]]]]]]
        let fake: Object = ["expandableVideoDescriptionBodyRenderer": ["attributedDescriptionBodyText": ["content": "Wrong panel"]]]
        let details = try WatchDetailsParser.parse(data(root([secondary], panels: [panel([fake], id: "wrong")])) )
        XCTAssertNil(details.description); XCTAssertEqual(details.channel?.name, "Owner"); XCTAssertNil(details.channel?.id)
    }
    func testRelatedWrappersLockupsDedupAndUnsupported() throws {
        let lockup: Object = ["lockupViewModel": ["contentId": "lmnopqrstuv", "contentType": "LOCKUP_CONTENT_TYPE_VIDEO", "metadata": ["lockupMetadataViewModel": ["title": ["content": "Modern"]]]]]
        let playlist: Object = ["lockupViewModel": ["contentId": "PLabcdefghijk", "contentType": "LOCKUP_CONTENT_TYPE_PLAYLIST"]]
        let values: [Any] = [compact(), ["compactAutoplayRenderer": ["contents": [compact(), lockup]]], ["itemSectionRenderer": ["contents": [playlist, 42]]]]
        let details = try WatchDetailsParser.parse(data(root(related: values)))
        XCTAssertEqual(details.related.map(\.id), ["abcdefghijk", "lmnopqrstuv"]); XCTAssertNotNil(details.relatedNotice)
    }
    func testUnknownVersusExplicitEmptyRelatedSection() throws {
        XCTAssertThrowsError(try WatchDetailsParser.parse(data(root())))
        let empty = try WatchDetailsParser.parse(data(root(related: [])))
        XCTAssertNil(empty.relatedNotice)
        let unsupported = try WatchDetailsParser.parse(data(root(related: [["unknown": [:]]])))
        XCTAssertNotNil(unsupported.relatedNotice)
        XCTAssertThrowsError(try WatchDetailsParser.parse(data(["error": ["code": 403]])))
    }
    func testDoesNotReadRelatedFromPrimaryOrOtherPaths() throws {
        let primary: Object = ["videoPrimaryInfoRenderer": ["title": ["simpleText": "T"]], "itemSectionRenderer": ["contents": [compact()]]]
        let details = try WatchDetailsParser.parse(data(root([primary])))
        XCTAssertTrue(details.related.isEmpty); XCTAssertNotNil(details.relatedNotice)
    }
    func testDeepRelatedContainersAreBounded() throws {
        var nested: Object = compact()
        for _ in 0..<20 { nested = ["itemSectionRenderer": ["contents": [nested]]] }
        let details = try WatchDetailsParser.parse(data(root(related: [nested])))
        XCTAssertTrue(details.related.isEmpty); XCTAssertNotNil(details.relatedNotice)
    }
    func testMalformedVideoAlongsideValidVideoIsPartial() throws {
        let details = try WatchDetailsParser.parse(data(root(related: [compact(), compact("not-valid") ])))
        XCTAssertEqual(details.related.count, 1); XCTAssertNotNil(details.relatedNotice)
        let duplicate = try WatchDetailsParser.parse(data(root(related: [compact(), compact()])))
        XCTAssertEqual(duplicate.related.count, 1); XCTAssertNil(duplicate.relatedNotice)
    }

    func testInjectedRawVideoIDIsNotNormalizedIntoAnotherVideo() throws {
        let details = try WatchDetailsParser.parse(data(root(related: [compact(), compact("abcdefghijk&junk=1") ])))
        XCTAssertEqual(details.related.map(\.id), ["abcdefghijk"]); XCTAssertNotNil(details.relatedNotice)
        let normalized: Object = ["onResponseReceivedCommands": [["appendContinuationItemsAction": ["continuationItems": [["videoRenderer": ["videoId": "abcdefghijk&junk=1", "title": ["simpleText": "Injected"]]]]]]]]
        XCTAssertThrowsError(try VideoSearchParser.parse(data(normalized)))
    }

    func testMalformedFirstInfocardDoesNotHideLaterChannel() throws {
        let items: [Any] = [["videoDescriptionInfocardsSectionRenderer": ["sectionTitle": "   "]],
            ["videoDescriptionInfocardsSectionRenderer": ["sectionTitle": "Valid second channel", "channelEndpoint": ["browseEndpoint": ["browseId": "UCabcdefghijklmnopqrstuv"]]]]]
        let details = try WatchDetailsParser.parse(data(root(panels: [panel(items)])))
        XCTAssertEqual(details.channel?.name, "Valid second channel")
        XCTAssertEqual(details.channel?.id, "UCabcdefghijklmnopqrstuv")
    }

}
