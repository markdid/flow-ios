import XCTest
@testable import FlowCore
final class VideoReferenceTests: XCTestCase {
    func testAcceptedLinks() throws {
        for link in ["https://youtu.be/dQw4w9WgXcQ?t=8", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "https://m.youtube.com/shorts/dQw4w9WgXcQ", "https://youtube.com/live/dQw4w9WgXcQ", "https://music.youtube.com/watch?v=dQw4w9WgXcQ"] {
            XCTAssertEqual(try VideoReference(url: XCTUnwrap(URL(string: link))).id, "dQw4w9WgXcQ")
        }
    }
    func testRejectedLinks() throws {
        for link in ["https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ", "https://evil.example/dQw4w9WgXcQ", "javascript:alert(1)", "https://youtu.be/short", "https://youtube.com/watch?v=abcdefghij!", "https://user@youtube.com/watch?v=dQw4w9WgXcQ", "https://youtu.be:8080/dQw4w9WgXcQ"] {
            XCTAssertThrowsError(try VideoReference(url: XCTUnwrap(URL(string: link))))
        }
    }
    func testRoundTrip() throws {
        let video = try VideoReference(url: XCTUnwrap(URL(string: "https://youtu.be/dQw4w9WgXcQ")), title: " Example ")
        XCTAssertEqual(video.title, "Example")
        XCTAssertEqual(try JSONDecoder().decode(VideoReference.self, from: JSONEncoder().encode(video)), video)
    }
}
