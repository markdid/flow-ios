// SPDX-License-Identifier: GPL-3.0-only
// Original Swift implementation of YouTube's documented WebView client-identification contract.
// https://developers.google.com/youtube/terms/required-minimum-functionality#api-client-identity-and-credentials
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum EmbeddedPlaybackRequestError: LocalizedError, Equatable, Sendable {
    case missingAppIdentity, invalidAppIdentity
    public var errorDescription: String? {
        switch self {
        case .missingAppIdentity: return "The app's bundle identifier is missing. Open this video on YouTube."
        case .invalidAppIdentity: return "The app's bundle identifier cannot identify the embedded player. Open this video on YouTube."
        }
    }
}

/// A request for the official embedded player, not direct-stream extraction.
/// The application must pass its actual Bundle.main.bundleIdentifier. Never pass another app's
/// identifier, an unrelated website, or a synthetic identity to work around a refusal.
/// No request is sent by this builder and no login, age, DRM or embedding restriction is changed.
public enum EmbeddedPlaybackRequest {
    public static func make(video: VideoReference, bundleIdentifier: String?) throws -> URLRequest {
        guard let identity = bundleIdentifier, !identity.isEmpty else {
            throw EmbeddedPlaybackRequestError.missingAppIdentity
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-.")
        let labels = identity.split(separator: ".", omittingEmptySubsequences: false)
        guard identity.utf8.count <= 253, labels.count >= 2,
              identity.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              labels.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 63 }) else {
            throw EmbeddedPlaybackRequestError.invalidAppIdentity
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = identity.lowercased()
        guard let referrer = components.url,
              referrer.host == identity.lowercased(), referrer.user == nil,
              referrer.password == nil, referrer.port == nil,
              referrer.query == nil, referrer.fragment == nil else {
            throw EmbeddedPlaybackRequestError.invalidAppIdentity
        }
        // Keep the existing privacy-enhanced official embed endpoint, controls and manual play.
        // App identification applies to privacy-enhanced embeds too.
        var request = URLRequest(url: video.embedURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(referrer.absoluteString, forHTTPHeaderField: "Referer")
        return request
    }
}
