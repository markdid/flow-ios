// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client Copyright (C) 2025-2026 A-EDev.
// Modified Swift translation, 2026-11-06, of player/stream/SignatureCipher.kt
// at upstream 3f3e2a6101fe511003f8b694876fe8c6ece89c66.
import Foundation

public enum StreamURLResolutionError: Error, Equatable, Sendable {
    case malformedCipher, invalidURL, ambiguousParameter
    case missingSignatureTransform, missingNTransform, invalidTransformResult
}

/// The form-encoded envelope supplied by a player response, not a decipher implementation.
public struct StreamSignatureCipher: Equatable, Sendable {
    public let url: URL
    public let signature: String
    public let parameter: String

    public init(_ encoded: String) throws {
        guard encoded.utf8.count <= 131_072 else { throw StreamURLResolutionError.malformedCipher }
        var fields: [String: String] = [:]
        for part in encoded.split(separator: "&", omittingEmptySubsequences: false) {
            guard let equal = part.firstIndex(of: "=") else { continue }
            let name = String(part[..<equal])
            guard ["url", "s", "sp"].contains(name) else { continue }
            guard fields[name] == nil,
                  let value = String(part[part.index(after: equal)...])
                    .replacingOccurrences(of: "+", with: " ").removingPercentEncoding else {
                throw StreamURLResolutionError.malformedCipher
            }
            fields[name] = value
        }
        guard let raw = fields["url"], let signature = fields["s"], !signature.isEmpty,
              signature.utf8.count <= 16_384 else { throw StreamURLResolutionError.malformedCipher }
        let parameter = fields["sp"].flatMap { $0.isEmpty ? nil : $0 } ?? "signature"
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard parameter.utf8.count <= 64, parameter.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              !["n", "s", "url"].contains(parameter) else { throw StreamURLResolutionError.malformedCipher }
        self.url = try StreamURLResolver.validate(raw)
        self.signature = signature
        self.parameter = parameter
    }
}

/// Portable URL assembly. Callers must supply transforms verified for the exact player version.
/// There is intentionally no default or guessed transform, remote-code execution, or network IO.
/// PlaybackResponseParser uses direct-URL validation only; cipher/n URLs remain unsupported.
public enum StreamURLResolver {
    public typealias Transform = (String) throws -> String

    public static func resolve(directURL: String? = nil, signatureCipher: String? = nil,
                               signatureTransform: Transform? = nil,
                               nTransform: Transform? = nil) throws -> URL {
        // A response offering both paths is ambiguous; do not guess which signature is authoritative.
        guard (directURL != nil) != (signatureCipher != nil) else {
            throw StreamURLResolutionError.invalidURL
        }
        var url: URL
        if let encoded = signatureCipher {
            let cipher = try StreamSignatureCipher(encoded)
            guard let transform = signatureTransform else {
                throw StreamURLResolutionError.missingSignatureTransform
            }
            let solved = try checkedResult(transform(cipher.signature))
            url = try replacing(cipher.parameter, in: cipher.url, with: solved)
        } else {
            url = try validate(directURL!)
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard !items.contains(where: { $0.name == "s" }) else { throw StreamURLResolutionError.invalidURL }
        let nItems = items.filter { $0.name == "n" }
        guard nItems.count <= 1 else { throw StreamURLResolutionError.ambiguousParameter }
        if let item = nItems.first {
            guard let input = item.value, !input.isEmpty, input.utf8.count <= 16_384 else {
                throw StreamURLResolutionError.invalidURL
            }
            guard let transform = nTransform else { throw StreamURLResolutionError.missingNTransform }
            let output = try checkedResult(transform(input))
            // An unchanged value is not evidence that the n transform succeeded.
            guard output != input else { throw StreamURLResolutionError.invalidTransformResult }
            url = try replacing("n", in: url, with: output)
        }
        return url
    }

    fileprivate static func validate(_ raw: String) throws -> URL {
        guard raw.utf8.count <= 131_072, let url = URL(string: raw),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil,
              let host = components.host?.lowercased(),
              host == "googlevideo.com" || host.hasSuffix(".googlevideo.com") else {
            throw StreamURLResolutionError.invalidURL
        }
        return url
    }

    private static func checkedResult(_ result: String) throws -> String {
        guard !result.isEmpty, result.utf8.count <= 16_384,
              !result.hasPrefix("enhanced_except_"),
              !result.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw StreamURLResolutionError.invalidTransformResult
        }
        return result
    }

    /// Preserve all unrelated query bytes, including '+' and percent-escape case, since a URL
    /// signature can depend on its exact representation. Only the target value is re-encoded.
    private static func replacing(_ name: String, in url: URL, with value: String) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw StreamURLResolutionError.invalidURL
        }
        var parts = (components.percentEncodedQuery ?? "").split(separator: "&", omittingEmptySubsequences: false).map(String.init)
        if parts == [""] { parts = [] }
        let matches = parts.indices.filter { index in
            let key = parts[index].split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            return String(key).removingPercentEncoding == name
        }
        guard matches.count <= 1 else { throw StreamURLResolutionError.ambiguousParameter }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw StreamURLResolutionError.invalidTransformResult
        }
        let replacement = "\(name)=\(encoded)"
        if let index = matches.first { parts[index] = replacement } else { parts.append(replacement) }
        components.percentEncodedQuery = parts.joined(separator: "&")
        guard let result = components.url else { throw StreamURLResolutionError.invalidURL }
        return result
    }
}
