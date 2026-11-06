// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client Copyright (C) 2025-2026 A-EDev.
// Swift subset of SponsorBlockSegment/ActionPolicy/Handler, modified 2026-11-06.
import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SponsorSegment: Identifiable, Equatable, Sendable {
    public let id: String
    public let category: String
    public let start: Double
    public let end: Double
    public init(id: String, category: String, start: Double, end: Double) {
        self.id = id; self.category = category; self.start = start; self.end = end
    }
    public var isValid: Bool { !id.isEmpty && start.isFinite && end.isFinite && start >= 0 && end > start }
    public func contains(_ position: Double) -> Bool { position.isFinite && position >= start && position < end }
    /// Keep unknown-duration segments for later, but never turn an unvalidated end into a seek.
    public func canSkip(duration: Double?) -> Bool {
        guard isValid, let duration, duration.isFinite, duration > 0 else { return false }
        return start < duration && end <= duration
    }
}
public enum SponsorBlockError: LocalizedError {
    case malformed, oversized, invalidVideo, http(Int)
    public var errorDescription: String? {
        switch self {
        case .malformed: return "SponsorBlock returned an unsupported response."
        case .oversized: return "SponsorBlock returned too much segment data."
        case .invalidVideo: return "This video identifier is invalid."
        case .http(let status): return "SponsorBlock returned HTTP \(status)."
        }
    }
}
public enum SponsorBlockParser {
    public static let categories = ["sponsor", "selfpromo", "interaction", "intro", "outro", "preview", "music_offtopic", "filler"]
    public static func parse(_ data: Data) throws -> [SponsorSegment] {
        guard data.count <= 2_000_000 else { throw SponsorBlockError.oversized }
        guard let items = try JSONSerialization.jsonObject(with: data) as? [Any] else { throw SponsorBlockError.malformed }
        var seen = Set<String>()
        return items.compactMap { value -> SponsorSegment? in
            guard let item = value as? [String: Any], item["actionType"] as? String == "skip",
                  let id = item["UUID"] as? String, let category = item["category"] as? String,
                  categories.contains(category), let range = item["segment"] as? [Any], range.count == 2,
                  let start = range[0] as? NSNumber, let end = range[1] as? NSNumber,
                  CFGetTypeID(start) != CFBooleanGetTypeID(), CFGetTypeID(end) != CFBooleanGetTypeID() else { return nil }
            let segment = SponsorSegment(id: id, category: category, start: start.doubleValue, end: end.doubleValue)
            guard segment.isValid, seen.insert(id).inserted else { return nil }
            return segment
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
}

/// Skip-once state is scoped to one video visit. Rewinds offer manual skipping, never another
/// automatic skip; this also prevents approximate seeks landing near an end from looping.
public struct SponsorSkipSession: Sendable {
    public let segments: [SponsorSegment]
    public private(set) var skippedOnce = Set<String>()
    public init(segments: [SponsorSegment]) {
        self.segments = segments.filter(\.isValid).sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
    public func current(at position: Double) -> SponsorSegment? { segments.first { $0.contains(position) } }
    public func current(at position: Double, duration: Double?) -> SponsorSegment? {
        segments.first { $0.contains(position) && $0.canSkip(duration: duration) }
    }
    public mutating func automaticTarget(at position: Double, isPlaying: Bool, duration: Double? = nil) -> SponsorSegment? {
        guard isPlaying, let segment = current(at: position, duration: duration), !skippedOnce.contains(segment.id) else { return nil }
        skippedOnce.insert(segment.id)
        return segment
    }
    public mutating func manualTarget(at position: Double, duration: Double?) -> SponsorSegment? {
        guard let segment = current(at: position, duration: duration) else { return nil }
        skippedOnce.insert(segment.id)
        return segment
    }
    public mutating func markSkipped(_ segment: SponsorSegment) {
        if segments.contains(segment) { skippedOnce.insert(segment.id) }
    }
}
public struct SponsorBlockClient {
    private let session: URLSession
    public init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }
    public static func request(videoID: String) throws -> URLRequest {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)"),
              let video = try? VideoReference(url: url), video.id == videoID else { throw SponsorBlockError.invalidVideo }
        var components = URLComponents(string: "https://sponsor.ajay.app/api/skipSegments")!
        components.queryItems = [URLQueryItem(name: "videoID", value: videoID),
            URLQueryItem(name: "categories", value: String(data: try JSONEncoder().encode(SponsorBlockParser.categories), encoding: .utf8)),
            URLQueryItem(name: "actionTypes", value: "[\"skip\"]")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        return request
    }
    public func fetch(videoID: String) async throws -> [SponsorSegment] {
        let (data, response) = try await session.data(for: Self.request(videoID: videoID))
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw SponsorBlockError.malformed }
        if http.statusCode == 404 { return [] }
        guard (200..<300).contains(http.statusCode) else { throw SponsorBlockError.http(http.statusCode) }
        return try SponsorBlockParser.parse(data)
    }
}
