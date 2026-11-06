// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import FlowCore

final class PlaybackManifestExtractorTests: XCTestCase {
    private let url = "https://rr1.googlevideo.com/videoplayback"
    private let videoMime = "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\""
    private func response(_ streaming: [String: Any], status: String = "OK") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["playabilityStatus": ["status": status], "streamingData": streaming])
    }
    private func format(_ itag: Int = 18, url: String? = nil) -> [String: Any] {
        ["itag": itag, "mimeType": videoMime, "url": url ?? self.url, "height": 360]
    }
    func testDirectSourceSelectionAndOrdering() throws {
        let result = try PlaybackManifestExtractor.extract(response([
            "hlsManifestUrl": "https://manifest.googlevideo.com/api/manifest/hls/a",
            "formats": [format()],
            "adaptiveFormats": [["itag": 140, "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "url": url]]
        ]))
        XCTAssertEqual(result.sources.map(\.kind), [.hls, .video, .audio])
        XCTAssertTrue(result.skipped.isEmpty)
    }
    func testExplicitTransformsResolveCipherAndN() throws {
        let original = url + "?n=raw&x=a%2fb"
        let encoded = original.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        var entry = format()
        entry.removeValue(forKey: "url")
        entry["signatureCipher"] = "url=\(encoded)&s=abc&sp=sig"
        let result = try PlaybackManifestExtractor.extract(response(["formats": [entry]]),
            signatureTransform: { XCTAssertEqual($0, "abc"); return "signed" },
            nTransform: { XCTAssertEqual($0, "raw"); return "solved" })
        XCTAssertEqual(result.sources.first?.url.absoluteString, url + "?n=solved&x=a%2fb&sig=signed")
        XCTAssertTrue(result.skipped.isEmpty)
    }
    func testMissingTransformDoesNotDiscardOtherSources() throws {
        let result = try PlaybackManifestExtractor.extract(response(["formats": [format(22, url: url + "?n=raw"), format()]]))
        XCTAssertEqual(result.sources.map(\.id), ["18"])
        XCTAssertEqual(result.skipped.map(\.reason), [.unresolvedURL(.missingNTransform)])
    }
    func testRefusalsNeverInvokeTransforms() throws {
        for status in ["LOGIN_REQUIRED", "UNPLAYABLE", "AGE_CHECK_REQUIRED", "ERROR"] {
            XCTAssertThrowsError(try PlaybackManifestExtractor.extract(response(["formats": [format()]], status: status), signatureTransform: { _ in XCTFail("Must not solve refused playback"); return "bad" }))
        }
    }
    func testProtectedAndVideoOnlyFormatsRejected() throws {
        var protected = format(); protected["drmFamilies"] = ["WIDEVINE"]
        let result = try PlaybackManifestExtractor.extract(response([
            "formats": [protected], "adaptiveFormats": [format(137)]
        ]))
        XCTAssertTrue(result.sources.isEmpty)
        XCTAssertEqual(result.skipped.map(\.reason), [.protectedFormat, .separateVideoTrack])
    }
    func testMalformedEntriesUnsupportedCodecsAndDuplicates() throws {
        var wrongCodec = format(22); wrongCodec["mimeType"] = "video/mp4; codecs=\"av01.0.08M.08, mp4a.40.2\""
        let result = try PlaybackManifestExtractor.extract(response(["formats": ["bad", wrongCodec, format(), format()] as [Any]]))
        XCTAssertEqual(result.sources.map(\.id), ["18"])
        XCTAssertEqual(result.skipped.map(\.reason), [.malformedFormat, .unsupportedCodecs, .duplicate])
    }
    func testFormatCountBound() throws {
        XCTAssertThrowsError(try PlaybackManifestExtractor.extract(response(["formats": Array(repeating: format(), count: 513)])))
    }
    func testCipherConflictAndUnsafeURL() throws {
        var entry = format(); entry["signatureCipher"] = "one"; entry["cipher"] = "two"
        let result = try PlaybackManifestExtractor.extract(response(["formats": [entry, format(22, url: "https://example.com/stream")]]))
        XCTAssertTrue(result.sources.isEmpty)
        XCTAssertEqual(result.skipped.map(\.reason), [.malformedFormat, .unresolvedURL(.invalidURL)])
    }
    func testThrowingTransformProducesSanitizedDiagnostic() throws {
        enum FixtureError: Error { case failure }
        let result = try PlaybackManifestExtractor.extract(response(["formats": [format(22, url: url + "?n=raw")]]), nTransform: { _ in throw FixtureError.failure })
        XCTAssertTrue(result.sources.isEmpty)
        XCTAssertEqual(result.skipped.map(\.reason), [.transformFailed])
    }
    func testBooleanItagsCannotBecomeIntegerIDs() throws {
        var truth = format(); truth["itag"] = true
        var falsity = format(); falsity["itag"] = false
        let result = try PlaybackManifestExtractor.extract(response(["formats": [truth, falsity, format(1)]]))
        XCTAssertEqual(result.sources.map(\.id), ["1"])
        XCTAssertEqual(result.skipped.map(\.reason), [.malformedFormat, .malformedFormat])
    }

    func testBooleanHeightsAreRejectedRatherThanDisplayedAsOneOrZero() throws {
        var truth = format(18); truth["height"] = true
        var falsity = format(22); falsity["height"] = false
        var missing = format(37); missing.removeValue(forKey: "height")
        let result = try PlaybackManifestExtractor.extract(response(["formats": [truth, falsity, missing]]))
        XCTAssertEqual(result.sources.map(\.id), ["37"])
        XCTAssertEqual(result.sources.first?.height, 0)
        XCTAssertEqual(result.skipped.map(\.reason), [.malformedFormat, .malformedFormat])
    }

    func testFractionalAndStringNumericFieldsAreRejected() throws {
        var fractionalID = format(); fractionalID["itag"] = 18.5
        var stringID = format(); stringID["itag"] = "18"
        var fractionalHeight = format(); fractionalHeight["height"] = 360.5
        var stringHeight = format(); stringHeight["height"] = "360"
        let result = try PlaybackManifestExtractor.extract(response([
            "formats": [fractionalID, stringID, fractionalHeight, stringHeight, format()]
        ]))
        XCTAssertEqual(result.sources.map(\.id), ["18"])
        XCTAssertEqual(result.sources.first?.height, 360)
        XCTAssertEqual(result.skipped.count, 4)
        XCTAssertTrue(result.skipped.allSatisfy { $0.reason == .malformedFormat })
    }

}
