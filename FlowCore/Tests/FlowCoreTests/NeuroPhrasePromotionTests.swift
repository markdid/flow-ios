// SPDX-License-Identifier: GPL-3.0-only
// Tests for Flow Android Client phrase promotion, https://github.com/Flow-Tube/Flow.
import XCTest
@testable import FlowCore

final class NeuroPhrasePromotionTests: XCTestCase {
    func testStrongAssociationAndClaimedWordCounts() {
        let snapshot = NeuroDocumentFrequency(totalDocuments: 10, frequencies: ["guitar lesson": 3])
        XCTAssertEqual(NeuroPhrasePromotion.npmi("guitar lesson", in: snapshot)!, 1, accuracy: 1e-12)
        XCTAssertTrue(NeuroPhrasePromotion.isPhrase("guitar lesson", in: snapshot))
        let ubiquitous = NeuroDocumentFrequency(totalDocuments: 10, frequencies: ["guitar lesson": 10])
        XCTAssertEqual(NeuroPhrasePromotion.npmi("guitar lesson", in: ubiquitous), 1)
    }
    func testWeakAssociationWarmupAndMinimumCount() {
        let weak = NeuroDocumentFrequency(totalDocuments: 100, frequencies: ["guitar": 60, "lesson": 50, "guitar lesson": 30])
        XCTAssertEqual(NeuroPhrasePromotion.npmi("guitar lesson", in: weak)!, 0, accuracy: 1e-12)
        XCTAssertFalse(NeuroPhrasePromotion.isPhrase("guitar lesson", in: weak))
        XCTAssertFalse(NeuroPhrasePromotion.isPhrase("guitar lesson", in: .init(totalDocuments: 9, frequencies: ["guitar lesson": 9])))
        XCTAssertFalse(NeuroPhrasePromotion.isPhrase("guitar lesson", in: .init(totalDocuments: 10, frequencies: ["guitar lesson": 2])))
    }
    func testMalformedAndMissingCountsNeverYieldNonfiniteScores() {
        let safe = NeuroDocumentFrequency(totalDocuments: 10, frequencies: ["bad": -1, "zero pair": 0, "huge pair": Int.max])
        XCTAssertNil(NeuroPhrasePromotion.npmi("bad", in: safe))
        XCTAssertNil(NeuroPhrasePromotion.npmi("zero pair", in: safe))
        XCTAssertNil(NeuroPhrasePromotion.npmi("missing pair", in: safe))
        XCTAssertEqual(NeuroPhrasePromotion.npmi("huge pair", in: safe), 1)
        XCTAssertEqual(NeuroDocumentFrequency(totalDocuments: -1, frequencies: ["x": 10]).frequencies, [:])
    }
    func testMergedRunRarestCharacterRule() {
        XCTAssertTrue(NeuroPhrasePromotion.isMergedRun("相机", in: .init(totalDocuments: 20, frequencies: ["相机": 3, "相": 6, "机": 10])))
        XCTAssertFalse(NeuroPhrasePromotion.isMergedRun("相机", in: .init(totalDocuments: 20, frequencies: ["相机": 3, "相": 7, "机": 10])))
        XCTAssertFalse(NeuroPhrasePromotion.isMergedRun("相机", in: .init(totalDocuments: 20, frequencies: ["相机": 3])))
    }
    func testPromotionClaimsOnlyMatchingPositions() throws {
        let title = try NeuroTitleChunker.extract("guitar lesson and guitar piano")
        let chosen = NeuroPhrasePromotion.select(from: title, in: .init(totalDocuments: 10, frequencies: ["guitar lesson": 3]))
        XCTAssertEqual(chosen.phrases, ["guitar lesson"])
        XCTAssertEqual(chosen.unclaimedWords, ["guitar", "piano"])
        XCTAssertFalse(chosen.topics.contains("lesson"))
    }
    func testTagAndCatalogPromotionWithoutStatisticalWarmup() throws {
        let title = try NeuroTitleChunker.extract("pixel pro camera")
        let empty = NeuroDocumentFrequency(totalDocuments: 0, frequencies: [:])
        XCTAssertEqual(NeuroPhrasePromotion.select(from: title, in: empty).topics, ["pixel", "camera"])
        let tag = NeuroPhrasePromotion.select(from: title, in: empty, tagPhrases: ["pixel pro camera"])
        XCTAssertEqual(tag.topics, ["pixel pro camera"])
        let catalog = NeuroPhrasePromotion.select(from: title, in: empty, catalogPhrases: ["pixel pro"])
        XCTAssertEqual(catalog.topics, ["pixel pro", "camera"])
    }
    func testTrigramsDoNotReceiveStatisticalPromotionAndDocumentsDeduplicate() throws {
        let title = try NeuroTitleChunker.extract("alpha beta gamma and alpha")
        let snapshot = NeuroDocumentFrequency(totalDocuments: 10, frequencies: ["alpha beta gamma": 5])
        XCTAssertTrue(NeuroPhrasePromotion.select(from: title, in: snapshot).phrases.isEmpty)
        let terms = NeuroPhrasePromotion.documentTerms(title: title, learnedKeys: ["extra"])
        XCTAssertEqual(terms.filter { $0 == "alpha" }.count, 1)
        XCTAssertTrue(terms.contains("alpha beta gamma"))
        XCTAssertTrue(terms.contains("extra"))
    }
}
