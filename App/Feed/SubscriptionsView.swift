// SPDX-License-Identifier: GPL-3.0-only
import FlowCore
import SwiftUI

struct SubscriptionsView: View {
    @Environment(MetadataCache.self) private var cache
    @EnvironmentObject private var library: LibraryStore
    @State private var model = SubscriptionFeedModel()

    private var subscriptions: [LocalSubscription] {
        library.snapshot.subscriptions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if !subscriptions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(subscriptions) { channel in
                                NavigationLink(value: Route.channel(id: channel.id, name: channel.name)) {
                                    VStack(spacing: 6) {
                                        ChannelAvatar(url: channel.thumbnailURL, name: channel.name, size: 52)
                                        Text(channel.name).font(.caption2).lineLimit(1).frame(width: 64)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                if subscriptions.isEmpty, !library.loading {
                    Text("No subscriptions").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 80)
                } else if model.items.isEmpty, model.loading {
                    ForEach(0..<3, id: \.self) { _ in SkeletonCard() }
                }
                ForEach(model.items) { VideoCard(video: $0) }
            }
            .padding(.vertical, 8)
        }
        .refreshable { model.refresh(subscriptions, cache: cache, force: true) }
        .navigationTitle("Subscriptions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SubscriptionManagerView() } label: { Image(systemName: "list.bullet") }.accessibilityLabel("Manage")
            }
        }
        .onAppear { model.refresh(subscriptions, cache: cache) }
        .onChange(of: library.snapshot.subscriptions.map(\.id)) { model.refresh(subscriptions, cache: cache) }
    }
}

struct SubscriptionManagerView: View {
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        List {
            Section {
                NavigationLink("Import or export") { SubscriptionTransferView() }
                NavigationLink("Import Google Takeout") { TakeoutImportView() }
            }
            Section {
                ForEach(library.snapshot.subscriptions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { channel in
                    NavigationLink(value: Route.channel(id: channel.id, name: channel.name)) {
                        HStack { ChannelAvatar(url: channel.thumbnailURL, name: channel.name, size: 32); Text(channel.name) }
                    }
                    .swipeActions { Button("Unsubscribe", role: .destructive) { Task { await library.perform(.unsubscribe(channel.id)) } } }
                }
            }
        }
        .navigationTitle("Channels")
    }
}
