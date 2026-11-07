// SPDX-License-Identifier: GPL-3.0-only
import FlowCore
import Foundation
import Observation

enum ChannelUploads {
    static let videosTab = "EgZ2aWRlb3PyBgQKAjoA"

    static func fetch(channelID: String, name: String) async throws -> [VideoItem] {
        let page = try await ChannelBrowseClient().browse(channelID: channelID, params: videosTab)
        return page.feed.items.map { item in
            var item = item
            item.channel = item.channel ?? page.title ?? name
            item.channelID = item.channelID ?? channelID
            return item
        }
    }
}

/// Approximate age in seconds for strings like "3 days ago" or "Streamed 2 weeks ago".
enum RelativeAge {
    static func seconds(_ text: String?) -> Double {
        guard let text = text?.lowercased() else { return .greatestFiniteMagnitude }
        let words = text.split(separator: " ")
        guard let index = words.firstIndex(where: { Int($0) != nil }), let value = Double(words[index]), index + 1 < words.count else {
            return .greatestFiniteMagnitude
        }
        let unit = words[index + 1]
        let scale: Double
        switch true {
        case unit.hasPrefix("second"): scale = 1
        case unit.hasPrefix("minute"): scale = 60
        case unit.hasPrefix("hour"): scale = 3600
        case unit.hasPrefix("day"): scale = 86_400
        case unit.hasPrefix("week"): scale = 604_800
        case unit.hasPrefix("month"): scale = 2_592_000
        case unit.hasPrefix("year"), unit.hasPrefix("y"): scale = 31_536_000
        default: return .greatestFiniteMagnitude
        }
        return value * scale
    }
}

/// On-device interest profile built from watch history and subscriptions.
struct InterestProfile {
    var terms: [String: Double] = [:]
    var channels: [String: Double] = [:]
    var watched: Set<String> = []

    static let stopWords: Set<String> = [
        "the", "and", "for", "with", "you", "your", "this", "that", "from", "are", "was", "but", "not", "how", "what", "why", "who",
        "all", "out", "new", "official", "video", "videos", "full", "episode", "part", "live", "feat", "ft", "vs", "his", "her", "its",
        "our", "they", "them", "can", "get", "got", "has", "have", "had", "will", "just", "about", "into", "best", "top", "one", "two",
        "more", "most", "make", "made", "when", "where", "than", "then", "there", "here", "music", "audio", "lyrics", "lyric", "remaster",
        "remastered", "hd", "4k", "1080p", "ever", "every", "day", "time", "first", "last", "after", "before", "over", "under", "without",
    ]

    static func tokens(_ title: String) -> [String] {
        title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) && Int($0) == nil }
    }

    init() {}

    @MainActor init(history: [LocalWatchEntry], subscriptions: [LocalSubscription], cache: MetadataCache, titles: [String: String], now: Date = Date()) {
        for entry in history.prefix(300) {
            watched.insert(entry.videoID)
            let ageDays = max(0, now.timeIntervalSince(entry.watchedAt)) / 86_400
            let engagement = entry.duration > 0 ? min(1, max(0.15, entry.progress * 1.2)) : 0.5
            let weight = exp(-ageDays / 21) * engagement
            let item = cache.item(entry.videoID, fallbackTitle: titles[entry.videoID] ?? "")
            for token in Set(Self.tokens(item.title)) { terms[token, default: 0] += weight }
            if let channel = item.channelID ?? item.channel { channels[channel, default: 0] += weight }
        }
        for subscription in subscriptions { channels[subscription.id, default: 0] += 0.6 }
    }

    var isEmpty: Bool { terms.isEmpty && channels.isEmpty }

    func topTerms(_ count: Int) -> [String] {
        terms.filter { $0.value >= 0.3 }.sorted { $0.value > $1.value }.prefix(count).map(\.key)
    }

    func score(_ video: VideoItem) -> Double {
        let tokens = Set(Self.tokens(video.title))
        let termScore = tokens.reduce(0) { $0 + (terms[$1] ?? 0) } / max(1, sqrt(Double(tokens.count)))
        let channelScore = video.channelID.flatMap { channels[$0] } ?? video.channel.flatMap { channels[$0] } ?? 0
        return termScore + 0.6 * min(channelScore, 3)
    }
}

@MainActor @Observable final class HomeFeedModel {
    private(set) var items: [VideoItem] = []
    private(set) var continueWatching: [VideoItem] = []
    private(set) var topics: [String] = []
    private(set) var loading = false
    private(set) var error: String?
    var topic: String?
    private var task: Task<Void, Never>?

    private static let coldStart = ["music", "science explained", "comedy", "cooking", "technology review", "gaming", "history documentary", "travel"]

