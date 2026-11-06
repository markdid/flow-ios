// SPDX-License-Identifier: GPL-3.0-only
// Tests for Flow Android Client feature math, https://github.com/Flow-Tube/Flow.
import Foundation
import XCTest
@testable import FlowCore

final class NeuroContentFeaturesTests: XCTestCase {
    func testIDFWarmupUnknownKeysAndCommonWordFloor() {
        XCTAssertEqual(NeuroContentFeatures.idfWeight(for: "guitar", source: .phrase,
            snapshot: .init(totalDocuments: 29, frequencies: ["guitar": 29])), 1.2)
        let snapshot = NeuroDocumentFrequency(totalDocuments: 1000, frequencies: ["common": 1000])
        XCTAssertEqual(NeuroContentFeatures.idfWeight(for: "new", source: .title, snapshot: snapshot), 0.5)
        XCTAssertEqual(NeuroContentFeatures.idfWeight(for: "common", source: .title, snapshot: snapshot), 0.075, accuracy: 1e-12)
        let boundary = NeuroDocumentFrequency(totalDocuments: 30, frequencies: ["guitar": 3])
        XCTAssertEqual(NeuroContentFeatures.idfWeight(for: "guitar", source: .channel, snapshot: boundary),
                       0.6 * log1p(30.0 / 4) / log1p(30), accuracy: 1e-12)
        XCTAssertEqual(NeuroContentFeatures.idfWeight(for: "guitar", baseWeight: .nan, snapshot: boundary), 0)
    }
    func testNormalizationIsStableAndRejectsCorruptInputs() {
        let result = NeuroContentFeatures.normalizedTopics(["alpha": 3, "beta": 4, "bad": .nan, "negative": -1])
        XCTAssertEqual(result["alpha"]!, 0.6, accuracy: 1e-12)
        XCTAssertEqual(result["beta"]!, 0.8, accuracy: 1e-12)
        XCTAssertEqual(result.count, 2)
        let huge = NeuroContentFeatures.normalizedTopics(["alpha": .greatestFiniteMagnitude, "beta": .greatestFiniteMagnitude])
        XCTAssertEqual(huge["alpha"]!, 1 / sqrt(2), accuracy: 1e-12)
        XCTAssertEqual(NeuroContentFeatures.normalizedTopics(["": 1, String(repeating: "a", count: 41): 1]), [:])
    }
    func testDurationDefaultsAndCeiling() {
        XCTAssertEqual(NeuroContentFeatures.durationScore(seconds: 0, isLive: false), log1p(300) / log1p(7200), accuracy: 1e-12)
        XCTAssertEqual(NeuroContentFeatures.durationScore(seconds: .nan, isLive: true), log1p(3600) / log1p(7200), accuracy: 1e-12)
        XCTAssertEqual(NeuroContentFeatures.durationScore(seconds: 7200, isLive: false), 1)
        XCTAssertEqual(NeuroContentFeatures.durationScore(seconds: 20000, isLive: false), 1)
    }
    func testPacingSubstringCountingAndShortsFallback() {
        XCTAssertEqual(NeuroContentFeatures.pacingScore(title: "tiktoks", isShort: false), 0.8, accuracy: 1e-12)
        XCTAssertEqual(NeuroContentFeatures.pacingScore(title: "podcast", isShort: true), 0.3, accuracy: 1e-12)
        XCTAssertEqual(NeuroContentFeatures.pacingScore(title: "fast podcast", isShort: true), 0.85)
        XCTAssertEqual(NeuroContentFeatures.pacingScore(title: "guitar", isShort: false), 0.5)
        XCTAssertEqual(NeuroContentFeatures.pacingScore(title: "podcast essay ambient study sleep", isShort: false), 0.05)
    }
    func testComplexityChaptersAndUTF16Lengths() {
        XCTAssertEqual(NeuroContentFeatures.complexityScore(title: "abcd", description: nil), 0.45, accuracy: 1e-12)
        XCTAssertEqual(NeuroContentFeatures.complexityScore(title: "abcd", description: "0:00 1:00 2:00"), 0.65, accuracy: 1e-12)
        XCTAssertEqual(NeuroContentFeatures.complexityScore(title: "abcd", description: "0:00 1:00"), 0.45, accuracy: 1e-12)
        XCTAssertEqual(NeuroContentFeatures.complexityScore(title: "𐐨𐐨", description: nil), 0.45, accuracy: 1e-12)
        XCTAssertEqual(NeuroContentFeatures.complexityScore(title: "", description: nil), 0.4)
    }
    func testVectorAssemblyCarriesFormatsAndLiveFlag() {
        let vector = NeuroContentFeatures.vector(weightedTopics: ["guitar": 2], title: "guitar", isLive: true, formats: ["live"])
        XCTAssertEqual(vector.topics, ["guitar": 1])
        XCTAssertEqual(vector.isLive, 1)
        XCTAssertEqual(vector.formats, ["live"])
        XCTAssertEqual(vector.pacing, 0.5)
    }
}
