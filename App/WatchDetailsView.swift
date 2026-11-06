// SPDX-License-Identifier: GPL-3.0-only
// New read-only watch details UI, 2026-11-06.
import SwiftUI
import FlowCore

@MainActor final class WatchDetailsModel: ObservableObject {
    @Published private(set) var details: WatchDetails?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let client = WatchDetailsClient()
    func load(_ videoID: String) {
        cancel(); let current = UUID(); generation = current; busy = true; error = nil
        task = Task {
            do {
                let details = try await client.details(videoID: videoID)
                guard !Task.isCancelled, generation == current else { return }
                self.details = details
            } catch {
                guard !Task.isCancelled, generation == current else { return }
                self.error = error.localizedDescription
            }
            if generation == current { busy = false }
        }
    }
    func cancel() { task?.cancel(); generation = UUID(); busy = false }
}
struct WatchDetailsView: View {
    let video: VideoReference
    @StateObject private var model = WatchDetailsModel()
    var body: some View {
        List {
            Text("Details and related videos are supplied by YouTube, not FlowNeuro. Opening connects to YouTube. Descriptions are plain text; links and timestamp actions are not supported.").font(.footnote).foregroundStyle(.secondary)
            if let details = model.details {
                Section("Video") {
                    Text(details.title ?? video.title).font(.headline)
                    if let views = details.views { Text(views) }
                    if let published = details.published { Text(published) }
                    ForEach(Array(details.facts.enumerated()), id: \.offset) { _, fact in Text("\(fact.value) \(fact.label)") }
                }
                if let channel = details.channel {
                    Section("Channel") {
                        if let id = channel.id { NavigationLink(channel.name) { ChannelView(channelID: id, name: channel.name) } }
                        else { Text(channel.name) }
                        if let count = channel.subscribers { Text(count).font(.caption) }
                    }
                }
                Section("Description") { Text(details.description ?? "No supported description was returned.").textSelection(.enabled) }
                Section("Related videos · first page") {
                    if let notice = details.relatedNotice { Text(notice).font(.footnote) }
                    ForEach(details.related) { related in
                        VStack(alignment: .leading) {
                            NavigationLink(related.title) { PlaybackView(video: related) }
                            PlaylistActions(video: related)
                        }
                    }
                    if details.related.isEmpty && details.relatedNotice == nil { Text("No related videos in this response.") }
                }
            }
            if model.busy { ProgressView("Loading video details…") }
            if let error = model.error { Text(error).foregroundStyle(.red); Button("Retry") { model.load(video.id) } }
        }.navigationTitle("Video details")
            .task { if model.details == nil { model.load(video.id) } }
            .onDisappear { model.cancel() }
    }
}
