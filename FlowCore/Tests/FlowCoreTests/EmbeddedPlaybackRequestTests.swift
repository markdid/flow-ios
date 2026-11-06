// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import FlowCore

final class EmbeddedPlaybackRequestTests: XCTestCase {
    private func video() throws -> VideoReference {
        try VideoReference(url: XCTUnwrap(URL(string: "https://youtu.be/abcdefghijk")))
    }
    func testActualBundleIdentityBecomesHTTPSReferrer() throws {
        let request = try EmbeddedPlaybackRequest.make(video: video(), bundleIdentifier: "Org.Example.FlowPrototype")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://org.example.flowprototype")
        XCTAssertEqual(request.httpMethod, "GET")
    }
    func testKeepsOfficialPrivacyEnhancedEmbedAndManualPlayback() throws {
        let reference = try video()
        let request = try EmbeddedPlaybackRequest.make(video: reference, bundleIdentifier: "org.example.flowprototype")
        XCTAssertEqual(request.url, reference.embedURL)
        XCTAssertEqual(request.url?.host, "www.youtube-nocookie.com")
        let items = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false)).queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "playsinline" })?.value, "1")
        XCTAssertFalse(items.contains(where: { ["autoplay", "has_verified", "contentCheckOk", "racyCheckOk"].contains($0.name) }))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.httpBody)
    }
    func testMissingIdentityHasNoInventedFallback() throws {
        for identity: String? in [nil, ""] {
            XCTAssertThrowsError(try EmbeddedPlaybackRequest.make(video: video(), bundleIdentifier: identity)) {
                XCTAssertEqual($0 as? EmbeddedPlaybackRequestError, .missingAppIdentity)
            }
        }
    }
    func testRejectsHeaderURLAndHostInjection() throws {
        for identity in ["https://example.com", "com.example/app", "com.example?x=1", "com.example#x", "user@com.example", "com.example:443", "com.example\r\nX-Foo: bar", " com.example", "com..example", ".com.example", "com.example.", "com.exämple", "localhost", "com.example_app"] {
            XCTAssertThrowsError(try EmbeddedPlaybackRequest.make(video: video(), bundleIdentifier: identity), identity)
        }
    }
    func testAllowsNormalHyphenatedBundleIdentityAndRejectsOversize() throws {
        XCTAssertEqual(try EmbeddedPlaybackRequest.make(video: video(), bundleIdentifier: "com.example.my-app").value(forHTTPHeaderField: "Referer"), "https://com.example.my-app")
        XCTAssertThrowsError(try EmbeddedPlaybackRequest.make(video: video(), bundleIdentifier: "com." + String(repeating: "a", count: 64)))
    }
}
