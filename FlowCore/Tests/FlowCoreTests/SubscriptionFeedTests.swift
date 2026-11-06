import XCTest
@testable import FlowCore

final class SubscriptionFeedTests: XCTestCase {
    private let channel = "UCabcdefghijklmnopqrstuv"
    private func feed() throws -> ChannelRSSFeed {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/">
          <author><name>Example &amp; channel</name></author>
          <entry><yt:videoId>dQw4w9WgXcQ</yt:videoId><title>Original title</title>
            <published>2026-11-01T12:00:00Z</published><updated>2026-11-05T12:00:00Z</updated>
            <link href="https://www.youtube.com/watch?v=dQw4w9WgXcQ"/>
            <media:group><media:title>Duplicate title</media:title><media:community><media:statistics views="1234"/></media:community></media:group>
          </entry>
          <entry><yt:videoId>abcdefghijk</yt:videoId><title>Short</title><published>2026-11-02T12:00:00.123Z</published><link href="https://www.youtube.com/shorts/abcdefghijk"/></entry>
          <entry><yt:videoId>invalid</yt:videoId><title>Invalid ID</title></entry>
        </feed>
        """
        return try ChannelRSSParser.parse(Data(xml.utf8), channelID: channel)
    }
    func testRSSFieldsDatesAndShorts() throws {
        let parsed = try feed()
        XCTAssertEqual(parsed.channelName, "Example & channel")
        XCTAssertEqual(parsed.uploads.count, 2)
        XCTAssertEqual(parsed.uploads[0].video.title, "Original title")
        XCTAssertEqual(parsed.uploads[0].viewCount, 1234)
        XCTAssertNil(parsed.uploads[0].isShort)
        XCTAssertEqual(parsed.uploads[1].isShort, true)
        XCTAssertEqual(parsed.uploads[0].publishedAt, ISO8601DateFormatter().date(from: "2026-11-01T12:00:00Z"))
    }
    func testMalformedAndDoctypeAreRejected() {
        for xml in ["<feed><entry>", "<html>unavailable</html>", "<!DOCTYPE feed [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><feed>&secret;</feed>"] {
            XCTAssertThrowsError(try ChannelRSSParser.parse(Data(xml.utf8), channelID: channel), xml)
        }
    }
    func testMergeDeduplicatesAndSortsPublishedNotUpdated() throws {
        let uploads = try feed().uploads
        let merged = SubscriptionFeedService.merge(uploads + uploads)
        XCTAssertEqual(merged.map(\.id), ["abcdefghijk", "dQw4w9WgXcQ"])
        XCTAssertEqual(SubscriptionFeedService.merge(uploads, maximum: 1).count, 1)
    }
    func testCacheSurvivesFailureAndUnsubscribeRemovesResults() async throws {
        let parsed = try feed()
        let fake = FeedFetchFixture(feed: parsed)
        let service = SubscriptionFeedService(fetch: { _, _ in try await fake.fetch() })
        let subscriptions = [LocalSubscription(id: channel, name: "Example")]
        let first = try await service.refresh(subscriptions: subscriptions)
        XCTAssertEqual(first.uploads.count, 2)
        _ = try await service.refresh(subscriptions: subscriptions)
        let calls = await fake.calls
        XCTAssertEqual(calls, 1)
        await fake.fail()
        let failed = try await service.refresh(subscriptions: subscriptions, force: true)
        XCTAssertEqual(failed.uploads.count, 2)
        XCTAssertNotNil(failed.failures[channel])
        XCTAssertTrue(failed.cachedChannelIDs.contains(channel))
        let removed = try await service.refresh(subscriptions: [])
        XCTAssertTrue(removed.uploads.isEmpty)
    }
}
private actor FeedFetchFixture {
    let feed: ChannelRSSFeed
    private var failing = false
    private(set) var calls = 0
    init(feed: ChannelRSSFeed) { self.feed = feed }
    func fail() { failing = true }
    func fetch() throws -> ChannelRSSFeed {
        calls += 1
        if failing { throw RSSFeedError.malformed }
        return feed
    }
}
