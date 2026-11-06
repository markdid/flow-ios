// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Flow Android Client, Copyright (C) 2025-2026 Flow | A-EDev.
// https://github.com/Flow-Tube/Flow
// NeuroVectorMath.kt / NeuroModels.kt at 3f3e2a6101fe511003f8b694876fe8c6ece89c66.
import Foundation

/// Pure recommendation math only. Does not tokenize titles, persist a brain, or rank a feed.
public struct NeuroContentVector: Equatable, Sendable {
    public var topics: [String: Double]
    public var duration: Double
    public var pacing: Double
    public var complexity: Double
    public var isLive: Double
    public var formats: Set<String>

    /// Rejects nonfinite weights and clamps normalized inputs at the API boundary.
    public init(topics: [String: Double] = [:], duration: Double = 0.5,
                pacing: Double = 0.5, complexity: Double = 0.5,
                isLive: Double = 0, formats: Set<String> = []) {
        self.topics = topics.filter { !$0.key.isEmpty && $0.value.isFinite && $0.value > 0 }
            .mapValues { min(1, $0) }
        self.duration = Self.unit(duration)
        self.pacing = Self.unit(pacing)
        self.complexity = Self.unit(complexity)
        self.isLive = Self.unit(isLive)
        self.formats = formats
    }
    fileprivate static func unit(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}

public enum NeuroVectorMath {
    public enum Horizon: Sendable {
        case longTerm, recent, timeOfDay
        fileprivate var saturation: Double { self == .recent ? 3 : 30 }
        fileprivate var halfLife: Double { self == .recent ? 25 : 600 }
        fileprivate var maxTopics: Int {
            switch self { case .longTerm: return 300; case .recent: return 60; case .timeOfDay: return 100 }
        }
    }

    private static func base(_ key: String) -> String {
        String(key.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)[0])
    }
    private static func length(_ topics: [String: Double]) -> Double {
        sqrt(topics.values.reduce(0) { $0 + $1 * $1 })
    }
    /// Immutable lookup snapshot reusable while scoring many candidates against one taste vector.
    public struct PreparedVector: Sendable {
        public let vector: NeuroContentVector
        fileprivate let magnitude: Double
        fileprivate let baseToTagged: [String: Double]
        fileprivate let untagged: [String: Double]

        public init(_ vector: NeuroContentVector) {
            let sanitized = NeuroVectorMath.clean(vector)
            self.vector = sanitized
            magnitude = NeuroVectorMath.length(sanitized.topics)
            var selected: [String: (key: String, value: Double)] = [:]
            var plain: [String: Double] = [:]
            for (key, value) in sanitized.topics {
                if key.contains(":") {
                    let base = NeuroVectorMath.base(key)
                    // Lexicographic tie resolution is deterministic without sorting all keys.
                    if selected[base] == nil || key < selected[base]!.key {
                        selected[base] = (key, value)
                    }
                } else { plain[key] = value }
            }
            baseToTagged = selected.mapValues { $0.value }
            untagged = plain
        }

        fileprivate func match(_ key: String) -> Double? {
            if let exact = vector.topics[key] { return exact }
            if key.contains(":") { return untagged[NeuroVectorMath.base(key)].map { $0 * 0.3 } }
            return baseToTagged[key].map { $0 * 0.3 }
        }
    }
    private static func clean(_ v: NeuroContentVector) -> NeuroContentVector {
        NeuroContentVector(topics: v.topics, duration: v.duration, pacing: v.pacing,
                           complexity: v.complexity, isLive: v.isLive, formats: v.formats)
    }

    public static func similarity(_ user: NeuroContentVector, _ content: NeuroContentVector) -> Double {
        similarity(PreparedVector(user), content)
    }

    /// Reuses the user's lookup when it is the larger vector. Otherwise indexes the content
    /// once to preserve upstream's smaller-to-larger migration matching direction.
    public static func similarity(_ user: PreparedVector, _ content: NeuroContentVector) -> Double {
        let u = user.vector, c = clean(content)
        let scalar = (1 - abs(u.duration - c.duration)) * 0.1
            + (1 - abs(u.pacing - c.pacing)) * 0.1
            + (1 - abs(u.complexity - c.complexity)) * 0.1
        let small: [String: Double]
        let large: PreparedVector
        if u.topics.count <= c.topics.count {
            small = u.topics
            large = PreparedVector(c)
        } else {
            small = c.topics
            large = user
        }
        var dot = 0.0
        var intersects = false
        for (key, value) in small {
            if let other = large.match(key) { dot += value * other; intersects = true }
        }
        guard intersects else { return scalar * 0.3 }
        let denominator = user.magnitude * length(c.topics)
        return (denominator > 0 ? dot / denominator * 0.7 : 0) + scalar
    }

