// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct HomeView: View {
    @Environment(MetadataCache.self) private var cache
    @EnvironmentObject private var library: LibraryStore
    @State private var model = HomeFeedModel()
    @State private var loadedOnce = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if !model.topics.isEmpty { topicBar }
                if model.topic == nil, !model.continueWatching.isEmpty { continueShelf }
                if model.items.isEmpty, model.loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                } else if model.items.isEmpty, let error = model.error {
                    ErrorRow(message: error) { reload() }
                }
                ForEach(model.items) { VideoCard(video: $0) }
            }
            .padding(.bottom, 20)
        }
        .refreshable { reload(); while model.loading { try? await Task.sleep(for: .milliseconds(200)) } }
        .navigationTitle("Flow")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.search("")) { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search")
            }
        }
        .task {
            guard !loadedOnce else { return }
            while library.loading { try? await Task.sleep(for: .milliseconds(100)) }
            loadedOnce = true
            reload()
        }
    }

    private func reload() { model.refresh(library: library, cache: cache) }

    private var topicBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                topicChip("All", selected: model.topic == nil) { model.topic = nil; reload() }
                ForEach(model.topics, id: \.self) { topic in
                    topicChip(topic.capitalized, selected: model.topic == topic) { model.topic = topic; reload() }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func topicChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.footnote.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(selected ? Color(.systemBackground) : .primary)
                .background(selected ? Color.primary : Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var continueShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Continue watching").font(.title3.weight(.bold)).padding(.horizontal, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(model.continueWatching) { ShelfCard(video: $0) }
                }
                .padding(.horizontal, 12)
            }
        }
    }
}

struct ShelfCard: View {
    @Environment(PlayerModel.self) private var player
    @EnvironmentObject private var library: LibraryStore
    let video: VideoItem
    var width: CGFloat = 220

    var body: some View {
        Button { player.play(video) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Thumbnail(video: video, progress: library.progress(video.id))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(video.title).font(.footnote.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                if let channel = video.channel { Text(channel).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu { VideoMenu(video: video) }
    }
}
