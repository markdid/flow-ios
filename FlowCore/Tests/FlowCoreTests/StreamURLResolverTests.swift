// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import FlowCore

final class StreamURLResolverTests: XCTestCase {
    private func cipher(url: String = "https://rr1.googlevideo.com/videoplayback?x=a%2fb+z", extra: String = "") -> String {
        let allowed = CharacterSet.alphanumerics
        return "url=\(url.addingPercentEncoding(withAllowedCharacters: allowed)!)&s=a%2Bb+c\(extra)"
    }

    func testFormDecodingAndDefaultParameter() throws {
        let parsed = try StreamSignatureCipher(cipher())
        XCTAssertEqual(parsed.signature, "a+b c")
        XCTAssertEqual(parsed.parameter, "signature")
        XCTAssertEqual(parsed.url.absoluteString, "https://rr1.googlevideo.com/videoplayback?x=a%2fb+z")
    }

    func testSignatureAndNWithPreservedQueryBytes() throws {
        let url = try StreamURLResolver.resolve(
            signatureCipher: cipher(url: "https://rr1.googlevideo.com/videoplayback?x=a%2fb+z&n=original", extra: "&sp=sig"),
            signatureTransform: { input in XCTAssertEqual(input, "a+b c"); return "signed+/=" },
            nTransform: { input in XCTAssertEqual(input, "original"); return "transformed" })
        XCTAssertEqual(url.absoluteString, "https://rr1.googlevideo.com/videoplayback?x=a%2fb+z&n=transformed&sig=signed%2B%2F%3D")
    }

    func testMissingTransformsFailClosed() throws {
        XCTAssertThrowsError(try StreamURLResolver.resolve(signatureCipher: cipher())) { error in
            XCTAssertEqual(error as? StreamURLResolutionError, .missingSignatureTransform)
        }
        XCTAssertThrowsError(try StreamURLResolver.resolve(directURL: "https://rr1.googlevideo.com/videoplayback?n=raw")) { error in
            XCTAssertEqual(error as? StreamURLResolutionError, .missingNTransform)
        }
    }

    func testDirectURLUnchanged() throws {
        let raw = "https://rr1.googlevideo.com/videoplayback?sig=a%2Bb&x=1+2"
        XCTAssertEqual(try StreamURLResolver.resolve(directURL: raw).absoluteString, raw)
    }

    func testRejectsMalformedEnvelopesAndUnsafeHosts() throws {
        for raw in ["", "s=x", "url=%ZZ&s=x", cipher() + "&s=other", cipher(extra: "&sp=n"), cipher(extra: "&sp=x%26evil"), cipher(url: "https://googlevideo.com.evil.test/video"), cipher(url: "https://user@rr1.googlevideo.com/video"), cipher(url: "http://rr1.googlevideo.com/video"), cipher(url: "https://rr1.googlevideo.com/video#fragment")] {
            XCTAssertThrowsError(try StreamSignatureCipher(raw), raw)
        }
    }

    func testDuplicateParametersAndInvalidNResultsFail() throws {
        XCTAssertThrowsError(try StreamURLResolver.resolve(directURL: "https://rr1.googlevideo.com/video?n=a&%6E=b", nTransform: { _ in "c" }))
        for output in ["", "raw", "enhanced_except_failure", "bad\nresult"] {
            XCTAssertThrowsError(try StreamURLResolver.resolve(directURL: "https://rr1.googlevideo.com/video?n=raw", nTransform: { _ in output }))
        }
        XCTAssertThrowsError(try StreamURLResolver.resolve(signatureCipher: cipher(url: "https://rr1.googlevideo.com/video?sig=a&sig=b", extra: "&sp=sig"), signatureTransform: { _ in "c" }))
    }

    func testReplacesExistingSignatureWithoutDuplicating() throws {
        let result = try StreamURLResolver.resolve(signatureCipher: cipher(url: "https://rr1.googlevideo.com/video?sig=old", extra: "&sp=sig"), signatureTransform: { _ in "new" })
        XCTAssertEqual(result.absoluteString, "https://rr1.googlevideo.com/video?sig=new")
    }

    func testDoesNotSwallowTransformErrors() throws {
        enum Failure: Error { case failed }
        XCTAssertThrowsError(try StreamURLResolver.resolve(signatureCipher: cipher(), signatureTransform: { _ in throw Failure.failed })) { error in
            XCTAssertTrue(error is Failure)
        }
    }
}
