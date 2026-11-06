import Foundation
import XCTest
@testable import FlowCore

final class NeuroBatchScorerTests: XCTestCase {
    func testBatchUsesActualMathWithoutRankingOrInventingFeatures() throws {
        let video = try VideoReference(url: XCTUnwrap(URL(string: "https://youtu.be/abcdefghijk")))
        let taste = NeuroContentVector(topics: ["guitar": 1])
        let content = NeuroContentVector(topics: ["guitar": 1, "guitar:music": 0.3])
        let scorer = NeuroBatchScorer(taste: taste)
        let candidates = [NeuroCandidate(video: video, vector: content), NeuroCandidate(video: video, vector: NeuroContentVector())]
        let scores = scorer.score(candidates)
        XCTAssertEqual(scores.map(\.videoID), [video.id, video.id])
        XCTAssertEqual(scores[0].topicSimilarity, NeuroVectorMath.topicSimilarity(taste, content), accuracy: 1e-12)
        XCTAssertGreaterThan(scores[0].topicSimilarity, 1)
        XCTAssertEqual(scores[1].similarity, NeuroVectorMath.similarity(taste, NeuroContentVector()), accuracy: 1e-12)
        XCTAssertTrue(scorer.score([]).isEmpty)
    }
}
