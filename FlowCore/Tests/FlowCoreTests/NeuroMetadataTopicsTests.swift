// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client metadata processing fixtures, https://github.com/Flow-Tube/Flow.
import XCTest
@testable import FlowCore

final class NeuroMetadataTopicsTests: XCTestCase {
    private let empty = NeuroDocumentFrequency(totalDocuments: 0, frequencies: [:])
    func testHashtagsLimitsDeduplicationAndCreatorOrder() {
        XCTAssertEqual(NeuroMetadataTopics.topicTags(creatorTags: ["guitar", "guitar"], description: nil), ["guitar", "guitar"])
        XCTAssertEqual(NeuroMetadataTopics.topicTags(creatorTags: ["guitar"], description: "#guitar #bass_guitar #piano #music #lesson #ignored"),
                       ["guitar", "bass guitar", "piano", "music", "lesson"])
    }
    func testDescriptionRemovesPromotionalAndShoutedLines() {
        let source = "Guitar techniques explained slowly.\nUse code SAVE for a discount today\nVisit https://example.com today\n#hashtags only on this line\nSUBSCRIBE TO MY CHANNEL\nPiano harmonies explained carefully."
        XCTAssertEqual(NeuroMetadataTopics.descriptionContent(source), "Guitar techniques explained slowly. Piano harmonies explained carefully.")
        XCTAssertEqual(NeuroMetadataTopics.descriptionContent("short"), "")
        XCTAssertFalse(NeuroMetadataTopics.descriptionContent("【MV】周杰倫最新歌曲完整版音樂欣賞播放").isEmpty)
    }
    func testDescriptionTokenLimitAndRepeatedWordWeights() throws {
        let weights = try NeuroMetadataTopics.descriptionWeights("Guitar techniques explained slowly.", snapshot: empty) { _ in Array(repeating: "guitar", count: 20) }
        XCTAssertEqual(weights["guitar"]!, 3, accuracy: 1e-12)
    }
    func testVerifiedPhraseAndUnverifiedWordWeights() throws {
        let weights = try NeuroMetadataTopics.tagWeights(["guitar lesson", "piano"], titleWords: ["guitar"], descriptionWords: [], snapshot: empty,
            chunk: { try NeuroTitleChunker.extract($0) }, resolveDomain: { word, _ in word })
        XCTAssertEqual(weights["guitar lesson"], 0.65)
        XCTAssertEqual(weights["guitar"], 0.325)
        XCTAssertEqual(weights["lesson"], 0.325)
        XCTAssertEqual(weights["piano"], 0.1)
    }
    func testSpamYearsIngestionAndDomainResolver() throws {
        var contextSeen: [String] = []
        let weights = try NeuroMetadataTopics.tagWeights(["viral", "2026", "bass"], titleWords: ["guitar"], descriptionWords: ["music"], snapshot: empty,
            chunk: { try NeuroTitleChunker.extract($0) }, resolveDomain: { word, context in contextSeen = context; return word + ":music" })
        XCTAssertEqual(weights, ["bass:music": 0.1])
        XCTAssertTrue(contextSeen.contains("guitar")); XCTAssertTrue(contextSeen.contains("music"))
        let limited = try NeuroMetadataTopics.tagWeights(Array(repeating: "viral", count: 15) + ["guitar"], titleWords: [], descriptionWords: [], snapshot: empty,
            chunk: { try NeuroTitleChunker.extract($0) }, resolveDomain: { word, _ in word })
        XCTAssertTrue(limited.isEmpty)
    }
    func testUnsupportedSegmentationErrorsPropagate() {
        XCTAssertThrowsError(try NeuroMetadataTopics.tagWeights(["中文教程"], titleWords: [], descriptionWords: [], snapshot: empty,
            chunk: { try NeuroTitleChunker.extract($0) }, resolveDomain: { word, _ in word }))
    }
}
