// SPDX-License-Identifier: GPL-3.0-only
import FlowCore
import SwiftUI

@MainActor @Observable final class ChannelModel {
    let channelID: String
    private(set) var title: String
    private(set) var tabs: [ChannelTab] = []
    private(set) var selected: String? = ChannelUploads.videosTab
    private(set) var items: [VideoItem] = []
    private(set) var continuation: String?
    private(set) var loading = false
    private(set) var error: String?
    private var task: Task<Void, Never>?

    init(channelID: String, title: String) { self.channelID = channelID; self.title = title }

    func load(more: Bool = false, cache: MetadataCache) {
        guard !(more && continuation == nil), !(more && loading) else { return }
        if !more { task?.cancel(); items = []; continuation = nil }
        loading = true; error = nil
        let params = selected, token = more ? continuation : nil, id = channelID, fallback = title
        task = Task {
            do {
                let page = try await ChannelBrowseClient().browse(channelID: id, params: token == nil ? params : nil, continuation: token)
                guard !Task.isCancelled else { return }
                if let name = page.title, !name.isEmpty { self.title = name }
                if !page.tabs.isEmpty { self.tabs = page.tabs.filter { ["Videos", "Shorts", "Live", "Home"].contains($0.title) } }
                let new = page.feed.items.map { item -> VideoItem in
                    var item = item
                    item.channel = item.channel ?? page.title ?? fallback
                    item.channelID = item.channelID ?? id
                    return item
                }.filter { item in !self.items.contains { $0.id == item.id } }
                cache.remember(new)
                self.items += new
                self.continuation = page.feed.continuation
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            self.loading = false
        }
    }

    func select(_ tab: ChannelTab, cache: MetadataCache) {
        selected = tab.params
        load(cache: cache)
    }
}

struct ChannelView: View {
    @Environment(MetadataCache.self) private var cache
    @EnvironmentObject private var library: LibraryStore
    @State private var model: ChannelModel

    init(channelID: String, name: String) { _model = State(initialValue: ChannelModel(channelID: channelID, title: name)) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                if !model.tabs.isEmpty {
                    Picker("Tab", selection: Binding(get: { model.selected }, set: { value in
                        if let tab = model.tabs.first(where: { $0.params == value }) { model.select(tab, cache: cache) }
                    })) {
                        ForEach(model.tabs) { Text($0.title).tag(Optional($0.params)) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                }
                ForEach(model.items) { video in
                    VideoRow(video: video)
                        .padding(.horizontal, 12)
                        .onAppear { if video.id == model.items.last?.id { model.load(more: true, cache: cache) } }
                }
                if model.loading { ProgressView().frame(maxWidth: .infinity) }
                else if let error = model.error { ErrorRow(message: error) { model.load(cache: cache) } }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.items.isEmpty { model.load(cache: cache) } }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ChannelAvatar(name: model.title, size: 64)
            VStack(alignment: .leading, spacing: 8) {
                Text(model.title).font(.title2.weight(.bold)).lineLimit(2)
                let subscribed = library.isSubscribed(model.channelID)
                Button(subscribed ? "Subscribed" : "Subscribe") { library.toggleSubscription(id: model.channelID, name: model.title) }
                    .buttonStyle(.borderedProminent)
                    .tint(subscribed ? Color(.systemGray4) : .primary)
                    .foregroundStyle(subscribed ? Color.primary : Color(.systemBackground))
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 12)
    }
}
