// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Flow Android Client, Copyright (C) 2025-2026 Flow | A-EDev.
// https://github.com/Flow-Tube/Flow at 3f3e2a6101fe511003f8b694876fe8c6ece89c66.
import Foundation

/// Candidate extraction, not final learned topic keys. Stemming/promotion are separate stages.
public struct NeuroTitleChunks: Equatable, Sendable {
    public let chunks: [[String]]
    public let modelPairs: [String]
    public let formats: Set<String>
    public var words: [String] { chunks.flatMap { $0 } }
    public var standaloneCandidates: Set<String> {
        Set(words.filter { !["pro", "max", "ultra", "plus", "mini"].contains($0) && $0.utf16.count <= 40 })
    }
    /// Only adjacent runs inside a chunk; never invent a phrase across a removed stop word.
    public var runCandidates: [String] {
        var result: [String] = []
        for chunk in chunks {
            for start in chunk.indices {
                var count = chunk[start].split(separator: " ").count
                guard start + 1 < chunk.count else { continue }
                for end in (start + 1)..<chunk.count {
                    count += chunk[end].split(separator: " ").count
                    if count > 3 { break }
                    let key = chunk[start...end].joined(separator: " ")
                    if key.utf16.count <= 40 { result.append(key) }
                }
            }
        }
        return result
    }
}

public enum NeuroTitleChunker {
    public enum ExtractionError: Error, Equatable { case dictionarySegmentationRequired, titleTooLong }
    public static var englishStopWords: Set<String> { NeuroChunkLexicon.englishStopWords }
    private enum Item { case word(String, Bool), boundary }
    private static let shortTopics: Set<String> = ["ai", "ml", "2d", "3d", "4k", "8k", "f1", "pc", "tv", "vr", "ar", "dj", "ui", "ux", "ev", "rc", "uk"]
    private static let smallCaps = Dictionary(uniqueKeysWithValues: zip(Array("ᴀʙᴄᴅᴇꜰɢʜɪᴊᴋʟᴍɴᴏᴘꞯʀꜱᴛᴜᴠᴡʏᴢ"), Array("abcdefghijklmnopqrstuvwyz")))

