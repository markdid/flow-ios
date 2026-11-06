// SPDX-License-Identifier: GPL-3.0-only
// New iOS public-playlist UI, 2026-11-06.
import SwiftUI
import FlowCore

@MainActor final class RemotePlaylistModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var title = "YouTube playlist"
    @Published private(set) var videos: [VideoReference] = []
    @Published private(set) var error: String?
    @Published private(set) var busy = false
    @Published private(set) var continuation: String?
    @Published private(set) var shortsGrid = false
    @Published private(set) var loaded = false
    @Published private(set) var canRetry = false
    private var id: RemotePlaylistID?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var tokens = Set<String>()
    private let client = RemotePlaylistClient()
    func open() {
        // Invalidate A before validating B, including malformed replacement input.
        cancel(); id = nil; canRetry = false; title = "YouTube playlist"
        videos = []; continuation = nil; tokens = []; loaded = false; shortsGrid = false; error = nil
        do { id = try RemotePlaylistID(input); canRetry = true; load() }
        catch { self.error = "Enter a public PL, UU or OLAK5uy_ playlist ID or YouTube playlist link. Mixes and account-private lists are not supported." }
    }
    func load(more: Bool = false) {
        guard !busy, let id, !more || continuation != nil else { return }
        let token = more ? continuation : nil
        let current = UUID(); generation = current; busy = true; error = nil
        task = Task {
            do {
                let page = try await client.browse(id: id, continuation: token)
                guard !Task.isCancelled, generation == current else { return }
                if !more { videos = []; tokens = [] }
                if let title = page.title { self.title = title }
                var seen = Set(videos.map(\.id))
                videos.append(contentsOf: page.feed.videos.filter { seen.insert($0.id).inserted })
                if let token { tokens.insert(token) }
                if let next = page.feed.continuation, !tokens.contains(next) { continuation = next } else { continuation = nil }
                loaded = true
                shortsGrid = page.isShortsGrid
            } catch {
                guard !Task.isCancelled, generation == current else { return }
                self.error = error.localizedDescription
            }
            if generation == current { busy = false }
        }
    }
    func cancel() { task?.cancel(); generation = UUID(); busy = false }
}
struct RemotePlaylistView: View {
    @StateObject private var model = RemotePlaylistModel()
    var body: some View {
        List {
            Section("Open public playlist") {
                TextField("YouTube playlist link or ID", text: $model.input).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Open playlist") { model.open() }.disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Opening connects to YouTube. Private lists and mixes are not supported. Only loaded videos are shown; unavailable entries may be omitted.").font(.footnote)
            }
            if model.shortsGrid { Text("YouTube returned a Shorts grid, which may stop at 100 videos. This may not be the complete playlist.").font(.footnote) }
            if let error = model.error { Text(error).foregroundStyle(.red) }
            ForEach(model.videos) { video in
                VStack(alignment: .leading) {
                    NavigationLink(video.title) { PlaybackView(video: video) }
                    PlaylistActions(video: video)
                }
            }
            if model.loaded && model.videos.isEmpty { Text("No available videos in this response.") }
            if model.busy { ProgressView("Loading playlist…") }
            else {
                if model.continuation != nil { Button("Load more") { model.load(more: true) } }
                if model.error != nil && model.canRetry { Button("Retry page") { model.load(more: model.continuation != nil) } }
            }
        }.navigationTitle(model.title).onDisappear { model.cancel() }
    }
}