    /// No scalar credit when topics do not overlap. Specificity is squared upstream.
    /// This is not a probability: migration aliases may reuse one user weight and produce
    /// a value above 1, as upstream does. Consumers must not assume a unit interval.
    public static func topicSimilarity(_ user: NeuroContentVector, _ content: NeuroContentVector,
                                       specificity: (String) -> Double = { _ in 1 }) -> Double {
        topicSimilarity(PreparedVector(user), content, specificity: specificity)
    }

    /// Prepared overload for ranking many candidates; each match is a dictionary lookup.
    /// Like the unprepared overload, this score may exceed 1 for migration aliases.
    public static func topicSimilarity(_ user: PreparedVector, _ content: NeuroContentVector,
                                       specificity: (String) -> Double = { _ in 1 }) -> Double {
        let c = clean(content)
        let denominator = user.magnitude * length(c.topics)
        guard denominator > 0 else { return 0 }
        let dot = c.topics.reduce(0.0) { result, entry in
            let weight = NeuroContentVector.unit(specificity(entry.key))
            return result + entry.value * (user.match(entry.key) ?? 0) * weight * weight
        }
        return dot / denominator
    }

    /// Evidence-based positive learning. One full watch has strength 1.
    /// Invalid or zero-strength events are ignored rather than decaying stored interests.
    public static func learn(_ current: NeuroContentVector, from video: NeuroContentVector,
                             strength: Double, horizon: Horizon, scalarRate: Double,
                             protected: Set<String> = []) -> NeuroContentVector {
        let current = clean(current), video = clean(video)
        guard strength.isFinite, strength > 0, scalarRate.isFinite else { return current }
        let keep = pow(0.5, strength / horizon.halfLife)
        var result = current
        var topics: [String: Double] = [:]
        for (key, weight) in current.topics {
            let decayed = 1 - pow(1 - min(weight, 0.999999), keep)
            if decayed >= 0.005 || video.topics[key] != nil { topics[key] = decayed }
        }
        for (key, share) in video.topics {
            topics[key] = 1 - (1 - min(topics[key] ?? 0, 0.999999)) * exp(-strength * share / horizon.saturation)
        }
        var phrases: [String: Double] = [:]
        for (key, weight) in topics where base(key).contains(" ") {
            for word in base(key).components(separatedBy: " ") { phrases[word] = max(phrases[word] ?? 0, weight) }
        }
        topics = topics.filter { key, weight in
            key.contains(" ") || protected.contains(key) || (phrases[key] ?? 0) <= weight * 10
        }
        result.topics = topics
        let rate = NeuroContentVector.unit(scalarRate)
        func scalar(_ old: Double, _ target: Double) -> Double {
            NeuroContentVector.unit(old + (target - old) * rate * pow(1 - old, 2))
        }
        result.duration = scalar(current.duration, video.duration)
        result.pacing = scalar(current.pacing, video.pacing)
        result.complexity = scalar(current.complexity, video.complexity)
        result.isLive = scalar(current.isLive, video.isLive)
        return capTopics(result, maximum: horizon.maxTopics, protected: protected)
    }

    /// Protected base keys can exceed maximum, matching upstream's exemption semantics.
    public static func capTopics(_ vector: NeuroContentVector, maximum: Int,
                                 protected: Set<String> = []) -> NeuroContentVector {
        var result = clean(vector)
        let sorted = result.topics.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        result.topics = Dictionary(uniqueKeysWithValues: sorted.enumerated().compactMap { index, entry in
            index < max(0, maximum) || protected.contains(base(entry.key)) ? (entry.key, entry.value) : nil
        })
        return result
    }

    public static func blend(longTerm: NeuroContentVector, recent: NeuroContentVector,
                             recentShare: Double = 0.25) -> NeuroContentVector {
        var result = clean(longTerm)
        let recent = clean(recent)
        let recentLength = length(recent.topics)
        guard recentLength > 0 else { return result }
        let longLength = length(result.topics), share = NeuroContentVector.unit(recentShare)
        result.topics = longLength > 0 ? result.topics.mapValues { $0 / longLength * (1 - share) } : [:]
        for (key, value) in recent.topics { result.topics[key, default: 0] += value / recentLength * share }
        return result
    }

    public static func titleSimilarity(_ first: Set<String>, _ second: Set<String>) -> Double {
        guard !first.isEmpty, !second.isEmpty else { return 0 }
        return Double(first.intersection(second).count) / Double(first.union(second).count)
    }
}
