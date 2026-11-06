// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import AVFoundation
import CoreVideo
@testable import FlowPrototype

/// Original changing-color video generated with FFmpeg, bundled only for tests.
/// Objective clock/state checks do not establish audible output or YouTube playback.
final class NativeLocalPlaybackTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        guard let url = Bundle(for: Self.self).url(forResource: "generated-colors", withExtension: "mp4") else {
            throw NSError(domain: "MissingOriginalTestFixture", code: 1)
        }
        return url
    }

    @MainActor
    func testGeneratedLocalVideoAdvancesPausesSeeksAndStops() async throws {
        let url = try fixtureURL()
        let controller = NativePlaybackController()
        defer { controller.stop() }
        controller.startLocalTestFixture(url)
        let deadline = Date().addingTimeInterval(20)
        while controller.player.currentItem?.status != .readyToPlay || controller.player.rate == 0 {
            if let error = controller.error { XCTFail(error); return }
            if Date() > deadline { XCTFail("Local AVPlayer did not become ready/playing"); return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let first = controller.player.currentTime().seconds
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let second = controller.player.currentTime().seconds
        XCTAssertTrue(first.isFinite && second.isFinite)
        XCTAssertGreaterThan(second - first, 0.7, "Actual AVPlayer time must advance")
        XCTAssertGreaterThan(controller.player.rate, 0)
        print("LOCAL_AVPLAYER_ADVANCE first=\(first) second=\(second) rate=\(controller.player.rate)")
        controller.pause()
        let paused = controller.player.currentTime().seconds
        try await Task.sleep(nanoseconds: 500_000_000)
        let pausedLater = controller.player.currentTime().seconds
        XCTAssertEqual(paused, pausedLater, accuracy: 0.15)
        XCTAssertEqual(controller.player.rate, 0)
        print("LOCAL_AVPLAYER_PAUSE first=\(paused) second=\(pausedLater)")
        controller.seek(to: 4)
        let seekDeadline = Date().addingTimeInterval(5)
        while abs(controller.player.currentTime().seconds - 4) > 0.2 && Date() < seekDeadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(controller.player.currentTime().seconds, 4, accuracy: 0.2)
        print("LOCAL_AVPLAYER_SEEK time=\(controller.player.currentTime().seconds)")
        controller.stop()
        XCTAssertNil(controller.player.currentItem)
        XCTAssertEqual(controller.player.rate, 0)
        print("LOCAL_AVPLAYER_STOP item=nil rate=0")
    }
}
