import Foundation
import XCTest
@testable import FlowCore

final class SponsorBlockTests: XCTestCase {
    func testParserFiltersUnknownMuteInvalidAndDuplicateSegments() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            ["UUID": "sponsor", "category": "sponsor", "actionType": "skip", "segment": [10, 20]],
            ["UUID": "sponsor", "category": "sponsor", "actionType": "skip", "segment": [10, 20]],
            ["UUID": "intro", "category": "intro", "actionType": "skip", "segment": [0, 4]],
            ["UUID": "mute", "category": "sponsor", "actionType": "mute", "segment": [5, 6]],
            ["UUID": "bad", "category": "sponsor", "actionType": "skip", "segment": [7, 2]],
            ["UUID": "point", "category": "poi_highlight", "actionType": "skip", "segment": [3, 3]]
        ])
        XCTAssertEqual(try SponsorBlockParser.parse(data).map(\.id), ["intro", "sponsor"])
    }
    func testSkipOnceDoesNotLoopOrAutoSkipWhilePaused() {
        let segment = SponsorSegment(id: "one", category: "sponsor", start: 10, end: 20)
        var state = SponsorSkipSession(segments: [segment])
        XCTAssertNil(state.automaticTarget(at: 12, isPlaying: false, duration: 100))
        XCTAssertEqual(state.automaticTarget(at: 12, isPlaying: true, duration: 100), segment)
        XCTAssertNil(state.automaticTarget(at: 19.9, isPlaying: true, duration: 100))
        XCTAssertNil(state.automaticTarget(at: 11, isPlaying: true, duration: 100))
        XCTAssertEqual(state.current(at: 11), segment)
        XCTAssertNil(state.current(at: 20))
        XCTAssertNil(state.current(at: .nan))
    }
    func testManualSkipMarksOnceAndNewSessionResets() {
        let segment = SponsorSegment(id: "one", category: "sponsor", start: 10, end: 20)
        var state = SponsorSkipSession(segments: [segment])
        state.markSkipped(segment)
        XCTAssertNil(state.automaticTarget(at: 15, isPlaying: true, duration: 100))
        var fresh = SponsorSkipSession(segments: [segment])
        XCTAssertNotNil(fresh.automaticTarget(at: 15, isPlaying: true, duration: 100))
    }
    func testRequestOnlyContactsSponsorBlockAndRequestsSkipActions() throws {
        let request = try SponsorBlockClient.request(videoID: "abcdefghijk")
        XCTAssertEqual(request.url?.host, "sponsor.ajay.app")
        let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "videoID" }?.value, "abcdefghijk")
        XCTAssertEqual(query.first { $0.name == "actionTypes" }?.value, "[\"skip\"]")
        XCTAssertThrowsError(try SponsorBlockClient.request(videoID: "abcdefghijk&other=true"))
    }
    func testBooleanTimesAreNotNumbers() throws {
        let data = try JSONSerialization.data(withJSONObject: [["UUID": "bad", "category": "sponsor", "actionType": "skip", "segment": [true, false]]])
        XCTAssertTrue(try SponsorBlockParser.parse(data).isEmpty)
    }
    func testOutOfRangeEndCannotProduceAutomaticOrManualSeek() {
        let bad = SponsorSegment(id: "bad", category: "sponsor", start: 10, end: 200)
        var state = SponsorSkipSession(segments: [bad])
        XCTAssertNil(state.automaticTarget(at: 15, isPlaying: true, duration: 100))
        XCTAssertNil(state.manualTarget(at: 15, duration: 100))
        XCTAssertTrue(state.skippedOnce.isEmpty)
    }
    func testUnknownDurationDefersSkippingWithoutDiscardingSegments() {
        let valid = SponsorSegment(id: "valid", category: "sponsor", start: 10, end: 20)
        var state = SponsorSkipSession(segments: [valid])
        for unknown: Double? in [nil, 0, -1, .nan, .infinity] {
            XCTAssertNil(state.automaticTarget(at: 15, isPlaying: true, duration: unknown))
            XCTAssertNil(state.manualTarget(at: 15, duration: unknown))
        }
        XCTAssertEqual(state.segments, [valid])
        XCTAssertEqual(state.automaticTarget(at: 15, isPlaying: true, duration: 100), valid)
    }
    func testExactEndIsValidAndBadOverlapDoesNotHideValidSegment() {
        let bad = SponsorSegment(id: "bad", category: "sponsor", start: 1, end: 200)
        let valid = SponsorSegment(id: "valid", category: "outro", start: 10, end: 100)
        var state = SponsorSkipSession(segments: [bad, valid])
        XCTAssertEqual(state.manualTarget(at: 15, duration: 100), valid)
        XCTAssertFalse(valid.canSkip(duration: 99.9))
        XCTAssertNil(state.manualTarget(at: 100, duration: 100))
    }
}