    public static func fold(_ text: String) -> String {
        var marks = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x2019, 0x2018, 0x02BC, 0x60, 0xB4: marks.append("'")
            case 0x130: marks.append("i")
            case 0x2010, 0x2011: marks.append("-")
            case 0xFE0F, 0x200D: break
            default: marks.unicodeScalars.append(scalar)
            }
        }
        return String(marks.precomposedStringWithCompatibilityMapping.map { smallCaps[$0] ?? $0 }).lowercased()
    }

    /// Defaults to the upstream English stop list. Other spaced-language callers must supply
    /// their language stop set. No stemming/lemmatization or language inference is claimed.
    public static func extract(_ title: String, stopWords: Set<String>? = nil) throws -> NeuroTitleChunks {
        guard title.utf16.count <= 16_384 else { throw ExtractionError.titleTooLong }
        let folded = fold(title)
        guard !folded.unicodeScalars.contains(where: needsDictionary) else {
            throw ExtractionError.dictionarySegmentationRequired
        }
        let stops = stopWords ?? englishStopWords
        var items: [Item] = []
        for piece in folded.split(whereSeparator: { $0.isWhitespace }) { split(String(piece), into: &items) }
        items = mergeExpressions(items)
        var chunks: [[String]] = [], current: [String] = [], models: [String] = []
        var formats: Set<String> = []
        func close() { if !current.isEmpty { chunks.append(current) }; current = [] }
        for item in items {
            guard case let .word(word, whole) = item else { close(); continue }
            if let format = NeuroFormats.format(of: word) { formats.insert(format); close(); continue }
            if whole { current.append(word); continue }
            if !word.isEmpty && word.allSatisfy({ $0.isNumber || $0 == "." }) {
                let year = word.count == 4 && (word.hasPrefix("19") || word.hasPrefix("20")) && word.allSatisfy(\.isNumber)
                if !year, let previous = current.last {
                    let candidate = previous + " " + word
                    if candidate.utf16.count <= 40 { models.append(candidate) }
                }
                close(); continue
            }
            guard (word.utf16.count >= 3 || shortTopics.contains(word)), !stops.contains(word) else { close(); continue }
            current.append(word)
        }
        close()
        return NeuroTitleChunks(chunks: chunks, modelPairs: models, formats: formats)
    }

    private static func needsDictionary(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0E00...0x0EFF, 0x1000...0x109F, 0x1780...0x17FF, 0x2E80...0x2FFF,
             0x3040...0x31FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA9E0...0xA9FF,
             0xAA60...0xAA7F, 0xF900...0xFAFF, 0xFF66...0xFF9F, 0x20000...0x323AF: return true
        default: return false
        }
    }
    private static func wordCharacter(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || CharacterSet.nonBaseCharacters.contains($0) }
    }
    private static func split(_ piece: String, into items: inout [Item]) {
        if piece == "&" { items.append(.word(piece, false)); return }
        let chars = Array(piece)
        var word = ""
        func flush() { if !word.isEmpty { shape(word, into: &items) }; word = "" }
        for i in chars.indices {
            let c = chars[i], next = i + 1 < chars.count ? chars[i + 1] : nil
            if wordCharacter(c) { word.append(c) }
            else if c == "'" { if !word.isEmpty { word.append(c) } }
            else if "-.&".contains(c), !word.isEmpty, let next, wordCharacter(next) { word.append(c) }
            else if c == ".", next == nil, word.contains(".") { continue }
            else if "+#".contains(c), !word.isEmpty {
                var end = i
                while end < chars.count && "+#".contains(chars[end]) { end += 1 }
                if NeuroChunkLexicon.keepWhole.contains(word + String(chars[i..<end])) { word.append(c) }
                else { flush(); items.append(.boundary) }
            } else { flush(); items.append(.boundary) }
        }
        flush()
    }
    private static func shape(_ raw: String, into items: inout [Item]) {
        if NeuroChunkLexicon.keepWhole.contains(raw) { items.append(.word(raw, true)); return }
        if let expression = NeuroChunkLexicon.expressions[raw] { items.append(.word(expression, true)); return }
        if NeuroChunkLexicon.contractions.contains(raw) { items.append(.boundary); return }
        var word = raw
        if let elision = NeuroChunkLexicon.elisions.first(where: { raw.hasPrefix($0) && raw.count > $0.count }) {
            word = String(raw.dropFirst(elision.count))
        }
        if word.hasSuffix("'s") { word = String(word.dropLast(2)) }
        else if word.hasSuffix("'") { word.removeLast() }
        word = word.replacingOccurrences(of: "'", with: "")
        if let expression = NeuroChunkLexicon.expressions[word] { items.append(.word(expression, true)); return }
        if word.contains("-") {
            let parts = word.split(separator: "-").map(String.init)
            if parts.contains(where: { $0.utf16.count <= 2 }) { items.append(.word(parts.joined(), false)) }
            else { items += parts.map { .word($0, false) } }
        } else if word.contains("."), !word.allSatisfy({ $0.isNumber || $0 == "." }) {
            items += word.split(separator: ".").map { .word(String($0), false) }
        } else { items.append(.word(word, false)) }
    }
    private static func mergeExpressions(_ items: [Item]) -> [Item] {
        let longest = NeuroChunkLexicon.expressions.keys.map { $0.split(separator: " ").count }.max() ?? 1
        var result: [Item] = [], index = 0
        while index < items.count {
            var found = false
            if min(longest, items.count - index) >= 2 {
                for count in stride(from: min(longest, items.count - index), through: 2, by: -1) {
                    let words = items[index..<(index + count)].compactMap { item -> String? in
                        if case let .word(text, false) = item { return text }; return nil
                    }
                    if words.count == count, let expression = NeuroChunkLexicon.expressions[words.joined(separator: " ")] {
                        result.append(.word(expression, true)); index += count; found = true; break
                    }
                }
            }
            if !found { result.append(items[index]); index += 1 }
        }
        return result
    }
}
