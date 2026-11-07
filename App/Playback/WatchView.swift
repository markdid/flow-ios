// SPDX-License-Identifier: GPL-3.0-only
import FlowCore
import SwiftUI

struct WatchView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @EnvironmentObject private var library: LibraryStore
    @State private var showDescription = false
    @State private var showComments = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            playerArea
            if let video = player.current {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        info(video)
                        channelRow(video)
                        actions(video)
                        descriptionCard
                        if !player.related.isEmpty {
                            ForEach(player.related) { VideoRow(video: $0) }
                        } else if player.details == nil {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 12)
                }
            } else {
                Spacer()
            }
        }
        .background(Color(.systemBackground))
        .offset(y: dragOffset)
        .sheet(isPresented: $showComments) {
            if let id = player.current?.id {
                NavigationStack { VideoCommentsView(videoID: id) }.presentationDetents([.medium, .large])
            }
        }
    }

    private var header: some View {
        HStack {
            Button { player.expanded = false } label: {
                Image(systemName: "chevron.down").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Minimize")
            Spacer()
            Button { player.close() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .gesture(dismissDrag)
    }

    private var playerArea: some View {
        ZStack {
            Color.black
            PlayerSurface(player: player.player)
            switch player.status {
            case .loading:
                ProgressView().tint(.white).controlSize(.large)
            case .failed(let message):
                VStack(spacing: 12) {
                    Text(message).font(.subheadline).foregroundStyle(.white).multilineTextAlignment(.center)
                    HStack {
                        Button("Retry") { player.reload() }.buttonStyle(.borderedProminent)
                        if let url = player.current?.watchURL { Link("YouTube", destination: url).buttonStyle(.bordered).tint(.white) }
                    }
                }
                .padding()
            default:
                EmptyView()
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
    }

    private var dismissDrag: some Gesture {
        DragGesture()
            .onChanged { dragOffset = max(0, $0.translation.height) }
            .onEnded { value in
                if value.translation.height > 120 { player.expanded = false }
                withAnimation(.snappy) { dragOffset = 0 }
            }
    }

    private func info(_ video: VideoItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(video.title).font(.headline).textSelection(.enabled)
            let meta = [video.views.map(VideoItem.shortViews), video.published].compactMap { $0 }.joined(separator: " · ")
            if !meta.isEmpty { Text(meta).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func channelRow(_ video: VideoItem) -> some View {
        HStack(spacing: 10) {
            Button {
                guard let id = video.channelID else { return }
                player.expanded = false
                router.open(.channel(id: id, name: video.channel ?? ""))
            } label: {
                HStack(spacing: 10) {
                    ChannelAvatar(name: video.channel)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(video.channel ?? " ").font(.subheadline.weight(.semibold)).lineLimit(1)
                        if let subs = player.details?.channel?.subscribers { Text(subs).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if let id = video.channelID {
                let subscribed = library.isSubscribed(id)
                Button(subscribed ? "Subscribed" : "Subscribe") { library.toggleSubscription(id: id, name: video.channel ?? "") }
                    .buttonStyle(.borderedProminent)
                    .tint(subscribed ? Color(.systemGray4) : .primary)
                    .foregroundStyle(subscribed ? Color.primary : Color(.systemBackground))
                    .clipShape(Capsule())
            }
        }
    }

    private func actions(_ video: VideoItem) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let saved = library.snapshot.playlists.first { $0.id == LocalPlaylist.watchLaterID }?.videoIDs.contains(video.id) ?? false
                chip(saved ? "Saved" : "Watch later", saved ? "clock.fill" : "clock") {
                    Task {
                        if saved { await library.perform(.removeFromPlaylist(videoID: video.id, playlistID: LocalPlaylist.watchLaterID)) }
                        else { await library.perform(.addToPlaylist(video: video.reference, playlistID: LocalPlaylist.watchLaterID)) }
                    }
                }
                chip("Audio only", player.audioOnly ? "headphones.circle.fill" : "headphones") { player.setAudioOnly(!player.audioOnly) }
                if let media = player.media, !media.qualities.isEmpty {
                    Menu {
                        ForEach(media.qualities) { quality in
                            Button { player.select(quality: quality) } label: {
                                if quality == player.quality, !player.audioOnly { Label(quality.label, systemImage: "checkmark") } else { Text(quality.label) }
                            }
                        }
                    } label: { chipLabel(player.audioOnly ? "Quality" : (player.quality?.label ?? "Quality"), "slider.horizontal.3") }
                }
                chip("Comments", "text.bubble") { showComments = true }
                ShareLink(item: video.watchURL) { chipLabel("Share", "square.and.arrow.up") }
                if let next = player.upNext {
                    chip("Next", "forward.end") { player.play(next) }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func chip(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, icon) }
    }

    private func chipLabel(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(.secondarySystemFill), in: Capsule())
    }

    @ViewBuilder private var descriptionCard: some View {
        let text = player.details?.description ?? player.media?.description
        if let text, !text.isEmpty {
            Button { withAnimation(.snappy) { showDescription.toggle() } } label: {
                Text(text)
                    .font(.footnote)
                    .lineLimit(showDescription ? nil : 3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
}

struct MiniPlayer: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        if let video = player.current {
            HStack(spacing: 10) {
                PlayerLayerView(player: player.player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text(video.title).font(.footnote.weight(.semibold)).lineLimit(1)
                    if let channel = video.channel { Text(channel).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 4)
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 36, height: 36)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.body).frame(width: 32, height: 36)
                }
                .disabled(player.upNext == nil)
                .accessibilityLabel("Next")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .onTapGesture { player.expanded = true }
        }
    }
}
