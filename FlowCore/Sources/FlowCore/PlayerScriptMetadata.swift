// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client Copyright (C) 2025-2026 A-EDev.
// Modified Swift translation, 2026-11-06, from utils/cipher/PlayerJsFetcher.kt and
// FunctionNameExtractor.kt at 3f3e2a6101fe511003f8b694876fe8c6ece89c66.
import Foundation

public enum PlayerScriptMetadataError: Error, Equatable {
    case oversizedInput, missingPlayerVersion, ambiguousPlayerVersion, invalidPlayerVersion
    case ambiguousSignatureTimestamp
}

/// Read-only metadata extraction. Does not execute or download JavaScript and does not certify
/// that a player can be deciphered. A signature timestamp alone is not a working transform.
public struct PlayerScriptMetadata: Equatable, Sendable {
    public let version: String
    public let signatureTimestamp: Int?

    public init(version: String, script: String) throws {
        guard Self.validVersion(version) else { throw PlayerScriptMetadataError.invalidPlayerVersion }
        guard script.utf8.count <= 8_000_000 else { throw PlayerScriptMetadataError.oversizedInput }
        self.version = version
        self.signatureTimestamp = try Self.timestamp(in: script)
    }

    /// This version is YouTube's player path identifier, not a cryptographic content hash.
    /// Unlike upstream's fallback, we do not manufacture it from a partial-script MD5 digest.
    public static func discoverVersion(iframeAPI: String) throws -> String {
        guard iframeAPI.utf8.count <= 1_000_000 else { throw PlayerScriptMetadataError.oversizedInput }
        let normalized = iframeAPI.replacingOccurrences(of: "\\/", with: "/")
        let values = captures(#"/s/player/([A-Za-z0-9_-]{1,64})/"#, in: normalized)
        let unique = Set(values)
        guard !unique.isEmpty else { throw PlayerScriptMetadataError.missingPlayerVersion }
        guard unique.count == 1, let version = unique.first else {
            throw PlayerScriptMetadataError.ambiguousPlayerVersion
        }
        return version
    }

    /// Upstream's fixed public player path. No arbitrary response URL or host is accepted.
    public var scriptURL: URL {
        URL(string: "https://www.youtube.com/s/player/\(version)/player_ias.vflset/en_GB/base.js")!
    }

    private static func validVersion(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return !value.isEmpty && value.utf8.count <= 64 && value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func timestamp(in script: String) throws -> Int? {
        // Exact identifier boundaries avoid matching unrelated names such as `lists` or
        // `not_signatureTimestamp`. Scan only data, never evaluate code to discover a value.
        let pattern = #"(?<![A-Za-z0-9_$])(?:signatureTimestamp|sts)[\"':\s]+([0-9]{1,10})(?![0-9])"#
        let values = Set(captures(pattern, in: script).compactMap(Int.init).filter { $0 > 0 && $0 <= Int(Int32.max) })
        guard values.count <= 1 else { throw PlayerScriptMetadataError.ambiguousSignatureTimestamp }
        return values.first
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let value = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[value])
        }
    }
}
