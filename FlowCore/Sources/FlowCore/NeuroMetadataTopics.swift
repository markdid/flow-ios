// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Flow Android Client, Copyright (C) 2025-2026 Flow | A-EDev.
// https://github.com/Flow-Tube/Flow at 3f3e2a6101fe511003f8b694876fe8c6ece89c66.
// NeuroTokenizer.kt topicTags, extractDescriptionKeywords and processTags.
import Foundation

public enum NeuroMetadataTopics {
    private static let hashtags = try! NSRegularExpression(pattern: "#([\\p{L}\\p{N}_]{3,40})")
    private static let shortTopics: Set<String> = ["ai", "ml", "2d", "3d", "4k", "8k", "f1", "pc", "tv", "vr", "ar", "dj", "ui", "ux", "ev", "rc", "uk"]

    /// Creator tags followed by at most five description hashtags, preserving first occurrence.
    /// As upstream, no-description input returns creator tags unchanged, including duplicates.
    public static func topicTags(creatorTags: [String], description: String?) -> [String] {
        guard let description, description.contains("#") else { return creatorTags }
        var found: [String] = []
        hashtags.enumerateMatches(in: description, range: NSRange(description.startIndex..., in: description)) { match, _, stop in
            if let match, let range = Range(match.range(at: 1), in: description) {
                found.append(description[range].replacingOccurrences(of: "_", with: " "))
            }
            if found.count >= 5 { stop.pointee = true }
        }
        var seen: Set<String> = []
        return (creatorTags + found).filter { seen.insert($0).inserted }
    }

    /// Upstream sponsor/link/hashtag/shouting filters, first five surviving lines.
    public static func descriptionContent(_ description: String?) -> String {
        guard let description, description.utf16.count >= 20 else { return "" }
        return description.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            return trimmed.utf16.count > 15 && !lower.contains("http") && !lower.hasPrefix("#")
                && !NeuroMetadataLexicon.sponsorPatterns.contains(where: { lower.contains($0) })
                && !isShouted(line)
        }.prefix(5).joined(separator: " ")
    }
    private static func isShouted(_ text: String) -> Bool {
        var capitals = 0, uncased = 0
        for scalar in text.unicodeScalars {
            if CharacterSet.lowercaseLetters.contains(scalar) { return false }
            if CharacterSet.uppercaseLetters.contains(scalar) { capitals += 1 }
            else if CharacterSet.letters.contains(scalar) { uncased += 1 }
        }
        return capitals >= uncased
    }

    /// Inject the final upstream-equivalent tokenizer when available. This function applies
    /// only description filtering, first-15-token ingestion, accumulation and IDF weighting.
    public static func descriptionWeights(_ description: String?, snapshot: NeuroDocumentFrequency,
                                          tokenize: (String) throws -> [String]) rethrows -> [String: Double] {
        let content = descriptionContent(description)
        guard !content.isEmpty else { return [:] }
        var result: [String: Double] = [:]
        for key in try tokenize(content).prefix(15) where validKey(key) {
            result[key, default: 0] += NeuroContentFeatures.idfWeight(for: key, source: .description, snapshot: snapshot)
        }
        return result
    }

    /// Tag pipeline with explicit tokenization and domain-resolution dependencies.
    /// There is no silent identity resolver or claim that unstemmed words equal spec-3 keys.
    public static func tagWeights(_ tags: [String], titleWords: [String], descriptionWords: [String],
                                  snapshot: NeuroDocumentFrequency,
                                  chunk: (String) throws -> NeuroTitleChunks,
                                  resolveDomain: (String, [String]) -> String) rethrows -> [String: Double] {
        let candidates = Array(tags.prefix(15))
        let verification = Set(titleWords + descriptionWords)
        let context = candidates.flatMap { tag in
            NeuroTitleChunker.fold(tag).split(whereSeparator: { $0.isWhitespace }).map {
                $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            }.filter { $0.utf16.count > 1 }
        } + titleWords + descriptionWords
        var result: [String: Double] = [:]
        let neverAlone: Set<String> = ["pro", "max", "ultra", "plus", "mini"]
        for tag in candidates {
            let cleaned = NeuroTitleChunker.fold(tag).trimmingCharacters(in: .whitespacesAndNewlines)
            guard validKey(cleaned), cleaned.utf16.count >= 3 || shortTopics.contains(cleaned),
                  !NeuroMetadataLexicon.tagSpam.contains(cleaned), !NeuroMetadataLexicon.stopWords.contains(cleaned) else { continue }
            if cleaned.range(of: "^20[2-9][0-9]$", options: .regularExpression) != nil { continue }
            let parsed = try chunk(cleaned)
            let tokens = parsed.words
            guard !tokens.isEmpty else { continue }
            let base = tokens.contains(where: { verification.contains($0) }) ? 0.65 : 0.10
            let phrases = parsed.chunks.filter {
                $0.count >= 2 && $0.reduce(0) { $0 + $1.split(separator: " ").count } <= 3
            }.map { $0.joined(separator: " ") }.filter(validKey)
            for phrase in phrases {
                result[phrase, default: 0] += NeuroContentFeatures.idfWeight(for: phrase, baseWeight: base, snapshot: snapshot)
            }
            for token in tokens where !neverAlone.contains(token) {
                let resolved = resolveDomain(token, context)
                guard validKey(resolved) else { continue }
                result[resolved, default: 0] += NeuroContentFeatures.idfWeight(for: resolved,
                    baseWeight: phrases.isEmpty ? base : base * 0.5, snapshot: snapshot)
            }
        }
        return result
    }
    private static func validKey(_ key: String) -> Bool { !key.isEmpty && key.utf16.count <= 40 }
}
