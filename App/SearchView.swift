// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import FlowCore

@MainActor final class SearchModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var videos: [VideoReference] = []
    @Published private(set) var presentation: [String: VideoPresentation] = [:]
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var continuation: String?
    @Published private(set) var filterGroups: [SearchFilterGroup] = []
    @Published private(set) var selectedFilter: String?
    @Published private(set) var searched = false
    private var params: String?
    private var activeQuery = ""
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let client = VideoSearchClient()

    func search(more: Bool = false) {
        if more && (busy || continuation == nil) { return }
        task?.cancel()
        let current = UUID()
        generation = current
        let token = more ? continuation : nil
        if !more { activeQuery = query; videos = []; presentation = [:]; continuation = nil }
        let submittedQuery = activeQuery
        let submittedParams = params
        busy = true
        searched = true
        error = nil
        task = Task {
            do {
                let page = try await client.search(query: submittedQuery, continuation: token, params: submittedParams)
                guard !Task.isCancelled, generation == current else { return }
                var seen = Set(videos.map(\.id))
                videos.append(contentsOf: page.videos.filter { seen.insert($0.id).inserted })
                presentation.merge(page.presentation) { _, newer in newer }
                continuation = page.continuation == token ? nil : page.continuation
                if !more { filterGroups = page.filterGroups }
            } catch {
                guard !Task.isCancelled, generation == current else { return }
                self.error = error.localizedDescription
            }
            if generation == current { busy = false }
        }
    }
    func chooseFilter(_ option: SearchFilterOption?) {
        params = option?.params
        selectedFilter = option?.label
        search()
    }
    func cancel() { task?.cancel(); generation = UUID(); busy = false }
}

struct SearchView: View {
    @StateObject private var model = SearchModel()
    @EnvironmentObject private var library: LibraryStore
    @State private var savedTitle: String?
    @State private var showingFilters = false
    @State private var saveError: String?
    var body: some View {
        List {
            Section {
                Text("Experimental video search. Queries are sent to YouTube. Video and basic Shorts results are supported. Music, channel and playlist result pages are not yet ported.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let label = model.selectedFilter { Text("Filter: \(label)").font(.footnote) }
            if let error = saveError { Text(error).foregroundStyle(.red) }
            if let error = model.error { Text(error).foregroundStyle(.red) }
            ForEach(model.videos) { video in
                VStack(alignment: .leading) {
                    NavigationLink { PlaybackView(video: video) } label: {
                        VStack(alignment: .leading) {
                            if let details = model.presentation[video.id] {
                                AsyncImage(url: details.thumbnailURL) { image in
                                    image.resizable().aspectRatio(contentMode: .fit)
                                } placeholder: { Rectangle().fill(.secondary.opacity(0.1)).aspectRatio(16 / 9, contentMode: .fit) }
                                Text(video.title).font(.headline)
                                Text([details.channel, details.duration, details.views, details.published, details.isShort ? "Shorts" : nil].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            } else { Text(video.title) }
                        }
                    }
                    Button("Save to library") {
                        Task {
                            if await library.add(video) { savedTitle = video.title }
                            else { saveError = library.error ?? "Could not save video." }
                        }
                    }.buttonStyle(.borderless)
                    PlaylistActions(video: video)
                }
            }
            if model.searched && !model.busy && model.error == nil && model.videos.isEmpty && model.continuation == nil { Text("No video results found.") }
            if model.busy { ProgressView("Searching…") }
            if model.continuation != nil { Button("Load more") { model.search(more: true) }.disabled(model.busy) }
        }
        .navigationTitle("Search")
        .toolbar { Button("Filters") { showingFilters = true }.disabled(model.filterGroups.isEmpty) }
        .sheet(isPresented: $showingFilters) {
            NavigationStack {
                List {
                    Button("Clear filters") { showingFilters = false; model.chooseFilter(nil) }
                    ForEach(Array(model.filterGroups.enumerated()), id: \.offset) { _, group in
                        Section(group.title) {
                            ForEach(Array(group.options.enumerated()), id: \.offset) { _, option in
                                Button {
                                    showingFilters = false
                                    model.chooseFilter(option)
                                } label: {
                                    HStack {
                                        Text(option.label)
                                        if option.selected { Image(systemName: "checkmark") }
                                    }
                                }.disabled(option.params == nil || option.selected)
                            }
                        }
                    }
                }.navigationTitle("Search filters")
                    .toolbar { Button("Close") { showingFilters = false } }
            }
        }
        .searchable(text: $model.query, prompt: "Search YouTube videos")
        .onSubmit(of: .search) { model.search() }
        .onDisappear { model.cancel() }
        .alert("Saved to library", isPresented: Binding(get: { savedTitle != nil }, set: { if !$0 { savedTitle = nil } })) {
            Button("OK") { savedTitle = nil }
        } message: { Text(savedTitle ?? "") }
    }
}
