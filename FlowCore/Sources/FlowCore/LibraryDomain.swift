// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client Copyright (C) 2025-2026 A-EDev.
// Modified Swift adaptation, 2026-11-06. See Documentation/LibraryPort.md.
import Foundation

public struct LocalPlaylist: Codable, Equatable, Identifiable, Sendable {
    public static let watchLaterID = "watch_later"
    public static let savedShortsID = "saved_shorts"
    public let id: String
    public var name: String
    public var description: String
    public var isMusic: Bool
    public let createdAt: Date
    /// Ordered, unique video IDs. Metadata is stored once in LibrarySnapshot.videos.
    public var videoIDs: [String]
    public var isBuiltIn: Bool { [Self.watchLaterID, Self.savedShortsID].contains(id) }
    public init(id: String = UUID().uuidString, name: String, description: String = "",
                isMusic: Bool = false, createdAt: Date = Date(), videoIDs: [String] = []) {
        self.id = id; self.name = name; self.description = description
        self.isMusic = isMusic; self.createdAt = createdAt; self.videoIDs = videoIDs
    }
}

public struct LocalSubscription: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var thumbnailURL: URL?
    public let subscribedAt: Date
    public var isMusic: Bool
    /// Records user preference only; does not register background notifications.
    public var notificationsEnabled: Bool
    public init(id: String, name: String, thumbnailURL: URL? = nil, subscribedAt: Date = Date(),
                isMusic: Bool = false, notificationsEnabled: Bool = false) {
        self.id = id; self.name = name; self.thumbnailURL = thumbnailURL
        self.subscribedAt = subscribedAt; self.isMusic = isMusic
        self.notificationsEnabled = notificationsEnabled
    }
}

public struct LocalWatchEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String { videoID }
    public let videoID: String
    /// Seconds, unlike upstream Android's millisecond position/duration.
    public var position: TimeInterval
    public var duration: TimeInterval
    public var watchedAt: Date
    public var isMusic: Bool
    public var isShort: Bool
    public init(videoID: String, position: TimeInterval, duration: TimeInterval,
                watchedAt: Date = Date(), isMusic: Bool = false, isShort: Bool = false) {
        self.videoID = videoID; self.position = position; self.duration = duration
        self.watchedAt = watchedAt; self.isMusic = isMusic; self.isShort = isShort
    }
    public var progress: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
}

public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public internal(set) var videos: [VideoReference]
    public internal(set) var playlists: [LocalPlaylist]
    public internal(set) var subscriptions: [LocalSubscription]
    public internal(set) var history: [LocalWatchEntry]
    public internal(set) var historyPaused: Bool
    public init() {
        schemaVersion = 1; videos = []; playlists = []; subscriptions = []
        history = []; historyPaused = false
    }
    public func videos(in playlistID: String) -> [VideoReference] {
        guard let playlist = playlists.first(where: { $0.id == playlistID }) else { return [] }
        // Public Codable values may be inspected before validated(); never trap on duplicates.
        let indexed = Dictionary(videos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return playlist.videoIDs.compactMap { indexed[$0] }
    }
    public func validated() throws -> LibrarySnapshot {
        guard schemaVersion == 1 else { throw LibraryError.unsupportedVersion(schemaVersion) }
        func unique(_ ids: [String]) -> Bool { Set(ids).count == ids.count }
        let videoIDs = Set(videos.map(\.id))
        guard unique(videos.map(\.id)), unique(playlists.map(\.id)),
              unique(subscriptions.map(\.id)), unique(history.map(\.videoID)),
              playlists.allSatisfy({ !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && unique($0.videoIDs) && Set($0.videoIDs).isSubset(of: videoIDs) }),
              subscriptions.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              history.allSatisfy({ videoIDs.contains($0.videoID) && $0.position.isFinite && $0.duration.isFinite && $0.position >= 0 && $0.duration >= 0 && ($0.duration == 0 || $0.position <= $0.duration) })
        else { throw LibraryError.invalidData }
        return self
    }
}

/// Opaque capability captured once when playback begins. Not persisted or transferable
/// to another repository instance. Obtain through LibraryRepository.beginWatch(videoID:).
public struct WatchSession: Equatable, Sendable {
    public let videoID: String
    internal let token: UUID
}

public enum LibraryCommand: Sendable {
    case saveVideo(VideoReference)
    case deleteVideo(String)
    case createPlaylist(LocalPlaylist)
    /// Adds one new playlist and any missing video metadata in a single commit.
    case importPlaylist(playlist: LocalPlaylist, videos: [VideoReference])
    case renamePlaylist(id: String, name: String)
    case deletePlaylist(String)
    case addToPlaylist(video: VideoReference, playlistID: String)
    case removeFromPlaylist(videoID: String, playlistID: String)
    /// Full permutation of current IDs; stale or partial reorder requests fail atomically.
    case reorderPlaylist(id: String, videoIDs: [String])
    case subscribe(LocalSubscription)
    case importSubscriptions([LocalSubscription])
    case unsubscribe(String)
    case recordWatch(video: VideoReference, entry: LocalWatchEntry, session: WatchSession)
    case pauseHistory(Bool)
    case removeHistory(String)
    case clearHistory
}

public enum LibraryError: Error, LocalizedError {
    case invalidData, missingPlaylist, duplicatePlaylist, protectedPlaylist
    case unsupportedVersion(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidData: return "Library data or ordering is invalid. No changes were saved."
        case .missingPlaylist: return "This playlist no longer exists."
        case .duplicatePlaylist: return "This playlist already exists."
        case .protectedPlaylist: return "Built-in playlists cannot be renamed or deleted."
        case .unsupportedVersion(let version): return "Library version \(version) is newer than this app supports."
        }
    }
}
