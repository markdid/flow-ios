// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Flow Android Client, Copyright (C) 2025-2026 Flow | A-EDev.
// https://github.com/Flow-Tube/Flow at 3f3e2a6101fe511003f8b694876fe8c6ece89c66.
// NeuroPhrases.kt and phrase-selection portions of NeuroTokenizer.kt.
import Foundation

/// Counts must represent distinct videos, not repeated playback/like events for one video.
/// This snapshot does not maintain that ledger or persist data.
public struct NeuroDocumentFrequency: Equatable, Sendable {
    public let totalDocuments: Int
    public let frequencies: [String: Int]
    public init(totalDocuments: Int, frequencies: [String: Int]) {
        self.totalDocuments = max(0, totalDocuments)
        self.frequencies = frequencies.filter { !$0.key.isEmpty && $0.value > 0 }
            .mapValues { min(max(0, totalDocuments), $0) }.filter { $0.value > 0 }
    }
}

public enum NeuroPhrasePromotion {
    public static let minimumDocuments = 10
    public static let minimumCount = 3
    public static let minimumNPMI = 0.5
    public static let minimumMergedShare = 0.5

    /// Normalized pointwise mutual information. Missing or zero joint count is unknown.
    /// A phrase may claim its words, so their effective counts are at least the joint count.
    public static func npmi(_ bigram: String, in snapshot: NeuroDocumentFrequency) -> Double? {
        guard let space = bigram.firstIndex(of: " "), space != bigram.startIndex,
              bigram.index(after: space) != bigram.endIndex,
              snapshot.totalDocuments > 0, let joint = snapshot.frequencies[bigram] else { return nil }
        let first = max(snapshot.frequencies[String(bigram[..<space])] ?? 0, joint)
        let second = max(snapshot.frequencies[String(bigram[bigram.index(after: space)...])] ?? 0, joint)
        let n = Double(snapshot.totalDocuments), pJoint = Double(joint) / Double(snapshot.totalDocuments)
        if pJoint >= 1 { return 1 }
        return log(pJoint / ((Double(first) / n) * (Double(second) / n))) / -log(pJoint)
    }
    public static func isPhrase(_ bigram: String, in snapshot: NeuroDocumentFrequency) -> Bool {
        guard snapshot.totalDocuments >= minimumDocuments,
              (snapshot.frequencies[bigram] ?? 0) >= minimumCount,
              let score = npmi(bigram, in: snapshot) else { return false }
        return score >= minimumNPMI
    }

    /// Accepts an already segmented merged-run candidate; does not perform Han segmentation.
    /// Uses UTF-16 units to match upstream Char iteration, including its supplementary limit.
    public static func isMergedRun(_ run: String, in snapshot: NeuroDocumentFrequency) -> Bool {
        guard !run.isEmpty, snapshot.totalDocuments >= minimumDocuments,
              let joint = snapshot.frequencies[run], joint >= minimumCount else { return false }
        let characterCounts = run.utf16.compactMap { unit in
            snapshot.frequencies[String(decoding: [unit], as: UTF16.self)]
        }
        guard let smallest = characterCounts.min() else { return false }
        return Double(joint) >= minimumMergedShare * Double(max(smallest, joint))
    }

    public struct Selection: Equatable, Sendable {
        public let phrases: Set<String>
        public let unclaimedWords: Set<String>
        public var topics: Set<String> { phrases.union(unclaimedWords) }
    }

    /// Promotion and positional word claiming from the upstream title feature pass.
    /// Catalog/compound keys must be supplied; no catalog parity or topic weights are implied.
    /// Statistical promotion applies only to two-word runs, as in upstream isKnownPhrase.
    public static func select(from title: NeuroTitleChunks, in snapshot: NeuroDocumentFrequency,
                              tagPhrases: Set<String> = [], catalogPhrases: Set<String> = [],
                              compoundTerms: Set<String> = []) -> Selection {
        let expressions = Set(NeuroChunkLexicon.expressions.values)
        let known = tagPhrases.union(catalogPhrases).union(compoundTerms).union(expressions)
        var phrases: Set<String> = [], words: Set<String> = []
        let neverAlone: Set<String> = ["pro", "max", "ultra", "plus", "mini"]
        for chunk in title.chunks {
            var claimed: Set<Int> = []
            for start in chunk.indices {
                var count = chunk[start].split(separator: " ").count
                guard start + 1 < chunk.count else { continue }
                for end in (start + 1)..<chunk.count {
                    count += chunk[end].split(separator: " ").count
                    if count > 3 { break }
                    let key = chunk[start...end].joined(separator: " ")
                    guard key.utf16.count <= 40 else { continue }
                    if known.contains(key) || (count == 2 && isPhrase(key, in: snapshot)) {
                        phrases.insert(key)
                        claimed.formUnion(start...end)
                    }
                }
            }
            for index in chunk.indices where !claimed.contains(index) {
                let word = chunk[index]
                if !neverAlone.contains(word), word.utf16.count <= 40 { words.insert(word) }
            }
        }
        return Selection(phrases: phrases, unclaimedWords: words)
    }

    /// Per-video set: repeated words/runs count once. Actual IDF accounting/deduplication by
    /// video ID belongs to the caller. Learned keys can include description/channel features.
    public static func documentTerms(title: NeuroTitleChunks, learnedKeys: Set<String> = []) -> Set<String> {
        learnedKeys.union(title.words).union(title.runCandidates).union(title.modelPairs)
    }
}
