// SPDX-License-Identifier: GPL-3.0-only
// Tests for preferences adapted from Flow Android Client, https://github.com/Flow-Tube/Flow.
import XCTest
@testable import FlowCore

final class NeuroPreferencesTests: XCTestCase {
    func testMultilingualFormatLookup() {
        XCTAssertEqual(NeuroFormats.surfaces.count, 21)
        for (format, words) in NeuroFormats.surfaces {
            for word in words { XCTAssertEqual(NeuroFormats.format(of: word), format) }
            XCTAssertEqual(NeuroFormats.searchWord(for: format), words.first)
        }
        XCTAssertEqual(NeuroFormats.format(of: "评测"), "review")
        XCTAssertEqual(NeuroFormats.format(of: "réaction"), "reaction")
        XCTAssertEqual(NeuroFormats.format(of: "tier list"), "tier list")
        XCTAssertNil(NeuroFormats.format(of: "REVIEW")) // Folding belongs to tokenizer.
        XCTAssertNil(NeuroFormats.format(of: "guitar"))
        XCTAssertEqual(NeuroFormats.searchWord(for: "custom"), "custom")
    }
    func testFormatLearningFadePruningAndNoOp() {
        let initial = ["review": 0.5, "tutorial": 0.4, "vlog": 0.01]
        XCTAssertEqual(NeuroFormats.learn(initial, formats: []), initial)
        let result = NeuroFormats.learn(initial, formats: ["review", "podcast"])
        XCTAssertEqual(result["review"]!, 0.55, accuracy: 1e-12)
        XCTAssertEqual(result["tutorial"]!, 0.396, accuracy: 1e-12)
        XCTAssertEqual(result["podcast"], 0.1)
        XCTAssertNil(result["vlog"])
        XCTAssertEqual(NeuroFormats.scoreTerm(result, formats: ["review", "podcast"]), 0.022, accuracy: 1e-12)
        XCTAssertEqual(NeuroFormats.scoreTerm(result, formats: []), 0)
    }
    func testCategoryNamesAndThemes() {
        XCTAssertEqual(NeuroCategories.id(for: "  Science & Technology\n"), "science")
        XCTAssertNil(NeuroCategories.id(for: nil))
        XCTAssertNil(NeuroCategories.id(for: "science"))
        XCTAssertTrue(NeuroCategories.isTheme("music"))
        XCTAssertFalse(NeuroCategories.isTheme("people"))
        XCTAssertFalse(NeuroCategories.isTheme("entertainment"))
        XCTAssertFalse(NeuroCategories.isTheme("unknown"))
    }
    func testCategoryLearningHalvesOnlyAfterThreshold() {
        XCTAssertEqual(NeuroCategories.learn(["music": 399], category: "music"), ["music": 400])
        XCTAssertEqual(NeuroCategories.learn(["music": 400], category: "gaming"), ["music": 200, "gaming": 0.5])
    }
    func testCategoryPenaltyWarmupConfidenceAndFamiliarity() {
        let foreign = NeuroChannelCategory(id: "gaming", confidence: 1)
        XCTAssertEqual(NeuroCategories.factor(["music": 19], category: foreign), 1)
        XCTAssertEqual(NeuroCategories.factor(["music": 20], category: foreign), 0.65, accuracy: 1e-12)
        XCTAssertEqual(NeuroCategories.factor(["music": 18, "gaming": 2], category: foreign), 1)
        XCTAssertEqual(NeuroCategories.factor(["music": 20], category: .init(id: "people", confidence: 1)), 0.895, accuracy: 1e-12)
        XCTAssertEqual(NeuroCategories.factor(["music": 20], category: .init(id: "gaming", confidence: 0.5)), 0.825, accuracy: 1e-12)
        XCTAssertEqual(NeuroCategories.factor(["music": 20], category: .init(id: "gaming", confidence: .nan)), 1)
    }
    func testClusterCategoryRequiresWeightedMajority() {
        let profiles = ["a": ["guitar": 0.6], "b": ["guitar": 0.4], "c": ["unrelated": 1.0]]
        let categories = ["a": NeuroChannelCategory(id: "music", confidence: 1),
                          "b": NeuroChannelCategory(id: "education", confidence: 1)]
        XCTAssertEqual(NeuroCategories.clusterCategory(topics: ["guitar"], channelTopicProfiles: profiles) { categories[$0] }, "music")
        XCTAssertNil(NeuroCategories.clusterCategory(topics: ["unknown"], channelTopicProfiles: profiles) { categories[$0] })
        let tied = ["a": ["guitar": 0.5], "b": ["guitar": 0.5]]
        XCTAssertNil(NeuroCategories.clusterCategory(topics: ["guitar"], channelTopicProfiles: tied) { categories[$0] })
    }
    func testMalformedFormatWeightsStayBoundedEvenWithoutLearning() {
        let malformed: [String: Double] = ["review": .nan, "tutorial": .infinity,
                                           "podcast": -1, "vlog": 3]
        XCTAssertEqual(NeuroFormats.learn(malformed, formats: []), ["vlog": 1])
        XCTAssertEqual(NeuroFormats.scoreTerm(malformed, formats: Set(malformed.keys)), 0.04)
        XCTAssertEqual(NeuroFormats.scoreTerm(malformed, formats: ["review", "tutorial", "podcast"]), 0)
        let learned = NeuroFormats.learn(malformed, formats: ["review"])
        XCTAssertEqual(learned["review"], 0.1)
        XCTAssertEqual(learned["vlog"], 0.99)
    }
    func testMalformedCategoryCountsStayFiniteAndBounded() {
        let malformed: [String: Double] = ["music": .greatestFiniteMagnitude, "gaming": .nan,
                                           "science": .infinity, "people": -10]
        XCTAssertEqual(NeuroCategories.learn(malformed, category: "gaming"), ["music": 200, "gaming": 0.5])
        let known = NeuroCategories.factor(malformed, category: .init(id: "music", confidence: 1))
        let foreign = NeuroCategories.factor(malformed, category: .init(id: "gaming", confidence: 1))
        XCTAssertEqual(known, 1)
        XCTAssertEqual(foreign, 0.65, accuracy: 1e-12)
        XCTAssertEqual(NeuroCategories.factor(["music": .nan], category: .init(id: "gaming", confidence: 1)), 1)
    }
    func testMalformedClusterProfilesDoNotPoisonVotes() {
        let profiles: [String: [String: Double]] = ["good": ["guitar": 1],
            "nan": ["guitar": .nan], "infinite": ["guitar": .infinity], "negative": ["guitar": -1]]
        XCTAssertEqual(NeuroCategories.clusterCategory(topics: ["guitar"], channelTopicProfiles: profiles) {
            .init(id: $0 == "good" ? "music" : "gaming", confidence: 1)
        }, "music")
        XCTAssertNil(NeuroCategories.clusterCategory(topics: ["guitar"], channelTopicProfiles: ["bad": ["guitar": .nan]]) {
            _ in .init(id: "music", confidence: 1)
        })
    }

}
