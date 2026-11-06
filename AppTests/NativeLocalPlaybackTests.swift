// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import AVFoundation
import CoreVideo
@testable import FlowPrototype

/// Original changing-color video generated on this simulator, never downloaded.
/// Objective clock/state checks do not establish audible output or YouTube playback.
final class NativeLocalPlaybackTests: XCTestCase {
    private func makeFixture() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 90
        ])
        input.expectsMediaDataInRealTime = false
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                          kCVPixelBufferWidthKey as String: 160,
                                          kCVPixelBufferHeightKey as String: 90])
        guard writer.canAdd(input) else { throw NSError(domain: "Fixture", code: 1) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "Fixture", code: 2) }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<240 {
            let deadline = Date().addingTimeInterval(10)
            while !input.isReadyForMoreMediaData {
                if Date() > deadline { throw NSError(domain: "FixtureTimeout", code: 1) }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            var optionalBuffer: CVPixelBuffer?
            let result = CVPixelBufferCreate(kCFAllocatorDefault, 160, 90, kCVPixelFormatType_32ARGB,
                                            nil, &optionalBuffer)
            guard result == kCVReturnSuccess, let buffer = optionalBuffer else {
                throw NSError(domain: "Fixture", code: 3)
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<90 {
                for x in 0..<160 {
                    let offset = y * stride + x * 4
                    bytes[offset] = 255
                    bytes[offset + 1] = UInt8((frame * 3 + x) % 256)
                    bytes[offset + 2] = UInt8((frame + y * 2) % 256)
                    bytes[offset + 3] = UInt8((frame * 2) % 256)
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adapter.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                throw writer.error ?? NSError(domain: "Fixture", code: 4)
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "Fixture", code: 5) }
        return url
    }

    @MainActor
    func testGeneratedLocalVideoAdvancesPausesSeeksAndStops() async throws {
        let url = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: url) }
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
