// SPDX-License-Identifier: GPL-3.0-only
import FlowCore
import SwiftUI

@MainActor @Observable final class ChannelModel {
    let channelID: String
    private(set) var title: String
    private(set) var header: ChannelHeader?
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
                if let header = page.header { self.header = header }
                if !page.tabs.isEmpty { self.tabs = page.tabs.filter { ["Videos", "Live"].contains($0.title) } }
                let avatar = self.header?.avatar
                let new = page.feed.items.map { item -> VideoItem in
                    var item = item
                    item.channel = item.channel ?? page.title ?? fallback
                    item.channelID = item.channelID ?? id
                    item.channelAvatar = item.channelAvatar ?? avatar
                    return item
                }.filter { item in !item.isShort && !self.items.contains { $0.id == item.id } }
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

    func select(_ params: String?, cache: MetadataCache) {
        guard params != selected else { return }
        selected = params
        load(cache: cache)
    }
}

struct ChannelView: View {
    @Environment(MetadataCache.self) private var cache
    @State private var model: ChannelModel
    @State private var expandedAbout = false

    init(channelID: String, name: String) { _model = State(initialValue: ChannelModel(channelID: channelID, title: name)) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                header
                Section {
                    ForEach(model.items) { video in
                        VideoCard(video: video)
                            .onAppear { if video.id == model.items.last?.id { model.load(more: true, cache: cache) } }
                    }
                    if model.loading {
                        if model.items.isEmpty { ForEach(0..<2, id: \.self) { _ in SkeletonCard() } } else { ProgressView().frame(maxWidth: .infinity) }
                    } else if let error = model.error {
                        ErrorRow(message: error) { model.load(cache: cache) }
                    } else if model.items.isEmpty {
                        Text("No videos").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 40)
                    }
                } header: {
                    if model.tabs.count > 1 { tabBar }
                }
            }
            .padding(.bottom, 12)
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.items.isEmpty { model.load(cache: cache) } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let banner = model.header?.banner {
                Color(.secondarySystemFill)
                    .aspectRatio(6.2, contentMode: .fit)
                    .overlay { AsyncImage(url: banner) { $0.image?.resizable().scaledToFill() } }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 12)
            }
            HStack(alignment: .center, spacing: 14) {
                ChannelAvatar(url: model.header?.avatar, name: model.title, size: 72)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title).font(.title2.weight(.bold)).lineLimit(2)
                    if let handle = model.header?.handle { Text(handle).font(.footnote.weight(.medium)) }
                    let stats = [model.header?.subscribers, model.header?.videoCount].compactMap { $0 }.joined(separator: " · ")
                    if !stats.isEmpty { Text(stats).font(.footnote).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            if let about = model.header?.description, !about.isEmpty {
                Button { withAnimation(.snappy) { expandedAbout.toggle() } } label: {
                    Text(about).font(.footnote).foregroundStyle(.secondary).lineLimit(expandedAbout ? nil : 2).multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            }
            SubscribeButton(channelID: model.channelID, name: model.title, avatar: model.header?.avatar, fullWidth: true)
                .padding(.horizontal, 12)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 24) {
            ForEach(model.tabs) { tab in
                let selected = tab.params == model.selected
                Button { model.select(tab.params, cache: cache) } label: {
                    VStack(spacing: 8) {
                        Text(tab.title).font(.subheadline.weight(.semibold)).foregroundStyle(selected ? .primary : .secondary)
                        Rectangle().fill(selected ? Color.primary : .clear).frame(height: 2)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.top, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}
