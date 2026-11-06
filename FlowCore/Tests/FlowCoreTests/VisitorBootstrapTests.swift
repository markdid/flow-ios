import XCTest
@testable import FlowCore

final class VisitorBootstrapTests: XCTestCase {
    func testExpectedServiceWorkerShapeWithPrefix() throws {
        let body = ")]}'\n[[null,null,[1,\"not-a-visitor\",\"Cgtfixture\"]]]"
        XCTAssertEqual(try VisitorBootstrap.parse(Data(body.utf8)), "Cgtfixture")
    }
    func testMissingPrefixIsAcceptedWhenJSONIsValid() throws {
        XCTAssertEqual(try VisitorBootstrap.parse(Data("[[null,null,[\"Cgsfixture\"]]]".utf8)), "Cgsfixture")
    }
    func testUnexpectedShapeAndInvalidPrefixFailSafely() {
        for body in ["[]", "{}", ")]}'", "[[null,null,[\"unknown\"]]]", "[[null,null,[\"Cg|invalid\"]]]"] {
            XCTAssertThrowsError(try VisitorBootstrap.parse(Data(body.utf8)))
        }
    }
    func testRequestCarriesVisitorInHeaderAndContext() throws {
        let request = try VideoSearchClient.request(query: "cats", visitorData: "Cgtfixture")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Visitor-Id"), "Cgtfixture")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let context = try XCTUnwrap(body["context"] as? [String: Any])
        let client = try XCTUnwrap(context["client"] as? [String: Any])
        XCTAssertEqual(client["visitorData"] as? String, "Cgtfixture")
    }
}
