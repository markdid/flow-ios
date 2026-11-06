// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import FlowSignatureSolver

/// These tests exercise only pre-execution gates. None evaluates bundled or player JavaScript.
final class ExperimentalSignatureSolverTests: XCTestCase {
    private let placeholderApproval = String(repeating: "0", count: 64)

    func testDisabledByDefault() async {
        do {
            _ = try await ExperimentalSignatureSolver().solve(playerScript: "fixture", signatures: ["abc"])
            XCTFail("Default solver must remain disabled")
        } catch { XCTAssertEqual(error as? ExperimentalSolverError, .disabled) }
    }

    func testOptInAloneCannotExecuteScripts() async {
        do {
            _ = try await ExperimentalSignatureSolver(enabled: true).solve(playerScript: "fixture", signatures: ["abc"])
            XCTFail("A separately approved fixture is required")
        } catch { XCTAssertEqual(error as? ExperimentalSolverError, .noApprovedFixtures) }
    }

    func testMalformedApprovalRejected() async {
        do {
            _ = try await ExperimentalSignatureSolver(enabled: true, approvedPlayerSHA256: ["not-a-digest"])
                .solve(playerScript: "fixture", signatures: ["abc"])
            XCTFail("Invalid approval")
        } catch { XCTAssertEqual(error as? ExperimentalSolverError, .invalidApprovalDigest) }
    }

    func testScriptSizeGatePrecedesEvaluation() async {
        do {
            _ = try await ExperimentalSignatureSolver(enabled: true, approvedPlayerSHA256: [placeholderApproval])
                .solve(playerScript: String(repeating: "x", count: 8_000_001), signatures: ["abc"])
            XCTFail("Oversized script")
        } catch { XCTAssertEqual(error as? ExperimentalSolverError, .inputLimit) }
    }

    func testChallengeBoundsPrecedeEvaluation() async {
        for challenge in ["", "bad\ninput", String(repeating: "x", count: 16_385)] {
            do {
                _ = try await ExperimentalSignatureSolver(enabled: true, approvedPlayerSHA256: [placeholderApproval])
                    .solve(playerScript: "fixture", nValues: [challenge])
                XCTFail("Invalid challenge")
            } catch { XCTAssertEqual(error as? ExperimentalSolverError, .invalidChallenge) }
        }
    }

    func testTooManyChallengesRejected() async {
        do {
            _ = try await ExperimentalSignatureSolver(enabled: true, approvedPlayerSHA256: [placeholderApproval])
                .solve(playerScript: "fixture", nValues: Array(repeating: "abc", count: 65))
            XCTFail("Too many challenges")
        } catch { XCTAssertEqual(error as? ExperimentalSolverError, .inputLimit) }
    }
}