    func refresh(library: LibraryStore, cache: MetadataCache) {
        task?.cancel()
        loading = true; error = nil
        let snapshot = library.snapshot
        let titles = Dictionary(snapshot.videos.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        let profile = InterestProfile(history: snapshot.history, subscriptions: snapshot.subscriptions, cache: cache, titles: titles)
        continueWatching = snapshot.history.filter { $0.progress > 0.03 && $0.progress < 0.9 && !$0.isShort }.prefix(10)
            .map { cache.item($0.videoID, fallbackTitle: titles[$0.videoID] ?? "") }
        topics = profile.topTerms(10)
        let topic = topic
        task = Task {
            let candidates: [(VideoItem, Double)]
            if let topic {
                candidates = await Self.search([topic], boost: 0.5)
            } else {
                candidates = await Self.gather(profile: profile, snapshot: snapshot)
            }
            guard !Task.isCancelled else { return }
            let ranked = Self.rank(candidates, profile: profile, keepWatched: topic != nil)
            cache.remember(ranked)
            if ranked.isEmpty { self.error = "Couldn't load feed" }
            self.items = ranked
            self.loading = false
        }
    }

    private static func gather(profile: InterestProfile, snapshot: LibrarySnapshot) async -> [(VideoItem, Double)] {
        await withTaskGroup(of: [(VideoItem, Double)].self) { group in
            let recent = snapshot.history.filter { !$0.isShort }.prefix(5)
            for entry in recent {
                group.addTask {
                    let details = try? await WatchDetailsClient().details(videoID: entry.videoID)
                    return (details?.relatedItems ?? []).prefix(12).map { ($0, 0.35 + 0.4 * entry.progress) }
                }
            }
            let subscriptions = snapshot.subscriptions
                .sorted { (profile.channels[$0.id] ?? 0) > (profile.channels[$1.id] ?? 0) }
                .prefix(8)
            for subscription in subscriptions {
                group.addTask {
                    let uploads = (try? await ChannelUploads.fetch(channelID: subscription.id, name: subscription.name)) ?? []
                    return uploads.prefix(6).map { video in
                        let age = RelativeAge.seconds(video.published)
                        return (video, age < 604_800 ? 0.9 : age < 2_592_000 ? 0.4 : 0.05)
                    }
                }
            }
            var queries = profile.topTerms(3)
            if profile.isEmpty || (recent.isEmpty && subscriptions.isEmpty) { queries = Array(coldStart.shuffled().prefix(4)) }
            for query in queries {
                group.addTask { await search([query], boost: 0.15) }
            }
            var all: [(VideoItem, Double)] = []
            for await batch in group { all += batch }
            return all
        }
    }

    private static func search(_ queries: [String], boost: Double) async -> [(VideoItem, Double)] {
        var results: [(VideoItem, Double)] = []
        for query in queries {
            let page = try? await VideoSearchClient().search(query: query)
            results += (page?.items ?? []).map { ($0, boost) }
        }
        return results
    }

    private static func rank(_ candidates: [(VideoItem, Double)], profile: InterestProfile, keepWatched: Bool) -> [VideoItem] {
        var best: [String: (VideoItem, Double)] = [:]
        for (video, boost) in candidates where !video.isShort {
            if !keepWatched, profile.watched.contains(video.id) { continue }
            if let duration = video.duration, duration.split(separator: ":").count == 2, (Int(duration.split(separator: ":")[0]) ?? 1) == 0 { continue }
            let score = profile.score(video) + boost + Double.random(in: 0...0.25)
            if let existing = best[video.id] {
                best[video.id] = (existing.0.merged(with: video), existing.1 + 0.2)
            } else {
                best[video.id] = (video, score)
            }
        }
        // Greedy pick with a per-channel cap so one channel can't take over the feed.
        var remaining = best.values.sorted { $0.1 > $1.1 }
        var picked: [VideoItem] = []
        var perChannel: [String: Int] = [:]
        while !remaining.isEmpty {
            let window = picked.suffix(8)
            let index = remaining.firstIndex { candidate in
                let key = candidate.0.channelID ?? candidate.0.channel ?? candidate.0.id
                return window.filter { ($0.channelID ?? $0.channel ?? $0.id) == key }.count < 2 && perChannel[key, default: 0] < 6
            } ?? 0
            let choice = remaining.remove(at: index).0
            perChannel[choice.channelID ?? choice.channel ?? choice.id, default: 0] += 1
            picked.append(choice)
        }
        return picked
    }
}

@MainActor @Observable final class SubscriptionFeedModel {
    private(set) var items: [VideoItem] = []
    private(set) var loading = false
    private(set) var failures = 0
    private var task: Task<Void, Never>?
    private var loadedFor: Set<String> = []

    func refresh(_ subscriptions: [LocalSubscription], cache: MetadataCache, force: Bool = false) {
        let ids = Set(subscriptions.map(\.id))
        guard force || ids != loadedFor else { return }
        loadedFor = ids
        task?.cancel()
        guard !subscriptions.isEmpty else { items = []; return }
        loading = true
        task = Task {
            var all: [VideoItem] = []
            var failed = 0
            await withTaskGroup(of: [VideoItem]?.self) { group in
                var iterator = subscriptions.makeIterator()
                var running = 0
                func next() -> Bool {
                    guard let subscription = iterator.next() else { return false }
                    group.addTask { try? await ChannelUploads.fetch(channelID: subscription.id, name: subscription.name) }
                    return true
                }
                while running < 6, next() { running += 1 }
                for await result in group {
                    if let result { all += result.prefix(15) } else { failed += 1 }
                    _ = next()
                }
            }
            guard !Task.isCancelled else { return }
            let sorted = all.filter { !$0.isShort }.sorted { RelativeAge.seconds($0.published) < RelativeAge.seconds($1.published) }
            cache.remember(sorted)
            self.items = sorted
            self.failures = failed
            self.loading = false
        }
    }
}
