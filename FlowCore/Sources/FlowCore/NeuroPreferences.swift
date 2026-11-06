// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Flow Android Client, Copyright (C) 2025-2026 Flow | A-EDev.
// https://github.com/Flow-Tube/Flow
// NeuroFormats.kt and NeuroCategories.kt at 3f3e2a6101fe511003f8b694876fe8c6ece89c66.
import Foundation

/// Pure format preferences. Input words must already be folded/tokenized by the caller;
/// this lookup deliberately does not guess at title segmentation or stemming.
public enum NeuroFormats {
    public static let surfaces: [String: [String]] = [
        "review": ["review", "reviews", "reseña", "análisis", "análise", "обзор", "inceleme", "评测", "测评", "点评"],
        "unboxing": ["unboxing", "déballage", "распаковка", "开箱"],
        "reaction": ["reaction", "reactions", "reacting", "reacción", "reação", "réaction", "реакция", "tepki"],
        "tutorial": ["tutorial", "tutorials", "tuto", "tutoriel", "урок", "教程", "教学"],
        "explainer": ["explained", "explainer", "解说", "讲解"],
        "vlog": ["vlog", "vlogs"],
        "podcast": ["podcast", "podcasts", "подкаст", "播客"],
        "live": ["live", "livestream", "直播"],
        "compilation": ["compilation", "compilación", "compilação", "подборка", "合集", "混剪"],
        "playalong": ["playalong"],
        "cover": ["cover", "covers", "кавер", "翻唱"],
        "remix": ["remix", "remixes", "ремикс", "混音"],
        "gameplay": ["gameplay", "геймплей", "实况"],
        "walkthrough": ["walkthrough", "playthrough", "прохождение", "攻略", "通关"],
        "highlights": ["highlights", "resumen", "хайлайты", "集锦"],
        "trailer": ["trailer", "teaser", "tráiler", "трейлер", "fragman", "预告", "预告片"],
        "interview": ["interview", "interviews", "entrevista", "интервью", "röportaj", "采访", "访谈", "专访"],
        "documentary": ["documentary", "documental", "documentário", "documentaire", "belgesel", "纪录片"],
        "asmr": ["asmr"],
        "tier list": ["tier list"],
        "versus": ["versus", "vs"],
    ]
    private static let formatBySurface: [String: String] = Dictionary(
        uniqueKeysWithValues: surfaces.flatMap { id, words in words.map { ($0, id) } }
    )
    public static let maximumScoreTerm = 0.04
    public static func format(of foldedWord: String) -> String? { formatBySurface[foldedWord] }
    public static func searchWord(for format: String) -> String { surfaces[format]?.first ?? format }

    /// Learns from a positive signal; unused formats fade by 1% and weights below 0.01 drop.
    /// Discards nonfinite/negative imported weights and clamps finite weights to 1.
    public static func learn(_ affinity: [String: Double], formats: Set<String>) -> [String: Double] {
        let affinity = sanitizedAffinity(affinity)
        guard !formats.isEmpty else { return affinity }
        var updated = affinity
        for (format, value) in affinity where !formats.contains(format) { updated[format] = value * 0.99 }
        for format in formats { updated[format] = (updated[format] ?? 0) * 0.9 + 0.1 }
        return updated.filter { $0.value >= 0.01 }
    }
    /// Maximum, not sum: a candidate announcing many formats gets no additive advantage.
    public static func scoreTerm(_ affinity: [String: Double], formats: Set<String>) -> Double {
        let safe = sanitizedAffinity(affinity)
        return (formats.map { safe[$0] ?? 0 }.max() ?? 0) * maximumScoreTerm
    }
    private static func sanitizedAffinity(_ values: [String: Double]) -> [String: Double] {
        values.filter { $0.value.isFinite && $0.value >= 0 }.mapValues { min(1, $0) }
    }
}

public struct NeuroChannelCategory: Equatable, Sendable {
    public let id: String
    public let confidence: Double
    public init(id: String, confidence: Double) {
        self.id = id
        self.confidence = confidence.isFinite ? min(1, max(0, confidence)) : 0
    }
}

/// Category preference signals, separate from title topics and format affinity.
public enum NeuroCategories {
    private static let ids: [String: String] = [
        "film & animation": "film", "autos & vehicles": "autos", "music": "music",
        "pets & animals": "pets", "sports": "sports", "travel & events": "travel",
        "gaming": "gaming", "people & blogs": "people", "comedy": "comedy",
        "entertainment": "entertainment", "news & politics": "news", "howto & style": "howto",
        "education": "education", "science & technology": "science", "nonprofits & activism": "nonprofits"
    ]
    private static let specificity: [String: Double] = ["people": 0.3, "entertainment": 0.5]
    public static let maximumPenalty = 0.35
    public static let minimumSignals = 20.0
    public static let familiarShare = 0.10

    public static func id(for name: String?) -> String? {
        guard let name else { return nil }
        return ids[name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }
    public static func isTheme(_ id: String) -> Bool { ids.values.contains(id) && specificity[id] == nil }

    /// One strong signal adds one count. All counts halve after the total exceeds 400.
    /// Invalid imported counts are discarded; oversized finite counts are capped at 400,
    /// the maximum per-category count reachable through this learner.
    public static func learn(_ affinity: [String: Double], category: String) -> [String: Double] {
        var counted = sanitizedCounts(affinity)
        counted[category, default: 0] += 1
        return counted.values.reduce(0, +) > 400 ? counted.mapValues { $0 / 2 } : counted
    }
    public static func factor(_ affinity: [String: Double], category: NeuroChannelCategory) -> Double {
        let affinity = sanitizedCounts(affinity)
        let total = affinity.values.reduce(0, +)
        guard total >= minimumSignals else { return 1 }
        let share = (affinity[category.id] ?? 0) / total
        let mismatch = 1 - min(1, share / familiarShare)
        return 1 - maximumPenalty * category.confidence * mismatch * (specificity[category.id] ?? 1)
    }

    private static func sanitizedCounts(_ values: [String: Double]) -> [String: Double] {
        values.filter { $0.value.isFinite && $0.value >= 0 }.mapValues { min(400, $0) }
    }

    /// Channels vote using topic overlap times category confidence. Requires a 60% majority.
    /// Invalid topic weights contribute nothing; finite weights are clamped to 0...1.
    public static func clusterCategory(topics: [String], channelTopicProfiles: [String: [String: Double]],
                                       categoryOf: (String) -> NeuroChannelCategory?) -> String? {
        var votes: [String: Double] = [:]
        for (channel, profile) in channelTopicProfiles {
            let overlap = topics.reduce(0.0) { sum, topic in
                let weight = profile[topic] ?? 0
                return sum + (weight.isFinite ? min(1, max(0, weight)) : 0)
            }
            guard overlap > 0, let category = categoryOf(channel) else { continue }
            votes[category.id, default: 0] += overlap * category.confidence
        }
        let total = votes.values.reduce(0, +)
        guard total > 0 else { return nil }
        let top = votes.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.first!
        return top.value / total >= 0.6 ? top.key : nil
    }
}
