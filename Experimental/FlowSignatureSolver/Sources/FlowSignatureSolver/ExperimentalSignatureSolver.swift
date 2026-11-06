// SPDX-License-Identifier: GPL-3.0-only
// Isolated experimental adaptation of Alexander Eichhorn's MIT-licensed SignatureSolver.swift.
// See THIRD_PARTY_NOTICES.txt and PROVENANCE.md. Modifications prepared 2026-11-06.
import Foundation
#if canImport(JavaScriptCore) && canImport(CryptoKit)
import JavaScriptCore
import CryptoKit
#endif

public enum ExperimentalSolverError: Error, Equatable {
    case disabled, noApprovedFixtures, invalidApprovalDigest, inputLimit, invalidChallenge
    case unapprovedPlayer, unavailableRuntime, missingResource(String), resourceIntegrity(String)
    case contextCreation, javascriptException(String), invalidResponse, solverRejected(String)
}

public struct ExperimentalSolveResult: Equatable, Sendable {
    public let signatures: [String: String]
    public let nValues: [String: String]
}

/// OFF by default. This research-only actor has no networking or playback integration.
/// Only separately reviewed, caller-allowlisted player fixtures can reach JavaScriptCore.
/// IMPORTANT: size limits do not enforce a CPU or memory budget during JS execution. An
/// infinite loop cannot be cancelled by cancelling the awaiting Swift Task. Do not enable
/// for arbitrary or automatically fetched scripts. Only Linux pre-execution gates have been
/// compiled/tested; the Apple JavaScriptCore branch remains uncompiled and untested.
public actor ExperimentalSignatureSolver {
    private let enabled: Bool
    private let approvedPlayerSHA256: Set<String>

    /// Supplying a digest means the developer has independently reviewed that exact fixture.
    /// Never populate this allowlist by hashing an incoming download automatically.
    public init(enabled: Bool = false, approvedPlayerSHA256: Set<String> = []) {
        self.enabled = enabled
        self.approvedPlayerSHA256 = approvedPlayerSHA256
    }

    public func solve(playerScript: String, signatures: [String] = [], nValues: [String] = []) throws -> ExperimentalSolveResult {
        guard enabled else { throw ExperimentalSolverError.disabled }
        guard !approvedPlayerSHA256.isEmpty else { throw ExperimentalSolverError.noApprovedFixtures }
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        guard approvedPlayerSHA256.count <= 32,
              approvedPlayerSHA256.allSatisfy({ $0.utf8.count == 64 && $0.unicodeScalars.allSatisfy { hex.contains($0) } }) else {
            throw ExperimentalSolverError.invalidApprovalDigest
        }
        guard !playerScript.isEmpty, playerScript.utf8.count <= 8_000_000,
              signatures.count + nValues.count > 0, signatures.count + nValues.count <= 64 else {
            throw ExperimentalSolverError.inputLimit
        }
        for value in signatures + nValues {
            guard !value.isEmpty, value.utf8.count <= 16_384,
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw ExperimentalSolverError.invalidChallenge
            }
        }
        try Task.checkCancellation()
        #if canImport(JavaScriptCore) && canImport(CryptoKit)
        let digest = Self.sha256(Data(playerScript.utf8))
        guard approvedPlayerSHA256.contains(digest) else { throw ExperimentalSolverError.unapprovedPlayer }
        return try evaluate(playerScript: playerScript, signatures: signatures, nValues: nValues)
        #else
        throw ExperimentalSolverError.unavailableRuntime
        #endif
    }

    #if canImport(JavaScriptCore) && canImport(CryptoKit)
    private struct Request: Encodable {
        let type: String
        let challenges: [String]
    }
    private struct Input: Encodable {
        let type = "player"
        let player: String
        let requests: [Request]
        let output_preprocessed = false
    }
    private struct Response: Decodable {
        struct Item: Decodable {
            let type: String
            let data: [String: String]?
            let error: String?
        }
        let type: String
        let responses: [Item]
    }
    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func evaluate(playerScript: String, signatures: [String], nValues: [String]) throws -> ExperimentalSolveResult {
        let vm = JSVirtualMachine()
        guard let context = JSContext(virtualMachine: vm) else { throw ExperimentalSolverError.contextCreation }
        // No Swift objects/functions, credentials, filesystem or networking bridges are exposed.
        // A fresh VM per call avoids cross-player mutable state. The actor serializes calls.
        var exceptionRaised = false
        context.exceptionHandler = { _, _ in exceptionRaised = true }
        defer { context.exceptionHandler = nil }
        func run(_ script: String, stage: String) throws -> JSValue {
            try Task.checkCancellation()
            exceptionRaised = false
            context.exception = nil
            let result = context.evaluateScript(script)
            guard !exceptionRaised, context.exception == nil, let value = result else {
                // Do not log raw JS exception messages; they may contain signed URLs/challenges.
                throw ExperimentalSolverError.javascriptException(stage)
            }
            return value
        }
        let resources: [(String, String, String)] = [
            ("meriyah", "umd.js", "a334aee4b2b6aabba544ec90eb28d09af06c727f9e0778bd647178e4c81019ec"),
            ("astring", "umd.js", "9e4a11f3f1bcf9a0d3092ce5b1b000c32f572ce8fff4d60378b4d04f28c7e123"),
            ("yt_ejs_helper", "js", "eb4d4844a3f9ab9f1672bc04218740cda4d3e85883dd186c2e0a8e1932d56eb7")
        ]
        for (name, ext, expectedDigest) in resources {
            guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
                throw ExperimentalSolverError.missingResource(name)
            }
            let data = try Data(contentsOf: url)
            guard data.count <= 500_000, Self.sha256(data) == expectedDigest,
                  let script = String(data: data, encoding: .utf8) else {
                throw ExperimentalSolverError.resourceIntegrity(name)
            }
            _ = try run(script, stage: name)
        }
        // EJS's own pinned setupNodes creates minimal environment placeholders. No broad browser
        // implementation or native capabilities are added. Unsupported assumptions must fail.
        var requests: [Request] = []
        if !nValues.isEmpty { requests.append(Request(type: "n", challenges: Array(Set(nValues)).sorted())) }
        if !signatures.isEmpty { requests.append(Request(type: "sig", challenges: Array(Set(signatures)).sorted())) }
        let payload = try JSONEncoder().encode(Input(player: playerScript, requests: requests))
        guard let json = String(data: payload, encoding: .utf8) else { throw ExperimentalSolverError.invalidResponse }
        context.setObject(json, forKeyedSubscript: "flowInputJSON" as NSString)
        let result = try run("JSON.stringify(jsc(JSON.parse(flowInputJSON)))", stage: "solve")
        try Task.checkCancellation()
        guard result.isString, let output = result.toString(), output.utf8.count <= 2_000_000,
              let outputData = output.data(using: .utf8),
              let response = try? JSONDecoder().decode(Response.self, from: outputData),
              response.type == "result", response.responses.count == requests.count else {
            throw ExperimentalSolverError.invalidResponse
        }
        var solvedN: [String: String] = [:]
        var solvedSig: [String: String] = [:]
        for (request, item) in zip(requests, response.responses) {
            guard item.type != "error" else { throw ExperimentalSolverError.solverRejected(request.type) }
            guard item.type == "result", item.error == nil, let values = item.data,
                  Set(values.keys) == Set(request.challenges) else { throw ExperimentalSolverError.invalidResponse }
            for (input, output) in values {
                guard !output.isEmpty, output.utf8.count <= 16_384,
                      !output.hasPrefix("enhanced_except_"),
                      !output.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                      request.type != "n" || output != input else { throw ExperimentalSolverError.invalidResponse }
            }
            if request.type == "n" { solvedN = values } else { solvedSig = values }
        }
        return ExperimentalSolveResult(signatures: solvedSig, nValues: solvedN)
    }
    #endif
}
