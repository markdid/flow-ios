// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Flow Android Client, Copyright (C) 2025-2026 Flow | A-EDev.
// https://github.com/Flow-Tube/Flow at 3f3e2a6101fe511003f8b694876fe8c6ece89c66.
// NeuroTokenizer.kt calculateIdfWeight and extractFeatures final normalization/scalars.
import Foundation

/// Feature weighting and final vector assembly. The caller must supply already extracted
/// topic weights; this API does not pretend title-only candidates are a full feature extractor.
public enum NeuroContentFeatures {
    public enum TopicSource: Sendable {
        case channel, title, phrase, description
        public var baseWeight: Double {
            switch self {
            case .channel: return 0.6
            case .title: return 0.5
            case .phrase: return 1.2
            case .description: return 0.2
            }
        }
    }
    private static let highPacing: Set<String> = [
        "compilation", "tiktok", "tiktoks", "highlights", "speedrun", "trailer", "shorts",
        "montage", "moments", "best of", "try not to", "memes", "funny", "fails", "rapid",
        "fast", "quick", "minute", "seconds", "top 10", "top 5", "ranked", "tier list", "versus"
    ]
    private static let lowPacing: Set<String> = [
        "podcast", "essay", "ambient", "explained", "study", "meditation", "sleep", "asmr",
        "relaxing", "calm", "deep dive", "analysis", "lecture", "course", "documentary",
        "interview", "conversation", "discussion", "breakdown", "walkthrough"
    ]
    private static let timestamp = try! NSRegularExpression(pattern: "[0-9]{1,2}:[0-9]{2}")

    /// Cold-start leaves the base weight unchanged until 30 documents, then scales by
    /// normalized log-IDF with a 0.15 floor. Invalid base weights contribute zero.
    public static func idfWeight(for key: String, baseWeight: Double,
                                 snapshot: NeuroDocumentFrequency) -> Double {
        guard baseWeight.isFinite, baseWeight > 0 else { return 0 }
        guard snapshot.totalDocuments >= 30 else { return baseWeight }
        let documents = Double(snapshot.totalDocuments)
        let frequency = Double(snapshot.frequencies[key] ?? 0)
        let relative = log1p(documents / (frequency + 1)) / log1p(documents)
        return baseWeight * min(1, max(0.15, relative))
    }

    public static func idfWeight(for key: String, source: TopicSource,
                                 snapshot: NeuroDocumentFrequency) -> Double {
        idfWeight(for: key, baseWeight: source.baseWeight, snapshot: snapshot)
    }

    /// L2 normalization, with scaling to prevent overflow when imported finite weights are huge.
    /// Discards negative/nonfinite weights and keys outside the shared 40-UTF-16-unit limit.
    public static func normalizedTopics(_ weightedTopics: [String: Double]) -> [String: Double] {
        let valid = weightedTopics.filter {
            !$0.key.isEmpty && $0.key.utf16.count <= 40 && $0.value.isFinite && $0.value > 0
        }
        guard let largest = valid.values.max() else { return [:] }
        let scaled = valid.mapValues { $0 / largest }
        let magnitude = sqrt(scaled.values.reduce(0) { $0 + $1 * $1 })
        return scaled.mapValues { $0 / magnitude }
    }

    /// Log-normalized duration, matching upstream defaults: live=3600, unknown=300 seconds.
    public static func durationScore(seconds: Double, isLive: Bool) -> Double {
        let duration = seconds.isFinite && seconds > 0 ? seconds : (isLive ? 3600 : 300)
        return min(1, max(0, log1p(duration) / log1p(7200)))
    }

    /// Upstream uses substring checks, not token matches. Overlapping cues count separately
    /// (for example, "tiktoks" matches both "tiktok" and "tiktoks").
    public static func pacingScore(title: String, isShort: Bool) -> Double {
        let lower = title.lowercased()
        let high = highPacing.filter { lower.contains($0) }.count
        let low = lowPacing.filter { lower.contains($0) }.count
        if high > low { return min(0.95, 0.6 + Double(high) * 0.1) }
        if low > high { return max(0.05, 0.4 - Double(low) * 0.1) }
        return isShort ? 0.85 : 0.5
    }

    /// UTF-16 lengths match Kotlin String.length. At least three timestamp matches add 0.2;
    /// this is upstream's heuristic, not validation of a genuine chapter list.
    public static func complexityScore(title: String, description: String?) -> Double {
        let words = title.split(whereSeparator: { $0.isWhitespace }).filter { $0.utf16.count > 1 }
        let average = words.isEmpty ? 4 : words.reduce(0.0) { $0 + Double($1.utf16.count) } / Double(words.count)
        let titleFactor = min(0.4, Double(title.utf16.count) / 80)
        let wordFactor = min(0.4, average / 8)
        var chapterBonus = 0.0
        if let description {
            var count = 0
            timestamp.enumerateMatches(in: description, range: NSRange(description.startIndex..., in: description)) { match, _, stop in
                if match != nil { count += 1 }
                if count >= 3 { stop.pointee = true }
            }
            if count >= 3 { chapterBonus = 0.2 }
        }
        return min(1, max(0, titleFactor + wordFactor + chapterBonus))
    }

    public static func vector(weightedTopics: [String: Double], title: String,
                              description: String? = nil, durationSeconds: Double = 0,
                              isLive: Bool = false, isShort: Bool = false,
                              formats: Set<String> = []) -> NeuroContentVector {
        NeuroContentVector(topics: normalizedTopics(weightedTopics),
                           duration: durationScore(seconds: durationSeconds, isLive: isLive),
                           pacing: pacingScore(title: title, isShort: isShort),
                           complexity: complexityScore(title: title, description: description),
                           isLive: isLive ? 1 : 0, formats: formats)
    }
}
