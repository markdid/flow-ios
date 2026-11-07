// SPDX-License-Identifier: GPL-3.0-only
import FlowCore
import SwiftUI

struct LibraryView: View {
    @Environment(MetadataCache.self) private var cache
    @EnvironmentObject private var library: LibraryStore
    @State private var newPlaylist = false
    @State private var playlistName = ""

    private var titles: [String: String] { Dictionary(library.snapshot.videos.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a }) }

    var body: some View {
        List {
            let history = library.snapshot.history.prefix(20)
            if !history.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(history) { entry in
                                ShelfCard(video: cache.item(entry.videoID, fallbackTitle: titles[entry.videoID] ?? ""), width: 160)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .listRowInsets(EdgeInsets())
                } header: {
                    NavigationLink(value: Route.history) {
                        HStack { Text("History").font(.title3.weight(.bold)).foregroundStyle(.primary); Image(systemName: "chevron.right").font(.footnote.weight(.bold)) }
                    }
                    .textCase(nil)
                }
            }
            Section("Playlists") {
                ForEach(library.snapshot.playlists.filter { $0.id != LocalPlaylist.savedShortsID }) { playlist in
                    NavigationLink(value: Route.playlist(id: playlist.id)) {
                        Label {
                            HStack { Text(playlist.name); Spacer(); Text("\(playlist.videoIDs.count)").foregroundStyle(.secondary) }
                        } icon: {
                            Image(systemName: playlist.id == LocalPlaylist.watchLaterID ? "clock" : "music.note.list")
                        }
                    }
                    .swipeActions {
                        if !playlist.isBuiltIn {
                            Button("Delete", role: .destructive) { Task { await library.perform(.deletePlaylist(playlist.id)) } }
                        }
                    }
                }
                Button { playlistName = ""; newPlaylist = true } label: { Label("New playlist", systemImage: "plus") }
                NavigationLink { RemotePlaylistView() } label: { Label("Open YouTube playlist", systemImage: "link") }
            }
            Section {
                NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
            }
            if let error = library.error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Library")
        .alert("New playlist", isPresented: $newPlaylist) {
            TextField("Name", text: $playlistName)
            Button("Create") {
                let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task { await library.perform(.createPlaylist(LocalPlaylist(name: name))) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct PlaylistView: View {
    @Environment(MetadataCache.self) private var cache
    @Environment(PlayerModel.self) private var player
    @EnvironmentObject private var library: LibraryStore
    let id: String

    var body: some View {
        let playlist = library.snapshot.playlists.first { $0.id == id }
        let videos = library.snapshot.videos(in: id).map { cache.item($0.id, fallbackTitle: $0.title) }
        List {
            ForEach(videos) { video in
                VideoRow(video: video)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
            .onDelete { offsets in
                let ids = offsets.map { videos[$0].id }
                Task { for videoID in ids { await library.perform(.removeFromPlaylist(videoID: videoID, playlistID: id)) } }
            }
            .onMove { from, to in
                var ids = videos.map(\.id)
                ids.move(fromOffsets: from, toOffset: to)
                Task { await library.perform(.reorderPlaylist(id: id, videoIDs: ids)) }
            }
            if videos.isEmpty { Text("Empty").foregroundStyle(.secondary) }
        }
        .listStyle(.plain)
        .navigationTitle(playlist?.name ?? "Playlist")
        .toolbar {
            if let first = videos.first {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { player.play(first) } label: { Image(systemName: "play.fill") }.accessibilityLabel("Play")
                }
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
    }
}

struct HistoryView: View {
    @Environment(MetadataCache.self) private var cache
    @EnvironmentObject private var library: LibraryStore
    @State private var confirmClear = false

    var body: some View {
        let titles = Dictionary(library.snapshot.videos.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        List {
            ForEach(library.snapshot.history) { entry in
                VideoRow(video: cache.item(entry.videoID, fallbackTitle: titles[entry.videoID] ?? ""))
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .swipeActions { Button("Remove", role: .destructive) { Task { await library.perform(.removeHistory(entry.videoID)) } } }
            }
            if library.snapshot.history.isEmpty { Text("No history").foregroundStyle(.secondary) }
        }
        .listStyle(.plain)
        .navigationTitle("History")
        .toolbar {
            Menu {
                Button(library.snapshot.historyPaused ? "Resume history" : "Pause history") {
                    Task { await library.perform(.pauseHistory(!library.snapshot.historyPaused)) }
                }
                Button("Clear history", role: .destructive) { confirmClear = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .confirmationDialog("Clear history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { Task { await library.perform(.clearHistory) } }
        }
    }
}

struct SettingsView: View {
    @AppStorage(Settings.qualityKey) private var quality = 1080
    @AppStorage(Settings.autoplayKey) private var autoplay = true
    @AppStorage(Settings.sponsorBlockKey) private var sponsorBlock = true

    var body: some View {
        Form {
            Section("Playback") {
                Picker("Default quality", selection: $quality) {
                    ForEach([2160, 1440, 1080, 720, 480, 360], id: \.self) { Text("\($0)p").tag($0) }
                }
                Toggle("Autoplay", isOn: $autoplay)
                Toggle("SponsorBlock", isOn: $sponsorBlock)
            }
            Section("Data") {
                NavigationLink("Subscriptions import/export") { SubscriptionTransferView() }
                NavigationLink("Import Google Takeout") { TakeoutImportView() }
            }
        }
        .navigationTitle("Settings")
    }
}
