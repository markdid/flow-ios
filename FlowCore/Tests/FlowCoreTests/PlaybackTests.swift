// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import FlowCore

final class PlaybackTests: XCTestCase {
    private func data(_ streaming: [String: Any], status: String = "OK") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["playabilityStatus": ["status": status], "streamingData": streaming])
    }
    func testHLSAndMuxedMP4Selection() throws {
        let sources = try PlaybackResponseParser.parse(data([
            "hlsManifestUrl": "https://manifest.googlevideo.com/api/manifest/hls/test",
            "formats": [["itag": 18, "mimeType": "video/mp4; codecs=avc1", "audioQuality": "AUDIO_QUALITY_LOW", "height": 360, "url": "https://rr1.googlevideo.com/videoplayback?sig=test"]]
        ]))
        XCTAssertEqual(sources.map(\.kind), [.hls, .video])
    }
    func testRejectsCipherAndUntransformedN() throws {
        XCTAssertThrowsError(try PlaybackResponseParser.parse(data(["formats": [
            ["itag": 18, "mimeType": "video/mp4", "audioChannels": 2, "url": "https://rr1.googlevideo.com/videoplayback?n=untransformed"],
            ["itag": 22, "mimeType": "video/mp4", "audioChannels": 2, "signatureCipher": "s=encrypted&url=foo"]
        ]])))
    }
    func testRejectsVideoOnlyAndUntrustedURLs() throws {
        for url in ["https://example.com/video.mp4", "http://rr1.googlevideo.com/video", "https://googlevideo.com.evil.test/video", "https://user@rr1.googlevideo.com/video"] {
            XCTAssertThrowsError(try PlaybackResponseParser.parse(data(["hlsManifestUrl": url])))
        }
        XCTAssertThrowsError(try PlaybackResponseParser.parse(data(["adaptiveFormats": [["itag": 137, "mimeType": "video/mp4", "url": "https://rr1.googlevideo.com/video"]]])))
    }
    func testAudioAndPlayabilityRefusal() throws {
        let sources = try PlaybackResponseParser.parse(data(["adaptiveFormats": [["itag": 140, "mimeType": "audio/mp4", "url": "https://rr1.googlevideo.com/audio"]]]))
        XCTAssertEqual(sources.first?.kind, .audio)
        XCTAssertThrowsError(try PlaybackResponseParser.parse(data([:], status: "LOGIN_REQUIRED")))
    }
    func testQueueBoundariesAndRepeat() throws {
        let a = try VideoReference(url: XCTUnwrap(URL(string: "https://youtu.be/abcdefghijk")))
        let b = try VideoReference(url: XCTUnwrap(URL(string: "https://youtu.be/12345678901")))
        var queue = PlaybackQueue()
        XCTAssertNil(queue.next())
        queue.replace(with: [a, b])
        XCTAssertEqual(queue.current, a)
        queue.repeatMode = .one
        XCTAssertEqual(queue.next(automatic: true), a)
        XCTAssertEqual(queue.next(), b)
        XCTAssertNil(queue.next())
        queue.repeatMode = .all
        XCTAssertEqual(queue.next(), a)
        XCTAssertEqual(queue.previous(), b)
        queue.replace(with: [], startAt: 9)
        XCTAssertNil(queue.current)
    }
    func testShuffleNeverImmediatelyRepeatsWhenMultipleItemsExist() throws {
        let a = try VideoReference(url: XCTUnwrap(URL(string: "https://youtu.be/abcdefghijk")))
        let b = try VideoReference(url: XCTUnwrap(URL(string: "https://youtu.be/12345678901")))
        var queue = PlaybackQueue()
        queue.replace(with: [a, b]); queue.shuffled = true
        XCTAssertEqual(queue.next(), b)
        XCTAssertNil(queue.next())
        queue.repeatMode = .all
        XCTAssertEqual(queue.next(), a)
    }

    func testShuffledTraversalEndsAndPreviousRetracesActualOrder() throws {
        let videos = try ["abcdefghijk", "12345678901", "ABCDEFGHIJK", "abcdefghij0"].map {
            try VideoReference(url: XCTUnwrap(URL(string: "https://youtu.be/\($0)")))
        }
        var queue = PlaybackQueue()
        queue.replace(with: videos)
        queue.shuffled = true
        var played = [try XCTUnwrap(queue.current)]
        for _ in 1..<videos.count { played.append(try XCTUnwrap(queue.next())) }
        XCTAssertEqual(Set(played.map(\.id)).count, videos.count)
        XCTAssertNil(queue.next(automatic: true))
        XCTAssertNil(queue.next())
        for expected in played.dropLast().reversed() { XCTAssertEqual(queue.previous(), expected) }
        XCTAssertEqual(queue.previous(), played.first)
        for expected in played.dropFirst() { XCTAssertEqual(queue.next(), expected) }
        XCTAssertNil(queue.next())
        queue.repeatMode = .all
        let boundary = try XCTUnwrap(queue.next())
        XCTAssertNotEqual(boundary, played.last)
        XCTAssertEqual(queue.previous(), played.last)
        XCTAssertEqual(queue.next(), boundary)
    }

    func testShuffleAppendAndReplaceResetTraversal() throws {
        let a = try VideoReference(url: XCTUnwrap(URL(string: "https://youtu.be/abcdefghijk")))
        let b = try VideoReference(url: XCTUnwrap(URL(string: "https://youtu.be/12345678901")))
        var queue = PlaybackQueue()
        queue.shuffled = true
        queue.append(a)
        XCTAssertNil(queue.next())
        queue.append(b)
        XCTAssertEqual(queue.next(), b)
        XCTAssertNil(queue.next())
        queue.replace(with: [b])
        XCTAssertEqual(queue.previous(), b)
        XCTAssertNil(queue.next())
    }
}
