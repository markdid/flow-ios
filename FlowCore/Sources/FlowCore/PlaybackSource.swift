// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client Copyright (C) 2025-2026 A-EDev.
// Modified Swift implementation, 2026-11-06. Inspired by InnerTube.kt and
// player/resolver/VideoPlaybackResolver.kt at upstream 3f3e2a6101fe511003f8b694876fe8c6ece89c66.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PlaybackSource: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case hls, video, audio }
    public let id: String
    public let url: URL
    public let label: String
    public let kind: Kind
    public let height: Int
    public init(id: String, url: URL, label: String, kind: Kind, height: Int = 0) {
        self.id = id; self.url = url; self.label = label; self.kind = kind; self.height = height
    }
}

public enum PlaybackError: LocalizedError {
    case malformedResponse, http(Int), unavailable(String), unsupportedExtraction
    public var errorDescription: String? {
        switch self {
        case .malformedResponse: return "The playback service returned an invalid response."
        case .http(let code): return "The playback service returned HTTP \(code)."
        case .unavailable(let reason): return reason
        case .unsupportedExtraction: return "No compatible native stream was returned. This iOS port does not yet support YouTube signature deciphering, n-token transformation, PO tokens, SABR, or separate video/audio DASH streams. Try the embedded player."
        }
    }
}

/// Rejects unsupported extraction instead of silently playing a video-only stream.
public enum PlaybackResponseParser {
    public static func parse(_ data: Data) throws -> [PlaybackSource] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = root["playabilityStatus"] as? [String: Any],
              let code = status["status"] as? String else { throw PlaybackError.malformedResponse }
        guard code == "OK" else { throw PlaybackError.unavailable(status["reason"] as? String ?? "YouTube refused playback (\(code)).") }
        guard let streaming = root["streamingData"] as? [String: Any] else { throw PlaybackError.unsupportedExtraction }
        var sources: [PlaybackSource] = []
        if let raw = streaming["hlsManifestUrl"] as? String, let url = safeStreamURL(raw) {
            sources.append(PlaybackSource(id: "hls", url: url, label: "Auto (HLS)", kind: .hls))
        }
        for value in streaming["formats"] as? [[String: Any]] ?? [] {
            guard value["signatureCipher"] == nil, value["cipher"] == nil,
                  let raw = value["url"] as? String, let url = safeStreamURL(raw),
                  let mime = value["mimeType"] as? String, mime.hasPrefix("video/mp4"),
                  value["audioQuality"] != nil || value["audioChannels"] != nil,
                  let itag = value["itag"] as? Int else { continue }
            let height = value["height"] as? Int ?? 0
            sources.append(PlaybackSource(id: String(itag), url: url,
                label: value["qualityLabel"] as? String ?? "MP4", kind: .video, height: height))
        }
        for value in streaming["adaptiveFormats"] as? [[String: Any]] ?? [] {
            guard value["signatureCipher"] == nil, value["cipher"] == nil,
                  let raw = value["url"] as? String, let url = safeStreamURL(raw),
                  let mime = value["mimeType"] as? String, mime.hasPrefix("audio/mp4"),
                  let itag = value["itag"] as? Int else { continue }
            sources.append(PlaybackSource(id: String(itag), url: url, label: "Audio only (AAC)", kind: .audio))
        }
        guard !sources.isEmpty else { throw PlaybackError.unsupportedExtraction }
        return sources.sorted {
            let lhs = $0.kind == .hls ? 2 : ($0.kind == .video ? 1 : 0)
            let rhs = $1.kind == .hls ? 2 : ($1.kind == .video ? 1 : 0)
            return lhs == rhs ? $0.height > $1.height : lhs > rhs
        }
    }
    private static func safeStreamURL(_ raw: String) -> URL? {
        // Without supplied transforms the shared resolver rejects cipher/n requirements.
        try? StreamURLResolver.resolve(directURL: raw)
    }
}

public struct PlaybackClient {
    private let session: URLSession
    public init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }
    public func resolve(_ video: VideoReference) async throws -> [PlaybackSource] {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("1", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("2.20260710.06.00", forHTTPHeaderField: "X-YouTube-Client-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "videoId": video.id,
            "context": ["client": ["clientName": "WEB", "clientVersion": "2.20260710.06.00", "hl": "en", "gl": "US"]]
        ])
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw PlaybackError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else { throw PlaybackError.http(http.statusCode) }
        guard data.count < 10_000_000 else { throw PlaybackError.malformedResponse }
        return try PlaybackResponseParser.parse(data)
    }
}
