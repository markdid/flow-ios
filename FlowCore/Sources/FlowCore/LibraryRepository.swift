// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client Copyright (C) 2025-2026 A-EDev.
// Modified Swift adaptation, 2026-11-06. See Documentation/LibraryPort.md.
import Foundation

/// Own ONE repository per file. Serial actor access prevents lost updates inside the app.
/// Disk writes complete before memory changes; failed loads never overwrite existing data.
public actor LibraryRepository {
    private let fileURL: URL
    private var state: LibrarySnapshot
    private var watchSessions: [String: UUID] = [:]

    /// Pass a NEW filename (e.g. collection-v1.json), not the prototype library.json.
    /// Legacy bookmarks are imported only if the destination does not already exist.
    /// A corrupt legacy file throws and is preserved. Source files are never deleted.
    public init(fileURL: URL, legacyBookmarksURL: URL? = nil) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            // Inspect version before decoding version-specific required fields.
            struct Header: Decodable { let schemaVersion: Int }
            let version = try JSONDecoder().decode(Header.self, from: data).schemaVersion
            guard version == 1 else { throw LibraryError.unsupportedVersion(version) }
            state = try JSONDecoder().decode(LibrarySnapshot.self, from: data).validated()
        } else {
            var initial = LibrarySnapshot()
            if let legacyBookmarksURL, FileManager.default.fileExists(atPath: legacyBookmarksURL.path) {
                let legacy = try JSONDecoder().decode([VideoReference].self, from: Data(contentsOf: legacyBookmarksURL))
                var seen = Set<String>()
                initial.videos = legacy.filter { seen.insert($0.id).inserted }
            }
            state = try initial.validated()
            // Persist migration immediately; next launch must not re-import deleted bookmarks.
            try Self.persist(state, to: fileURL)
        }
    }

    public func snapshot() -> LibrarySnapshot { state }

    /// Call once for an explicit playback start, never from a progress callback.
    /// Starting another session for this video invalidates its previous callbacks.
    /// Returns nil while history is paused; unpausing requires a new explicit start.
    public func beginWatch(videoID: String) -> WatchSession? {
        guard !state.historyPaused else { return nil }
        let token = UUID()
        watchSessions[videoID] = token
        return WatchSession(videoID: videoID, token: token)
    }

    @discardableResult public func apply(_ command: LibraryCommand) throws -> LibrarySnapshot {
        var next = state
        var nextSessions = watchSessions
        func upsert(_ video: VideoReference) {
            next.videos.removeAll { $0.id == video.id }; next.videos.insert(video, at: 0)
        }
        func playlistIndex(_ id: String) throws -> Int {
            guard let index = next.playlists.firstIndex(where: { $0.id == id }) else { throw LibraryError.missingPlaylist }
            return index
        }
        switch command {
        case .saveVideo(let video): upsert(video)
        case .deleteVideo(let id):
            nextSessions.removeValue(forKey: id)
            next.videos.removeAll { $0.id == id }
            next.history.removeAll { $0.videoID == id }
            for index in next.playlists.indices { next.playlists[index].videoIDs.removeAll { $0 == id } }
        case .createPlaylist(let playlist):
            guard !next.playlists.contains(where: { $0.id == playlist.id }) else { throw LibraryError.duplicatePlaylist }
            next.playlists.append(playlist)
        case .importPlaylist(let playlist, let videos):
            guard !playlist.isBuiltIn, !next.playlists.contains(where: { $0.id == playlist.id }) else { throw LibraryError.duplicatePlaylist }
            guard videos.count <= TakeoutCSV.maximumRows, Set(videos.map(\.id)).count == videos.count,
                  playlist.videoIDs == videos.map(\.id) else { throw LibraryError.invalidData }
            let existing = Set(next.videos.map(\.id))
            // CSV has IDs, not titles. Never replace richer existing metadata with IDs.
            next.videos.append(contentsOf: videos.filter { !existing.contains($0.id) })
            next.playlists.append(playlist)
        case .renamePlaylist(let id, let name):
            let index = try playlistIndex(id)
            guard !next.playlists[index].isBuiltIn else { throw LibraryError.protectedPlaylist }
            next.playlists[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        case .deletePlaylist(let id):
            let index = try playlistIndex(id)
            guard !next.playlists[index].isBuiltIn else { throw LibraryError.protectedPlaylist }
            next.playlists.remove(at: index)
        case .addToPlaylist(let video, let id):
            if !next.playlists.contains(where: { $0.id == id }), [LocalPlaylist.watchLaterID, LocalPlaylist.savedShortsID].contains(id) {
                next.playlists.append(LocalPlaylist(id: id, name: id == LocalPlaylist.watchLaterID ? "Watch Later" : "Saved Shorts"))
            }
            let index = try playlistIndex(id)
            upsert(video)
            if !next.playlists[index].videoIDs.contains(video.id) {
                if next.playlists[index].isBuiltIn { next.playlists[index].videoIDs.insert(video.id, at: 0) }
                else { next.playlists[index].videoIDs.append(video.id) }
            }
        case .removeFromPlaylist(let videoID, let playlistID):
            let index = try playlistIndex(playlistID)
            next.playlists[index].videoIDs.removeAll { $0 == videoID }
        case .reorderPlaylist(let id, let ids):
            let index = try playlistIndex(id)
            guard Set(ids).count == ids.count, Set(ids) == Set(next.playlists[index].videoIDs) else { throw LibraryError.invalidData }
            next.playlists[index].videoIDs = ids
        case .subscribe(let subscription):
            if let index = next.subscriptions.firstIndex(where: { $0.id == subscription.id }) {
                // Preserve original subscribe date while allowing metadata/preferences to refresh.
                let previous = next.subscriptions[index]
                next.subscriptions[index] = LocalSubscription(id: subscription.id, name: subscription.name,
                    thumbnailURL: subscription.thumbnailURL, subscribedAt: previous.subscribedAt,
                    isMusic: subscription.isMusic, notificationsEnabled: subscription.notificationsEnabled)
            } else { next.subscriptions.insert(subscription, at: 0) }
        case .importSubscriptions(let subscriptions):
            guard subscriptions.count <= NewPipeSubscriptions.maximumEntries,
                  subscriptions.allSatisfy({ ChannelBrowseClient.validChannelID($0.id) }) else { throw LibraryError.invalidData }
            for subscription in subscriptions {
                if let index = next.subscriptions.firstIndex(where: { $0.id == subscription.id }) {
                    let previous = next.subscriptions[index]
                    next.subscriptions[index] = LocalSubscription(id: subscription.id, name: subscription.name,
                        thumbnailURL: previous.thumbnailURL ?? subscription.thumbnailURL, subscribedAt: previous.subscribedAt,
                        isMusic: previous.isMusic, notificationsEnabled: previous.notificationsEnabled)
                } else { next.subscriptions.append(subscription) }
            }
        case .unsubscribe(let id): next.subscriptions.removeAll { $0.id == id }
        case .recordWatch(let video, var entry, let session):
            guard !next.historyPaused, session.videoID == video.id,
                  nextSessions[video.id] == session.token else { return state }
            guard entry.videoID == video.id, entry.position.isFinite, entry.duration.isFinite,
                  entry.position >= 0, entry.duration >= 0 else { throw LibraryError.invalidData }
            if entry.duration > 0 { entry.position = min(entry.position, entry.duration) }
            // Delayed callbacks must not overwrite newer progress.
            if let old = next.history.first(where: { $0.videoID == video.id }), old.watchedAt > entry.watchedAt { return state }
            upsert(video)
            next.history.removeAll { $0.videoID == video.id }; next.history.append(entry)
            next.history.sort { $0.watchedAt == $1.watchedAt ? $0.videoID < $1.videoID : $0.watchedAt > $1.watchedAt }
        case .pauseHistory(let paused):
            next.historyPaused = paused
            if paused { nextSessions.removeAll() }
        case .removeHistory(let id):
            next.history.removeAll { $0.videoID == id }
            nextSessions.removeValue(forKey: id)
        case .clearHistory:
            next.history.removeAll()
            nextSessions.removeAll()
        }
        next = try next.validated()
        try Self.persist(next, to: fileURL)
        state = next
        watchSessions = nextSessions
        return next
    }

    private static func persist(_ snapshot: LibrarySnapshot, to url: URL) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
