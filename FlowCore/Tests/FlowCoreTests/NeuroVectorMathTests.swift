// SPDX-License-Identifier: GPL-3.0-only
// Fixtures for math adapted from Flow Android Client (https://github.com/Flow-Tube/Flow).
import Foundation
import XCTest
@testable import FlowCore

final class NeuroVectorMathTests: XCTestCase {
    func testIdenticalAndUnrelatedVectors() {
        let guitar = NeuroContentVector(topics: ["guitar": 1])
        XCTAssertEqual(NeuroVectorMath.similarity(guitar, guitar), 1, accuracy: 1e-12)
        let unrelated = NeuroContentVector(topics: ["cooking": 1])
        XCTAssertEqual(NeuroVectorMath.similarity(guitar, unrelated), 0.09, accuracy: 1e-12)
        XCTAssertEqual(NeuroVectorMath.topicSimilarity(guitar, unrelated), 0)
    }
    func testTaggedMigrationAndSpecificity() {
        let old = NeuroContentVector(topics: ["guitar": 1])
        let new = NeuroContentVector(topics: ["guitar:music": 1])
        XCTAssertEqual(NeuroVectorMath.similarity(old, new), 0.51, accuracy: 1e-12)
        XCTAssertEqual(NeuroVectorMath.topicSimilarity(old, new), 0.3, accuracy: 1e-12)
        XCTAssertEqual(NeuroVectorMath.topicSimilarity(old, old, specificity: { _ in 0.5 }), 0.25, accuracy: 1e-12)
    }
    func testFullWatchEvidenceAndRecentHorizon() {
        let blank = NeuroContentVector()
        let video = NeuroContentVector(topics: ["guitar": 1])
        let long = NeuroVectorMath.learn(blank, from: video, strength: 1, horizon: .longTerm, scalarRate: 0.15)
        let recent = NeuroVectorMath.learn(blank, from: video, strength: 1, horizon: .recent, scalarRate: 0.15)
        XCTAssertEqual(long.topics["guitar"]!, 1 - exp(-1.0 / 30), accuracy: 1e-12)
        XCTAssertEqual(recent.topics["guitar"]!, 1 - exp(-1.0 / 3), accuracy: 1e-12)
        XCTAssertGreaterThan(recent.topics["guitar"]!, long.topics["guitar"]!)
        XCTAssertEqual(NeuroVectorMath.learn(long, from: video, strength: 0, horizon: .longTerm, scalarRate: 1), long)
    }
    func testBlendPreservesScalars() {
        let long = NeuroContentVector(topics: ["guitar": 1], duration: 0.9)
        let recent = NeuroContentVector(topics: ["cooking": 1], duration: 0.1)
        let blended = NeuroVectorMath.blend(longTerm: long, recent: recent)
        XCTAssertEqual(blended.topics["guitar"]!, 0.75, accuracy: 1e-12)
        XCTAssertEqual(blended.topics["cooking"]!, 0.25, accuracy: 1e-12)
        XCTAssertEqual(blended.duration, 0.9)
        XCTAssertEqual(NeuroVectorMath.blend(longTerm: long, recent: NeuroContentVector()), long)
    }
    func testCapAndProtectedBaseKeys() {
        let vector = NeuroContentVector(topics: ["a": 0.9, "b": 0.8, "c:music": 0.1])
        XCTAssertEqual(Set(NeuroVectorMath.capTopics(vector, maximum: 1).topics.keys), ["a"])
        XCTAssertEqual(Set(NeuroVectorMath.capTopics(vector, maximum: 1, protected: ["c"]).topics.keys), ["a", "c:music"])
    }
    func testInvalidNumbersAndTitleSimilarity() {
        let vector = NeuroContentVector(topics: ["bad": .nan, "negative": -1, "valid": 2], duration: .infinity)
        XCTAssertEqual(vector.topics, ["valid": 1])
        XCTAssertEqual(vector.duration, 0)
        XCTAssertEqual(NeuroVectorMath.titleSimilarity(["guitar", "lesson"], ["guitar", "review"]), 1.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(NeuroVectorMath.titleSimilarity([], []), 0)
    }
    func testPhraseAbsorbsWeakWord() {
        let old = NeuroContentVector(topics: ["camera": 0.01, "camera test": 0.8])
        let learned = NeuroVectorMath.learn(old, from: NeuroContentVector(), strength: 1, horizon: .longTerm, scalarRate: 0)
        XCTAssertNil(learned.topics["camera"])
        XCTAssertNotNil(learned.topics["camera test"])
        let protected = NeuroVectorMath.learn(old, from: NeuroContentVector(), strength: 1, horizon: .longTerm, scalarRate: 0, protected: ["camera"])
        XCTAssertNotNil(protected.topics["camera"])
    }
    func testPreparedLookupMatchesBothVectorSizeDirections() {
        let user = NeuroContentVector(topics: ["guitar:z": 0.9, "guitar:a": 0.2, "cooking": 0.4])
        let prepared = NeuroVectorMath.PreparedVector(user)
        for content in [NeuroContentVector(topics: ["guitar": 1]),
                        NeuroContentVector(topics: ["guitar": 1, "cooking": 0.5, "other": 0.2, "extra": 0.1])] {
            XCTAssertEqual(NeuroVectorMath.similarity(prepared, content),
                           NeuroVectorMath.similarity(user, content), accuracy: 1e-12)
            XCTAssertEqual(NeuroVectorMath.topicSimilarity(prepared, content),
                           NeuroVectorMath.topicSimilarity(user, content), accuracy: 1e-12)
        }
        // Ambiguous tagged aliases choose guitar:a (0.2), not guitar:z (0.9).
        XCTAssertEqual(NeuroVectorMath.topicSimilarity(prepared, NeuroContentVector(topics: ["guitar": 1])),
                       0.06 / sqrt(1.01), accuracy: 1e-12)
    }
    func testMigrationAliasesCanProduceTopicSimilarityAboveOne() {
        let user = NeuroContentVector(topics: ["guitar": 1])
        let content = NeuroContentVector(topics: ["guitar": 1, "guitar:music": 0.3])
        let expected = sqrt(1.09)
        let prepared = NeuroVectorMath.PreparedVector(user)
        XCTAssertGreaterThan(expected, 1)
        XCTAssertEqual(NeuroVectorMath.topicSimilarity(user, content), expected, accuracy: 1e-12)
        XCTAssertEqual(NeuroVectorMath.topicSimilarity(prepared, content), expected, accuracy: 1e-12)
    }

}
