// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AVKit
import FlowCore

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @State private var pendingDelete: DownloadedMedia?
    var body: some View {
        List {
            Section {
                Text("Direct MP4 video and AAC audio only. Start a download from the native player’s Download menu. Keep the app open: resumable/background downloads and HLS/DASH downloads are not yet implemented. Files are kept in app storage and may be included in device backups.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let title = downloads.runningTitle {
                    ProgressView("Downloading \(title)…")
                    Button("Cancel download", role: .cancel) { downloads.cancel() }
                }
                if let message = downloads.message { Text(message).font(.footnote) }
                if let error = downloads.error { Text(error).foregroundStyle(.red) }
                if downloads.loading { ProgressView("Loading downloads…") }
            }
            ForEach(downloads.records) { record in
                NavigationLink { OfflinePlayerView(record: record) } label: {
                    VStack(alignment: .leading) {
                        Text(record.video.title)
                        Text("\(record.kind == .audio ? "Audio" : "Video") · \(ByteCountFormatter.string(fromByteCount: record.byteCount, countStyle: .file))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.swipeActions { Button("Delete", role: .destructive) { pendingDelete = record } }
            }
        }.navigationTitle("Downloads")
            .confirmationDialog("Delete this downloaded file?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { record in
                Button("Delete download", role: .destructive) { Task { await downloads.remove(record) }; pendingDelete = nil }
            } message: { record in Text(record.video.title) }
    }
}

struct OfflinePlayerView: View {
    @EnvironmentObject private var downloads: DownloadManager
    let record: DownloadedMedia
    @State private var player: AVPlayer?
    @State private var error: String?
    var body: some View {
        VStack {
            if let player { VideoPlayer(player: player) }
            else if let error { Text(error).foregroundStyle(.red).padding() }
            else { ProgressView("Opening downloaded file…") }
        }.navigationTitle(record.video.title).navigationBarTitleDisplayMode(.inline)
            .task {
                do {
                    let url = try await downloads.localURL(record)
                    try Task.checkCancellation()
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                    try AVAudioSession.sharedInstance().setActive(true)
                    let player = AVPlayer(url: url)
                    self.player = player; player.play()
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
            .onDisappear {
                player?.pause(); player = nil
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
    }
}
