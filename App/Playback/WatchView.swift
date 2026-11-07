// SPDX-License-Identifier: GPL-3.0-only
import FlowCore
import SwiftUI

struct WatchView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @EnvironmentObject private var library: LibraryStore
    @State private var showDescription = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                playerArea
            }
            .background(Color.black.ignoresSafeArea(edges: .top))
            if let video = player.current {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        info(video)
                        channelRow(video)
                        actions(video)
                        commentsCard
                        if !player.related.isEmpty {
                            ForEach(player.related) { VideoRow(video: $0) }
                        } else if player.details == nil {
                            ForEach(0..<4, id: \.self) { _ in SkeletonCard(compact: true) }
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 24)
                }
                .id(video.id)
            } else {
                Spacer()
            }
        }
        .background(Color(.systemBackground))
        .offset(y: dragOffset)
        .sheet(isPresented: Bindable(player).commentsPresented) {
            if let id = player.current?.id {
                NavigationStack { VideoCommentsView(videoID: id) }
                    .presentationDetents([.fraction(0.65), .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var header: some View {
        HStack {
            Button { player.expanded = false } label: {
                Image(systemName: "chevron.down").font(.body.weight(.semibold)).frame(width: 44, height: 36)
            }
            .accessibilityLabel("Minimize")
            Spacer()
            Button { player.close() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 36)
            }
            .accessibilityLabel("Close")
        }
        .foregroundStyle(.white)
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
        Button { withAnimation(.snappy) { showDescription.toggle() } } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(video.title).font(.title3.weight(.bold)).multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    let meta = [video.views.map(VideoItem.shortViews), video.published].compactMap { $0 }.joined(separator: " · ")
                    Text(meta).foregroundStyle(.secondary)
                    if description != nil { Text(showDescription ? "less" : "...more").fontWeight(.semibold) }
                }
                .font(.footnote)
                if showDescription, let description {
                    Text(description)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var description: String? {
        let text = player.details?.description ?? player.media?.description
        return text?.isEmpty == false ? text : nil
    }

    private func channelRow(_ video: VideoItem) -> some View {
        HStack(spacing: 10) {
            Button {
                guard let id = video.channelID else { return }
                player.expanded = false
                router.open(.channel(id: id, name: video.channel ?? ""))
            } label: {
                HStack(spacing: 10) {
                    ChannelAvatar(url: video.channelAvatar, name: video.channel, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(video.channel ?? " ").font(.subheadline.weight(.semibold)).lineLimit(1)
                        if let subs = player.details?.channel?.subscribers { Text(subs).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if let id = video.channelID {
                SubscribeButton(channelID: id, name: video.channel ?? "", avatar: video.channelAvatar)
            }
        }
    }

    private func actions(_ video: VideoItem) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let likes = player.details?.likes {
                    chipLabel(likes, "hand.thumbsup")
                }
                let saved = library.snapshot.playlists.first { $0.id == LocalPlaylist.watchLaterID }?.videoIDs.contains(video.id) ?? false
                chip(saved ? "Saved" : "Save", saved ? "bookmark.fill" : "bookmark") {
                    Task {
                        if saved { await library.perform(.removeFromPlaylist(videoID: video.id, playlistID: LocalPlaylist.watchLaterID)) }
                        else { await library.perform(.addToPlaylist(video: video.reference, playlistID: LocalPlaylist.watchLaterID)) }
                    }
                }
                ShareLink(item: video.watchURL) { chipLabel("Share", "arrowshape.turn.up.right") }
                chip("Audio", player.audioOnly ? "headphones.circle.fill" : "headphones") { player.setAudioOnly(!player.audioOnly) }
                if let media = player.media, !media.qualities.isEmpty {
                    Menu {
                        ForEach(media.qualities) { quality in
                            Button { player.select(quality: quality) } label: {
                                if quality == player.quality, !player.audioOnly { Label(quality.label, systemImage: "checkmark") } else { Text(quality.label) }
                            }
                        }
                    } label: { chipLabel(player.audioOnly ? "Quality" : (player.quality?.label ?? "Quality"), "slider.horizontal.3") }
                }
                if let next = player.upNext {
                    chip("Next", "forward.end") { player.play(next) }
                }
            }
        }
        .buttonStyle(.plain)
        .scrollClipDisabled()
    }

    private func chip(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, icon) }
    }

    private func chipLabel(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color(.secondarySystemFill), in: Capsule())
    }

    @ViewBuilder private var commentsCard: some View {
        if let comment = player.commentPreview {
            Button { player.commentsPresented = true } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Comments").font(.subheadline.weight(.bold))
                        if let count = player.commentCount?.components(separatedBy: " ").first { Text(count).font(.subheadline).foregroundStyle(.secondary) }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        ChannelAvatar(url: comment.avatar, name: comment.author, size: 24)
                        Text(comment.text).font(.footnote).lineLimit(2).multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
}

struct SubscribeButton: View {
    @EnvironmentObject private var library: LibraryStore
    let channelID: String
    let name: String
    var avatar: URL?
    var fullWidth = false

    var body: some View {
        let subscribed = library.isSubscribed(channelID)
        Button {
            library.toggleSubscription(id: channelID, name: name, avatar: avatar)
        } label: {
            Text(subscribed ? "Subscribed" : "Subscribe")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.horizontal, 16).padding(.vertical, fullWidth ? 11 : 9)
                .foregroundStyle(subscribed ? Color.primary : Color(.systemBackground))
                .background(subscribed ? Color(.secondarySystemFill) : Color.primary, in: Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: subscribed)
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
