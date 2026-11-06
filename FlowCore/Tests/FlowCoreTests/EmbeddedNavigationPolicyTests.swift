import XCTest
@testable import FlowCore
final class EmbeddedNavigationPolicyTests: XCTestCase {
    func testOnlyCurrentOfficialEmbedIsAllowedAsMainDocument() throws {
        let video = try VideoReference(url: URL(string: "https://youtu.be/abcdefghijk")!)
        XCTAssertTrue(EmbeddedNavigationPolicy.permitsMainFrame(video.embedURL, video: video))
        XCTAssertTrue(EmbeddedNavigationPolicy.permitsMainFrame(URL(string: "https://www.youtube-nocookie.com/embed/abcdefghijk?playsinline=1&extra=1"), video: video))
        for value in ["https://www.youtube.com/watch?v=abcdefghijk", "https://evil.test/embed/abcdefghijk", "http://www.youtube-nocookie.com/embed/abcdefghijk", "https://www.youtube-nocookie.com/embed/01234567890", "https://user@www.youtube-nocookie.com/embed/abcdefghijk", "https://www.youtube-nocookie.com:444/embed/abcdefghijk", "about:blank"] {
            XCTAssertFalse(EmbeddedNavigationPolicy.permitsMainFrame(URL(string: value), video: video))
        }
        XCTAssertFalse(EmbeddedNavigationPolicy.permitsMainFrame(nil, video: video))
    }
}
