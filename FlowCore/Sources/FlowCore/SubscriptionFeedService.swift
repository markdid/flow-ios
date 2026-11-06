// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client Copyright (C) 2025-2026 A-EDev.
// Swift bounded RSS feed orchestration, modified 2026-11-06.
import Foundation

public struct SubscriptionFeedReport: Sendable {
    public let uploads: [SubscriptionUpload]
    public let failures: [String: String]
    public let cachedChannelIDs: Set<String>
    public let refreshedAt: Date
}

public actor SubscriptionFeedService {
    public typealias Fetch = @Sendable (String, String) async throws -> ChannelRSSFeed
    private struct CacheEntry { let feed: ChannelRSSFeed; let fetchedAt: Date }
    private struct Outcome: Sendable { let channelID: String; let feed: ChannelRSSFeed?; let error: String? }
    private let fetch: Fetch
    private var cache: [String: CacheEntry] = [:]
    private var generation = UUID()
    public init() {
        let client = ChannelRSSClient()
        fetch = { id, name in try await client.fetch(channelID: id, fallbackName: name) }
    }
    public init(fetch: @escaping Fetch) { self.fetch = fetch }
    public func refresh(subscriptions: [LocalSubscription], force: Bool = false, now: Date = Date()) async throws -> SubscriptionFeedReport {
        let current = UUID(); generation = current
        let allowed = Set(subscriptions.map(\.id))
        cache = cache.filter { allowed.contains($0.key) }
        var seen = Set<String>()
        let unique = subscriptions.filter { seen.insert($0.id).inserted }
        let stale = unique.filter { subscription in
            if force { return true }
            guard let entry = cache[subscription.id] else { return true }
            return now.timeIntervalSince(entry.fetchedAt) >= 900
        }
        var failures: [String: String] = [:]
        let staleIDs = Set(stale.map(\.id))
        var usedCache = Set(unique.filter { !staleIDs.contains($0.id) }.map(\.id))
        let fetch = self.fetch
        // A bounded round avoids creating one network task per subscription at once.
        for start in stride(from: 0, to: stale.count, by: 3) {
            try Task.checkCancellation()
            guard generation == current else { throw CancellationError() }
            let batch = Array(stale[start..<min(start + 3, stale.count)])
            let outcomes = try await withThrowingTaskGroup(of: Outcome.self) { group -> [Outcome] in
                for subscription in batch {
                    group.addTask {
                        do {
                            let feed = try await fetch(subscription.id, subscription.name)
                            try Task.checkCancellation()
                            return Outcome(channelID: subscription.id, feed: feed, error: nil)
                        } catch {
                            try Task.checkCancellation()
                            return Outcome(channelID: subscription.id, feed: nil, error: error.localizedDescription)
                        }
                    }
                }
                var results: [Outcome] = []
                for try await outcome in group { results.append(outcome) }
                return results
            }
            try Task.checkCancellation()
            guard generation == current else { throw CancellationError() }
            for outcome in outcomes {
                if let feed = outcome.feed { cache[outcome.channelID] = CacheEntry(feed: feed, fetchedAt: now) }
                else {
                    failures[outcome.channelID] = outcome.error ?? "Could not fetch this channel."
                    if cache[outcome.channelID] != nil { usedCache.insert(outcome.channelID) }
                }
            }
        }
        try Task.checkCancellation()
        guard generation == current else { throw CancellationError() }
        let feeds = unique.compactMap { cache[$0.id]?.feed }
        return SubscriptionFeedReport(uploads: Self.merge(feeds.flatMap(\.uploads)), failures: failures, cachedChannelIDs: usedCache, refreshedAt: now)
    }
    public static func merge(_ uploads: [SubscriptionUpload], maximum: Int = 1000) -> [SubscriptionUpload] {
        var byID: [String: SubscriptionUpload] = [:]
        for item in uploads {
            if let old = byID[item.id] {
                if old.publishedAt == nil && item.publishedAt != nil { byID[item.id] = item }
            } else { byID[item.id] = item }
        }
        return Array(byID.values.sorted {
            let left = $0.publishedAt ?? .distantPast, right = $1.publishedAt ?? .distantPast
            return left == right ? $0.id < $1.id : left > right
        }.prefix(max(0, maximum)))
    }
}
