// SPDX-License-Identifier: GPL-3.0-only
// Selected unchanged expectations from Flow Android Client key_spec_golden.json plus boundary tests.
import XCTest
@testable import FlowCore

final class NeuroTitleChunksTests: XCTestCase {
    func testUpstreamGoldenCasesThatDoNotRequireStemming() throws {
        let cases: [(String, [[String]], Set<String>)] = [
            ("Guitar Playalong - Hotel California", [["guitar"], ["hotel", "california"]], ["playalong"]),
            ("Lo-Fi Hip Hop Radio", [["lofi", "hip hop", "radio"]], []),
            ("Lo Fi Hip-Hop Mix", [["lofi", "hip hop", "mix"]], []),
            ("stand up comedy", [["standup", "comedy"]], []),
            ("Drum & Bass mix", [["drum and bass", "mix"]], []),
            ("drum n bass mix", [["drum and bass", "mix"]], []),
            ("Rock 'n' Roll history", [["rock and roll", "history"]], []),
            ("GPT-4 explained", [["gpt4"]], ["explainer"]),
            ("𝙋𝙃𝙊𝙉𝙆 𝙈𝙄𝙓", [["phonk", "mix"]], []),
            ("ｐｈｏｎｋ ｍｉｘ", [["phonk", "mix"]], []),
            ("ᴘʜᴏɴᴋ ᴍɪx", [["phonk", "mix"]], []),
            ("İSTANBUL GEZİSİ", [["istanbul", "gezisi"]], []),
            ("L'amour d'été", [["amour", "été"]], [])
        ]
        for (title, chunks, formats) in cases {
            let result = try NeuroTitleChunker.extract(title)
            XCTAssertEqual(result.chunks, chunks, title)
            XCTAssertEqual(result.formats, formats, title)
            XCTAssertEqual(result.modelPairs, [], title)
        }
    }
    func testBoundariesNeverInventCrossStopWordPhrases() throws {
        let result = try NeuroTitleChunker.extract("Big Tech’s Privacy Promises Are Lies")
        XCTAssertEqual(result.chunks, [["big", "tech", "privacy", "promises"], ["lies"]])
        XCTAssertFalse(result.runCandidates.contains("promises lies"))
        XCTAssertTrue(result.runCandidates.contains("tech privacy promises"))
        XCTAssertFalse(result.runCandidates.contains("big tech privacy promises"))
    }
    func testModelsYearsFormatsAndNeverAlone() throws {
        let result = try NeuroTitleChunker.extract("Pixel 10 Pro review 2026 Python 3.12")
        XCTAssertEqual(result.modelPairs, ["pixel 10", "python 3.12"])
        XCTAssertEqual(result.chunks, [["pixel"], ["pro"], ["python"]])
        XCTAssertEqual(result.formats, ["review"])
        XCTAssertFalse(result.standaloneCandidates.contains("pro"))
        XCTAssertTrue(try NeuroTitleChunker.extract("pixel pro").runCandidates.contains("pixel pro"))
    }
    func testPunctuationKeepsTechnicalNamesAndSplitsOtherDots() throws {
        XCTAssertEqual(try NeuroTitleChunker.extract("C++ tutorial node.js C# F#").chunks,
                       [["c++"], ["node.js", "c#", "f#"]])
        XCTAssertEqual(try NeuroTitleChunker.extract("alpha.beta spider-man").chunks,
                       [["alpha", "beta", "spider", "man"]])
        XCTAssertEqual(try NeuroTitleChunker.extract("alpha | beta").chunks, [["alpha"], ["beta"]])
    }
    func testDictionaryScriptsAndOverlongInputAreExplicitlyUnsupported() {
        for title in ["中文教程", "日本語かな", "ภาษาไทย", "မြန်မာ"] {
            XCTAssertThrowsError(try NeuroTitleChunker.extract(title)) {
                XCTAssertEqual($0 as? NeuroTitleChunker.ExtractionError, .dictionarySegmentationRequired)
            }
        }
        XCTAssertThrowsError(try NeuroTitleChunker.extract(String(repeating: "a", count: 16_385)))
    }
    func testCustomStopWordsEmptyTextAndCandidateLimits() throws {
        XCTAssertEqual(try NeuroTitleChunker.extract("guitar custom piano", stopWords: ["custom"]).chunks,
                       [["guitar"], ["piano"]])
        XCTAssertEqual(try NeuroTitleChunker.extract("").chunks, [])
        XCTAssertEqual(try NeuroTitleChunker.extract("drum and bass mix").runCandidates, []) // Four words.
        XCTAssertTrue(try NeuroTitleChunker.extract(String(repeating: "a", count: 41)).standaloneCandidates.isEmpty)
    }
    func testModelPairsRespectFinalUTF16KeyLimit() throws {
        let exact = String(repeating: "a", count: 37) + " 10"
        XCTAssertEqual(try NeuroTitleChunker.extract(exact).modelPairs, [exact])
        XCTAssertEqual(try NeuroTitleChunker.extract(String(repeating: "a", count: 38) + " 10").modelPairs, [])
        // Supplementary letters occupy two UTF-16 units each, not one Character.
        let supplementary = String(repeating: "𐐨", count: 19)
        XCTAssertEqual(supplementary.utf16.count, 38)
        XCTAssertEqual(try NeuroTitleChunker.extract(supplementary + " 1").modelPairs, [supplementary + " 1"])
        XCTAssertEqual(try NeuroTitleChunker.extract(supplementary + " 10").modelPairs, [])
        XCTAssertEqual(try NeuroTitleChunker.extract("pixel " + String(repeating: "1", count: 35)).modelPairs, [])
    }

}
