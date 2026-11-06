// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import FlowCore

struct PlaylistActions: View {
    @EnvironmentObject private var library: LibraryStore
    let video: VideoReference
    var body: some View {
        Menu("Add to playlist") {
            Button("Watch Later") { add(LocalPlaylist.watchLaterID) }
            Button("Saved Shorts") { add(LocalPlaylist.savedShortsID) }
            ForEach(library.snapshot.playlists.filter { !$0.isBuiltIn }) { playlist in
                Button(playlist.name) { add(playlist.id) }
            }
        }.buttonStyle(.borderless)
    }
    private func add(_ id: String) {
        Task { _ = await library.perform(.addToPlaylist(video: video, playlistID: id)) }
    }
}

struct PlaylistsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var creating = false
    @State private var name = ""
    var body: some View {
        List {
            if library.snapshot.playlists.isEmpty { Text("Create a playlist or save a video to Watch Later.") }
            ForEach(library.snapshot.playlists) { playlist in
                NavigationLink { PlaylistDetailView(playlistID: playlist.id) } label: {
                    VStack(alignment: .leading) {
                        Text(playlist.name)
                        Text("\(playlist.videoIDs.count) videos").font(.caption).foregroundStyle(.secondary)
                    }
                }.deleteDisabled(playlist.isBuiltIn)
            }.onDelete { offsets in
                let ids = offsets.compactMap { index in
                    library.snapshot.playlists.indices.contains(index) ? library.snapshot.playlists[index].id : nil
                }
                Task { for id in ids { _ = await library.perform(.deletePlaylist(id)) } }
            }
        }.navigationTitle("Playlists")
            .toolbar { Button("Create") { name = ""; creating = true } }
            .alert("New playlist", isPresented: $creating) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Create") { Task { _ = await library.perform(.createPlaylist(LocalPlaylist(name: name.trimmingCharacters(in: .whitespacesAndNewlines)))) } }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    let playlistID: String
    @State private var renaming = false
    @State private var name = ""
    private var playlist: LocalPlaylist? { library.snapshot.playlists.first { $0.id == playlistID } }
    private var videos: [VideoReference] { library.snapshot.videos(in: playlistID) }
    var body: some View {
        List {
            if videos.isEmpty { Text("This playlist is empty. Add videos from search or your library.") }
            ForEach(videos) { video in
                NavigationLink(video.title) { PlaybackView(video: video) }
            }.onDelete { offsets in
                let ids = offsets.compactMap { videos.indices.contains($0) ? videos[$0].id : nil }
                Task { for id in ids { _ = await library.perform(.removeFromPlaylist(videoID: id, playlistID: playlistID)) } }
            }.onMove { from, to in
                var ids = videos.map(\.id)
                ids.move(fromOffsets: from, toOffset: to)
                Task { _ = await library.perform(.reorderPlaylist(id: playlistID, videoIDs: ids)) }
            }
        }.navigationTitle(playlist?.name ?? "Playlist")
            .toolbar {
                EditButton()
                if playlist?.isBuiltIn == false { Button("Rename") { name = playlist?.name ?? ""; renaming = true } }
            }
            .alert("Rename playlist", isPresented: $renaming) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Save") { Task { _ = await library.perform(.renamePlaylist(id: playlistID, name: name)) } }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var confirmingClear = false
    var body: some View {
        List {
            Toggle("Pause watch history", isOn: Binding(get: { library.snapshot.historyPaused }, set: { paused in
                Task { _ = await library.perform(.pauseHistory(paused)) }
            }))
            if library.snapshot.history.isEmpty { Text("No native playback history yet. Embedded-player progress is not tracked.") }
            ForEach(library.snapshot.history) { entry in
                if let video = library.videos.first(where: { $0.id == entry.videoID }) {
                    NavigationLink { PlaybackView(video: video) } label: {
                        VStack(alignment: .leading) {
                            Text(video.title)
                            ProgressView(value: entry.progress)
                            Text(entry.watchedAt, style: .date).font(.caption)
                        }
                    }
                }
            }.onDelete { offsets in
                let ids = offsets.compactMap { library.snapshot.history.indices.contains($0) ? library.snapshot.history[$0].videoID : nil }
                Task { for id in ids { _ = await library.perform(.removeHistory(id)) } }
            }
        }.navigationTitle("Watch history")
            .toolbar { Button("Clear", role: .destructive) { confirmingClear = true }.disabled(library.snapshot.history.isEmpty) }
            .confirmationDialog("Clear all watch history?", isPresented: $confirmingClear) {
                Button("Clear history", role: .destructive) { Task { _ = await library.perform(.clearHistory) } }
            }
    }
}

struct SubscriptionsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var adding = false
    @State private var channelID = ""
    @State private var name = ""
    var body: some View {
        List {
            NavigationLink("Latest uploads") { SubscriptionFeedView() }
            NavigationLink("Import and export") { SubscriptionTransferView() }
            Text("Open a saved channel to browse supported video tabs. Background feed refresh and notifications are not yet implemented.").font(.footnote).foregroundStyle(.secondary)
            ForEach(library.snapshot.subscriptions) { subscription in
                NavigationLink { ChannelView(channelID: subscription.id, name: subscription.name) } label: {
                    VStack(alignment: .leading) {
                        Text(subscription.name)
                        Text(subscription.id).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.onDelete { offsets in
                let ids = offsets.compactMap { library.snapshot.subscriptions.indices.contains($0) ? library.snapshot.subscriptions[$0].id : nil }
                Task { for id in ids { _ = await library.perform(.unsubscribe(id)) } }
            }
        }.navigationTitle("Subscriptions")
            .toolbar { Button("Add") { channelID = ""; name = ""; adding = true } }
            .alert("Save channel", isPresented: $adding) {
                TextField("Channel ID (UC…)", text: $channelID).textInputAutocapitalization(.never)
                TextField("Channel name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Save") { Task { _ = await library.perform(.subscribe(LocalSubscription(id: channelID.trimmingCharacters(in: .whitespacesAndNewlines), name: name.trimmingCharacters(in: .whitespacesAndNewlines)))) } }
                    .disabled(!ChannelBrowseClient.validChannelID(channelID.trimmingCharacters(in: .whitespacesAndNewlines)) || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
    }
}
