// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import FlowCore

@MainActor final class SubscriptionFeedModel: ObservableObject {
    @Published private(set) var report: SubscriptionFeedReport?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    private let service = SubscriptionFeedService()
    private var generation = UUID()
    private var task: Task<Void, Never>?
    func refresh(_ subscriptions: [LocalSubscription], force: Bool = false) async {
        task?.cancel()
        let current = UUID(); generation = current
        busy = true; error = nil
        let operation = Task { @MainActor in
            do {
                let result = try await service.refresh(subscriptions: subscriptions, force: force)
                guard !Task.isCancelled, current == generation else { return }
                report = result
            } catch {
                guard !Task.isCancelled, current == generation else { return }
                self.error = error.localizedDescription
            }
            if current == generation { busy = false }
        }
        task = operation
        await withTaskCancellationHandler(operation: { await operation.value }, onCancel: { operation.cancel() })
    }
    func cancelDisplay() { task?.cancel(); generation = UUID(); busy = false }

}

struct SubscriptionFeedView: View {
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var model = SubscriptionFeedModel()
    @State private var hideWatched = false
    @State private var shortsOnly = false
    private var subscriptionKey: String { library.snapshot.subscriptions.map(\.id).sorted().joined(separator: ",") }
    private var visible: [SubscriptionUpload] {
        let subscribed = Set(library.snapshot.subscriptions.map(\.id))
        let watched = Set(library.snapshot.history.map(\.videoID))
        return (model.report?.uploads ?? []).filter {
            subscribed.contains($0.channelID) && (!hideWatched || !watched.contains($0.id)) && (!shortsOnly || $0.isShort == true)
        }
    }
    var body: some View {
        List {
            Section {
                Text("Recent uploads from your saved channels via YouTube RSS. Each feed covers only its latest entries; this is not the full channel history. Refresh happens while this screen is open, not in the background.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Hide watched", isOn: $hideWatched)
                Toggle("Confirmed Shorts only", isOn: $shortsOnly)
                if shortsOnly { Text("RSS does not identify every Short, so this filter may omit some.").font(.caption) }
            }
            if library.snapshot.subscriptions.isEmpty { Text("Save a channel in Subscriptions to build your feed.") }
            if model.busy { ProgressView("Refreshing subscribed channels…") }
            if let error = model.error { Text(error).foregroundStyle(.red) }
            if let report = model.report {
                if !report.cachedChannelIDs.isEmpty { Text("Some channel results are cached. Pull to refresh to request fresh feeds.").font(.caption) }
                if !report.failures.isEmpty {
                    Section("Channels that could not refresh") {
                        ForEach(report.failures.keys.sorted(), id: \.self) { id in
                            if library.snapshot.subscriptions.contains(where: { $0.id == id }) {
                                Text("\(library.snapshot.subscriptions.first(where: { $0.id == id })?.name ?? id): \(report.failures[id] ?? "Refresh failed")").font(.caption)
                            }
                        }
                    }
                }
                if visible.isEmpty && !model.busy { Text("No uploads match the current feed and filters.") }
            }
            ForEach(visible) { upload in
                VStack(alignment: .leading) {
                    NavigationLink { PlaybackView(video: upload.video) } label: {
                        VStack(alignment: .leading) {
                            AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(upload.id)/hqdefault.jpg")) { image in
                                image.resizable().aspectRatio(contentMode: .fit)
                            } placeholder: { Rectangle().fill(.secondary.opacity(0.1)).aspectRatio(16 / 9, contentMode: .fit) }
                            Text(upload.video.title).font(.headline)
                            Text(upload.channelName).font(.caption).foregroundStyle(.secondary)
                            if let published = upload.publishedAt { Text(published, style: .date).font(.caption) }
                        }
                    }
                    HStack {
                        PlaylistActions(video: upload.video)
                        NavigationLink("Channel") { ChannelView(channelID: upload.channelID, name: upload.channelName) }
                    }.font(.caption)
                }
            }
        }.navigationTitle("Latest uploads")
            .task(id: subscriptionKey) { await model.refresh(library.snapshot.subscriptions) }
            .refreshable { await model.refresh(library.snapshot.subscriptions, force: true) }
            .onDisappear { model.cancelDisplay() }
    }
}
