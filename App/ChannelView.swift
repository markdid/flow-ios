// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import FlowCore

@MainActor final class ChannelModel: ObservableObject {
    @Published private(set) var title: String
    @Published private(set) var tabs: [ChannelTab] = []
    @Published private(set) var videos: [VideoReference] = []
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var continuation: String?
    @Published private(set) var notice: String?
    @Published private(set) var selectedTabID: Int?
    let channelID: String
    private var params: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let client = ChannelBrowseClient()
    init(channelID: String, name: String) { self.channelID = channelID; self.title = name }
    func select(_ tab: ChannelTab) { selectedTabID = tab.id; params = tab.params; load() }
    func load(more: Bool = false) {
        if more && (busy || continuation == nil) { return }
        task?.cancel()
        let current = UUID(); generation = current
        let token = more ? continuation : nil
        if !more { videos = []; continuation = nil }
        busy = true; error = nil; notice = nil
        let selectedParams = params
        task = Task {
            do {
                let page = try await client.browse(channelID: channelID, params: selectedParams, continuation: token)
                guard !Task.isCancelled, generation == current else { return }
                if let title = page.title { self.title = title }
                if !page.tabs.isEmpty {
                    tabs = page.tabs
                    if selectedTabID == nil { selectedTabID = page.tabs.first(where: { $0.selected })?.id }
                }
                var seen = Set(videos.map(\.id))
                videos.append(contentsOf: page.feed.videos.filter { seen.insert($0.id).inserted })
                continuation = page.feed.continuation == token ? nil : page.feed.continuation
                notice = page.notice
            } catch {
                guard !Task.isCancelled, generation == current else { return }
                self.error = error.localizedDescription
            }
            if generation == current { busy = false }
        }
    }
    func cancel() { task?.cancel(); generation = UUID(); busy = false }
}

struct ChannelView: View {
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var model: ChannelModel
    init(channelID: String, name: String) {
        _model = StateObject(wrappedValue: ChannelModel(channelID: channelID, name: name))
    }
    private var subscribed: Bool { library.snapshot.subscriptions.contains { $0.id == model.channelID } }
    var body: some View {
        List {
            Button(subscribed ? "Unsubscribe" : "Subscribe locally") {
                Task {
                    if subscribed { _ = await library.perform(.unsubscribe(model.channelID)) }
                    else { _ = await library.perform(.subscribe(LocalSubscription(id: model.channelID, name: model.title))) }
                }
            }
            if !model.tabs.isEmpty {
                Menu("Channel tabs") {
                    ForEach(model.tabs) { tab in
                        Button(tab.title) { model.select(tab) }.disabled(tab.id == model.selectedTabID || (tab.params == nil && tab.id != 0))
                    }
                }
            }
            if let notice = model.notice { Text(notice).font(.footnote) }
            if let error = model.error {
                Text(error).foregroundStyle(.red)
                Button("Retry") { model.load() }
            }
            ForEach(model.videos) { video in
                VStack(alignment: .leading) {
                    NavigationLink(video.title) { PlaybackView(video: video) }
                    PlaylistActions(video: video)
                }
            }
            if model.busy { ProgressView("Loading channel…") }
            if model.continuation != nil { Button("Load more") { model.load(more: true) }.disabled(model.busy) }
        }.navigationTitle(model.title)
            .task { if model.videos.isEmpty { model.load() } }
            .onDisappear { model.cancel() }
    }
}
