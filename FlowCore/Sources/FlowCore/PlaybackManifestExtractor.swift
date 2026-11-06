// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client Copyright (C) 2025-2026 A-EDev.
// Swift adaptation of the format URL assembly stage in player/stream/
// InnerTubeVideoStreamExtractor.kt, upstream 3f3e2a6101fe511003f8b694876fe8c6ece89c66.
// Conservative AVPlayer format selection and diagnostics are specific to this iOS port.
import Foundation
import CoreFoundation

public struct PlaybackExtractionReport: Sendable {
    public enum Rejection: Equatable, Sendable {
        case malformedFormat, protectedFormat, unsupportedCodecs, separateVideoTrack, duplicate
        case unresolvedURL(StreamURLResolutionError)
        case transformFailed
    }
    public struct SkippedFormat: Equatable, Sendable {
        public let id: String
        public let reason: Rejection
    }
    public let sources: [PlaybackSource]
    public let skipped: [SkippedFormat]
}

/// Offline response processing only. Does not fetch, run JavaScript, retry refusals, or bypass
/// access restrictions. Optional transforms must belong to the response's exact player version.
/// No default decipher functions exist. PlaybackClient is not wired to this experimental path.
public enum PlaybackManifestExtractor {
    public static func extract(_ data: Data,
                               signatureTransform: StreamURLResolver.Transform? = nil,
                               nTransform: StreamURLResolver.Transform? = nil) throws -> PlaybackExtractionReport {
        guard data.count <= 10_000_000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = root["playabilityStatus"] as? [String: Any],
              let code = status["status"] as? String else { throw PlaybackError.malformedResponse }
        guard code == "OK" else {
            throw PlaybackError.unavailable(status["reason"] as? String ?? "YouTube refused playback (\(code)).")
        }
        guard let streaming = root["streamingData"] as? [String: Any] else { throw PlaybackError.unsupportedExtraction }
        let formats = streaming["formats"] as? [Any] ?? []
        let adaptive = streaming["adaptiveFormats"] as? [Any] ?? []
        guard formats.count + adaptive.count <= 512 else { throw PlaybackError.malformedResponse }
        var sources: [PlaybackSource] = []
        var skipped: [PlaybackExtractionReport.SkippedFormat] = []
        var seen = Set<String>()
        func reject(_ id: String, _ reason: PlaybackExtractionReport.Rejection) {
            skipped.append(.init(id: id, reason: reason))
        }
        func resolve(_ id: String, direct: String?, cipher: String?) -> URL? {
            do {
                return try StreamURLResolver.resolve(directURL: direct, signatureCipher: cipher,
                    signatureTransform: signatureTransform, nTransform: nTransform)
            } catch let error as StreamURLResolutionError {
                reject(id, .unresolvedURL(error))
            } catch { reject(id, .transformFailed) }
            return nil
        }
        if let hls = streaming["hlsManifestUrl"] as? String,
           let url = resolve("hls", direct: hls, cipher: nil) {
            sources.append(PlaybackSource(id: "hls", url: url, label: "Auto (HLS)", kind: .hls))
        }
        for (isAdaptive, entries) in [(false, formats), (true, adaptive)] {
            for (index, entry) in entries.enumerated() {
                let unknownID = "\(isAdaptive ? "adaptive" : "format")-\(index)"
                guard let value = entry as? [String: Any], let itag = jsonInteger(value["itag"]),
                      itag > 0, itag < 1_000_000, let mime = value["mimeType"] as? String else {
                    reject(unknownID, .malformedFormat); continue
                }
                let id = String(itag)
                let height: Int
                if let rawHeight = value["height"] {
                    guard let numericHeight = jsonInteger(rawHeight) else {
                        reject(id, .malformedFormat); continue
                    }
                    height = min(4320, max(0, numericHeight))
                } else { height = 0 }
                if let families = value["drmFamilies"], !(families is NSNull) {
                    guard let list = families as? [Any], list.isEmpty else {
                        reject(id, .protectedFormat); continue
                    }
                }
                guard value["drmTrackType"] == nil, value["drmParams"] == nil else {
                    reject(id, .protectedFormat); continue
                }
                let container = mime.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
                let codecs = codecList(mime)
                let kind: PlaybackSource.Kind
                if container == "audio/mp4", isAdaptive,
                   codecs.count == 1, codecs[0].hasPrefix("mp4a.") {
                    kind = .audio
                } else if container == "video/mp4" {
                    if isAdaptive { reject(id, .separateVideoTrack); continue }
                    guard codecs.count == 2,
                          codecs.contains(where: { $0.hasPrefix("avc1.") || $0.hasPrefix("avc3.") }),
                          codecs.contains(where: { $0.hasPrefix("mp4a.") }) else {
                        reject(id, .unsupportedCodecs); continue
                    }
                    kind = .video
                } else { reject(id, .unsupportedCodecs); continue }
                // Distinct cipher spellings are accepted, but conflicting envelopes are not.
                let signatureCipher = value["signatureCipher"] as? String
                let cipher = value["cipher"] as? String
                guard signatureCipher == nil || cipher == nil || signatureCipher == cipher else {
                    reject(id, .malformedFormat); continue
                }
                guard let url = resolve(id, direct: value["url"] as? String, cipher: signatureCipher ?? cipher) else { continue }
                guard seen.insert(id).inserted else { reject(id, .duplicate); continue }
                let label = kind == .audio ? "Audio only (AAC)" : (height > 0 ? "\(height)p (MP4)" : "MP4")
                sources.append(PlaybackSource(id: id, url: url, label: label, kind: kind, height: height))
            }
        }
        let sorted = sources.sorted {
            func rank(_ kind: PlaybackSource.Kind) -> Int { kind == .hls ? 2 : (kind == .video ? 1 : 0) }
            if rank($0.kind) != rank($1.kind) { return rank($0.kind) > rank($1.kind) }
            if $0.height != $1.height { return $0.height > $1.height }
            return $0.id < $1.id
        }
        return PlaybackExtractionReport(sources: sorted, skipped: skipped)
    }

    /// JSONSerialization bridges booleans through NSNumber, and `as? Int` alone can accept
    /// true as 1. Check the Core Foundation type before any integer conversion.
    private static func jsonInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number as? Int
    }

    private static func codecList(_ mime: String) -> [String] {
        guard mime.utf8.count <= 1024,
              let expression = try? NSRegularExpression(pattern: #"(?:^|;)\s*codecs\s*=\s*"([^"]+)""#, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: mime, range: NSRange(mime.startIndex..., in: mime)),
              let range = Range(match.range(at: 1), in: mime) else { return [] }
        return mime[range].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    }
}
