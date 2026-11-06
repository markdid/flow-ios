// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import FlowCore

final class PlayerScriptMetadataTests: XCTestCase {
    func testEscapedAndUnescapedPlayerPaths() throws {
        XCTAssertEqual(try PlayerScriptMetadata.discoverVersion(iframeAPI: #"var src='https:\/\/www.youtube.com\/s\/player\/abc123_-\/www-widgetapi.js';"#), "abc123_-")
        XCTAssertEqual(try PlayerScriptMetadata.discoverVersion(iframeAPI: "/s/player/abc123/- /s/player/abc123/"), "abc123")
    }
    func testMissingAndAmbiguousVersions() {
        XCTAssertThrowsError(try PlayerScriptMetadata.discoverVersion(iframeAPI: "no player"))
        XCTAssertThrowsError(try PlayerScriptMetadata.discoverVersion(iframeAPI: "/s/player/a/ /s/player/b/"))
        XCTAssertThrowsError(try PlayerScriptMetadata(version: "../escape", script: ""))
    }
    func testTimestampAndCanonicalURL() throws {
        let result = try PlayerScriptMetadata(version: "abc12345", script: #"x={"signatureTimestamp":20522};"#)
        XCTAssertEqual(result.signatureTimestamp, 20522)
        XCTAssertEqual(result.scriptURL.absoluteString, "https://www.youtube.com/s/player/abc12345/player_ias.vflset/en_GB/base.js")
        XCTAssertEqual(try PlayerScriptMetadata(version: "a", script: "sts:20522").signatureTimestamp, 20522)
    }
    func testUnknownAndConflictingTimestampFailClosed() throws {
        XCTAssertNil(try PlayerScriptMetadata(version: "a", script: "lists:20522; not_signatureTimestamp:9;").signatureTimestamp)
        XCTAssertThrowsError(try PlayerScriptMetadata(version: "a", script: "sts:20522; signatureTimestamp:20523"))
        XCTAssertNil(try PlayerScriptMetadata(version: "a", script: "sts:99999999999").signatureTimestamp)
    }
    func testInputBounds() {
        XCTAssertThrowsError(try PlayerScriptMetadata.discoverVersion(iframeAPI: String(repeating: "x", count: 1_000_001)))
        XCTAssertThrowsError(try PlayerScriptMetadata(version: "a", script: String(repeating: "x", count: 8_000_001)))
    }
}
