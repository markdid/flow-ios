import XCTest
@testable import FlowCore
final class PlaybackStartPolicyTests: XCTestCase {
    func testPauseWhileResolvingFirstSourceWins() {
        XCTAssertFalse(PlaybackStartPolicy.shouldStart(firstSource: true, requested: false, pendingPlay: false, actualRate: 0, waiting: false))
        XCTAssertTrue(PlaybackStartPolicy.shouldStart(firstSource: true, requested: true, pendingPlay: true, actualRate: 0, waiting: false))
    }
    func testReplacingPausedSourceDoesNotInventPlayIntent() {
        XCTAssertFalse(PlaybackStartPolicy.shouldStart(firstSource: false, requested: true, pendingPlay: false, actualRate: 0, waiting: false))
        XCTAssertTrue(PlaybackStartPolicy.shouldStart(firstSource: false, requested: false, pendingPlay: true, actualRate: 0, waiting: false))
        XCTAssertTrue(PlaybackStartPolicy.shouldStart(firstSource: false, requested: true, pendingPlay: false, actualRate: 0, waiting: true))
        XCTAssertTrue(PlaybackStartPolicy.shouldStart(firstSource: false, requested: true, pendingPlay: false, actualRate: 1, waiting: false))
    }
    func testEOFRestartAndUnknownDuration() {
        XCTAssertTrue(PlaybackStartPolicy.shouldRestart(ended: true, position: 0, duration: 0))
        XCTAssertTrue(PlaybackStartPolicy.shouldRestart(ended: false, position: 10, duration: 10))
        XCTAssertFalse(PlaybackStartPolicy.shouldRestart(ended: false, position: 9, duration: 10))
        XCTAssertFalse(PlaybackStartPolicy.shouldRestart(ended: false, position: 20, duration: 0))
        XCTAssertFalse(PlaybackStartPolicy.shouldRestart(ended: false, position: .nan, duration: .infinity))
    }
    func testSourceRestorationConservativelyRequiresFreshPlay() {
        XCTAssertFalse(PlaybackStartPolicy.shouldStartAfterSeek(sourceRestoration: true, explicitReplay: false, pendingPlay: true, requested: true))
        XCTAssertTrue(PlaybackStartPolicy.shouldStartAfterSeek(sourceRestoration: false, explicitReplay: true, pendingPlay: false, requested: true))
        XCTAssertFalse(PlaybackStartPolicy.shouldStartAfterSeek(sourceRestoration: false, explicitReplay: true, pendingPlay: false, requested: false))
        XCTAssertTrue(PlaybackStartPolicy.shouldStartAfterSeek(sourceRestoration: false, explicitReplay: false, pendingPlay: true, requested: true))
    }

}
