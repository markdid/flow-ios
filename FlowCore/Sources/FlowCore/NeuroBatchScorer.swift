// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client Copyright (C) 2025-2026 Flow | A-EDev.
// Swift integration boundary for the ported NeuroVectorMath, 2026-11-06.
import Foundation

public struct NeuroCandidate: Sendable {
    public let video: VideoReference
    public let vector: NeuroContentVector
    public init(video: VideoReference, vector: NeuroContentVector) { self.video = video; self.vector = vector }
}
public struct NeuroCandidateScore: Sendable {
    public let videoID: String
    public let similarity: Double
    public let topicSimilarity: Double
}

/// Scores explicitly supplied content vectors against one prepared taste snapshot.
/// This does not derive topics, learn from watch history, fetch candidates, or rank a feed.
/// Input order and duplicates are preserved so callers retain candidate identity/order.
public struct NeuroBatchScorer: Sendable {
    private let prepared: NeuroVectorMath.PreparedVector
    public init(taste: NeuroContentVector) { prepared = NeuroVectorMath.PreparedVector(taste) }
    public func score(_ candidates: [NeuroCandidate]) -> [NeuroCandidateScore] {
        candidates.map { candidate in
            NeuroCandidateScore(videoID: candidate.video.id,
                similarity: NeuroVectorMath.similarity(prepared, candidate.vector),
                topicSimilarity: NeuroVectorMath.topicSimilarity(prepared, candidate.vector))
        }
    }
}
