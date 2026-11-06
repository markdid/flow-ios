// SPDX-License-Identifier: GPL-3.0-only
// New iOS playback UI, 2026-11-06. Native playback is experimental.
import SwiftUI
import AVKit
import FlowCore

struct NativePlayerView: View {
    let video: VideoReference
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var watchSession: WatchSession?
    @State private var visible = false
    @StateObject private var playback = NativePlaybackController()
    @StateObject private var sponsorBlock = SponsorBlockModel()
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VideoPlayer(player: playback.player).aspectRatio(16 / 9, contentMode: .fit)
                if playback.loading { ProgressView("Resolving native stream…") }
                if let notice = playback.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                if let error = playback.error {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                    Button("Retry native playback") { playback.retry() }
                }
                if playback.selectedSource != nil {
                    HStack {
                        Button { playback.previous() } label: { Image(systemName: "backward.end.fill") }.accessibilityLabel("Previous")
                        Button { playback.seek(to: playback.position - 10) } label: { Image(systemName: "gobackward.10") }.accessibilityLabel("Back ten seconds")
                        Button { playback.toggle() } label: { Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill") }.accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                        Button { playback.seek(to: playback.position + 10) } label: { Image(systemName: "goforward.10") }.accessibilityLabel("Forward ten seconds")
                        Button { playback.next() } label: { Image(systemName: "forward.end.fill") }.accessibilityLabel("Next")
                    }.font(.title2).buttonStyle(.bordered)
                    HStack {
                        Menu("Stream") {
                            ForEach(playback.sources) { source in Button(source.label) { playback.select(source) } }
                        }
                        Menu("Speed \(playback.rate, specifier: "%.2g")×") {
                            ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) { value in
                                Button("\(value, specifier: "%.2g")×") { playback.setRate(value) }
                            }
                        }
                        Menu("Repeat: \(playback.queue.repeatMode.rawValue)") {
                            ForEach(PlaybackQueue.RepeatMode.allCases, id: \.self) { mode in
                                Button(mode.rawValue.capitalized) { playback.setRepeat(mode) }
                            }
                        }
                    }
                }
                if playback.sources.contains(where: { $0.kind != .hls }) {
                    Menu("Download") {
                        ForEach(playback.sources.filter { $0.kind != .hls }) { source in
                            Button(source.label) { downloads.download(video: video, source: source) }
                        }
                    }.disabled(downloads.runningTitle != nil || downloads.loading)
                    Text("Saves a direct MP4/AAC file for offline playback. Only download content you are allowed to keep. Keep the app open; files over 1 GB are rejected after transfer.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                NavigationLink("View downloads") { DownloadsView() }
                NavigationLink("Video details and related") { WatchDetailsView(video: video) }
                NavigationLink("Read comments") { VideoCommentsView(videoID: video.id) }
                SponsorBlockControls(model: sponsorBlock, videoID: video.id, position: playback.position, duration: playback.duration) { playback.seek(to: $0) }
                Text("Native playback currently supports direct HLS, muxed MP4 and AAC audio only. Many YouTube videos require extraction features not yet ported to iOS.")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink("Use embedded YouTube player") { PlaybackView(video: video) }
                Link("Open on YouTube", destination: video.watchURL)
            }.padding()
        }
        .navigationTitle(video.title).navigationBarTitleDisplayMode(.inline)
        .task {
            visible = true
            let session = await library.beginWatch(videoID: video.id)
            guard !Task.isCancelled, visible else { return }
            watchSession = session
            let prior = library.snapshot.history.first { $0.videoID == video.id }
            playback.start(videos: [video], resumeAt: prior?.position ?? 0)
            playback.onCheckpoint = { current, position, duration in
                guard let session, current.id == video.id else { return }
                let entry = LocalWatchEntry(videoID: current.id, position: position, duration: duration, watchedAt: Date())
                Task { _ = await library.perform(.recordWatch(video: current, entry: entry, session: session)) }
            }
        }
        .onChange(of: playback.position) { position in
            guard visible else { return }
            if let target = sponsorBlock.update(position: position, isPlaying: playback.isPlaying, duration: playback.duration) { playback.seek(to: target) }
        }
        .onChange(of: playback.duration) { duration in
            guard visible else { return }
            if let target = sponsorBlock.update(position: playback.position, isPlaying: playback.isPlaying, duration: duration) { playback.seek(to: target) }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { playback.checkpoint() }
        }
        .onDisappear {
            visible = false
            sponsorBlock.disable()
            playback.stop()
            playback.onCheckpoint = nil
            watchSession = nil
        }
    }
}
