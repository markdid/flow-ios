// SPDX-License-Identifier: GPL-3.0-only
// New iOS queue implementation, 2026-11-06.
import Foundation

public struct PlaybackQueue: Sendable {
    public enum RepeatMode: String, CaseIterable, Sendable { case off, all, one }
    public private(set) var videos: [VideoReference] = []
    public private(set) var index: Int?
    public var repeatMode: RepeatMode = .off
    public var shuffled = false {
        didSet { if shuffled != oldValue { resetShuffleTraversal() } }
    }
    private var shuffleRemaining: [Int] = []
    private var shuffleHistory: [Int] = []
    private var shuffleCursor = 0

    private mutating func resetShuffleTraversal() {
        shuffleRemaining = videos.indices.filter { $0 != index }.shuffled()
        shuffleHistory = index.map { [$0] } ?? []
        shuffleCursor = 0
    }
    public init() {}
    public var current: VideoReference? {
        guard let index, videos.indices.contains(index) else { return nil }
        return videos[index]
    }
    public mutating func replace(with videos: [VideoReference], startAt: Int = 0) {
        self.videos = videos
        index = videos.indices.contains(startAt) ? startAt : (videos.isEmpty ? nil : 0)
        resetShuffleTraversal()
    }
    public mutating func append(_ video: VideoReference) {
        videos.append(video)
        if index == nil { index = 0; resetShuffleTraversal() }
        else { shuffleRemaining.append(videos.count - 1) }
    }
    /// Manual next ignores repeat-one, matching standard player transport behavior.
    @discardableResult public mutating func next(automatic: Bool = false) -> VideoReference? {
        guard let index else { return nil }
        if automatic && repeatMode == .one { return current }
        if shuffled {
            if shuffleCursor + 1 < shuffleHistory.count {
                shuffleCursor += 1
                self.index = shuffleHistory[shuffleCursor]
                return current
            }
            if shuffleRemaining.isEmpty {
                guard repeatMode == .all else { return nil }
                shuffleRemaining = Array(videos.indices).shuffled()
                // Avoid immediate repeats at a cycle boundary when possible.
                if shuffleRemaining.last == index, shuffleRemaining.count > 1 {
                    shuffleRemaining.swapAt(0, shuffleRemaining.count - 1)
                }
            }
            guard let nextIndex = shuffleRemaining.popLast() else { return nil }
            self.index = nextIndex
            shuffleHistory.append(nextIndex)
            if shuffleHistory.count > 1000 { shuffleHistory.removeFirst() }
            shuffleCursor = shuffleHistory.count - 1
        } else if index + 1 < videos.count { self.index = index + 1 }
        else if repeatMode == .all { self.index = 0 }
        else { return nil }
        return current
    }
    @discardableResult public mutating func previous() -> VideoReference? {
        guard let index else { return nil }
        if shuffled {
            if shuffleCursor > 0 {
                shuffleCursor -= 1
                self.index = shuffleHistory[shuffleCursor]
            }
            return current
        }
        if index > 0 { self.index = index - 1 }
        else if repeatMode == .all { self.index = videos.count - 1 }
        return current
    }
}
