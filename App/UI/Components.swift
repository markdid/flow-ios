// SPDX-License-Identifier: GPL-3.0-only
import FlowCore
import Observation
import SwiftUI

enum Route: Hashable {
    case channel(id: String, name: String)
    case playlist(id: String)
    case history
    case search(String)
}

enum AppTab: Hashable { case home, subscriptions, library }

@MainActor @Observable final class Router {
    var tab: AppTab = .home
    var home: [Route] = []
    var subscriptions: [Route] = []
    var library: [Route] = []

    func open(_ route: Route) {
        switch tab {
        case .home: home.append(route)
        case .subscriptions: subscriptions.append(route)
        case .library: library.append(route)
        }
    }
}

struct Thumbnail: View {
    let video: VideoItem
    var progress: Double? = nil

    var body: some View {
        Color(.secondarySystemFill)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: video.thumbnail, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if video.isLive {
                    Text("LIVE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.red, in: RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                } else if let duration = video.duration {
                    Text(duration)
                        .font(.caption2.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
            }
            .overlay(alignment: .bottom) {
                if let progress, progress > 0.01 {
                    GeometryReader { proxy in
                        Rectangle().fill(.red).frame(width: proxy.size.width * progress, height: 3)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            .clipped()
    }
}

struct ChannelAvatar: View {
    var url: URL? = nil
    let name: String?
    var size: CGFloat = 36
    var body: some View {
        Circle().fill(Color(.tertiarySystemFill))
            .frame(width: size, height: size)
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { initial }
                    }
                } else { initial }
            }
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
    private var initial: some View {
        Text(String((name ?? "?").trimmingCharacters(in: CharacterSet(charactersIn: "@")).prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.secondary)
    }
}

/// Grey placeholder shown while a feed loads.
struct SkeletonCard: View {
    var compact = false
    var body: some View {
        if compact {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemFill)).aspectRatio(16 / 9, contentMode: .fit).frame(width: 160)
                VStack(alignment: .leading, spacing: 6) {
                    bar(width: nil); bar(width: 100); bar(width: 70)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Rectangle().fill(Color(.secondarySystemFill)).aspectRatio(16 / 9, contentMode: .fit)
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(Color(.secondarySystemFill)).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 6) { bar(width: nil); bar(width: 180) }
                }
                .padding(.horizontal, 12)
            }
        }
    }
    private func bar(width: CGFloat?) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(Color(.secondarySystemFill)).frame(width: width, height: 12).frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// Full-width feed card, like Flow's home feed.
struct VideoCard: View {
    @Environment(PlayerModel.self) private var player
    @EnvironmentObject private var library: LibraryStore
    let video: VideoItem

    var body: some View {
        Button { player.play(video) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Thumbnail(video: video, progress: library.progress(video.id))
                HStack(alignment: .top, spacing: 12) {
                    channelButton
                    VStack(alignment: .leading, spacing: 3) {
                        Text(video.title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        Text(video.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { VideoMenu(video: video) }
    }

    @Environment(Router.self) private var router
    @ViewBuilder private var channelButton: some View {
        if let id = video.channelID {
            Button { router.open(.channel(id: id, name: video.channel ?? "")) } label: {
                ChannelAvatar(url: video.channelAvatar, name: video.channel)
            }
            .buttonStyle(.plain)
        } else {
            ChannelAvatar(url: video.channelAvatar, name: video.channel)
        }
    }
}

/// Compact row for related videos, search and lists.
struct VideoRow: View {
    @Environment(PlayerModel.self) private var player
    @EnvironmentObject private var library: LibraryStore
    let video: VideoItem

    var body: some View {
        Button { player.play(video) } label: {
            HStack(alignment: .top, spacing: 10) {
                Thumbnail(video: video, progress: library.progress(video.id))
                    .frame(width: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title).font(.subheadline.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
                    if let channel = video.channel { Text(channel).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    let meta = [video.views.map(VideoItem.shortViews), video.published].compactMap { $0 }.joined(separator: " · ")
                    if !meta.isEmpty { Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { VideoMenu(video: video) }
    }
}

struct VideoMenu: View {
    @Environment(Router.self) private var router
    @Environment(PlayerModel.self) private var player
    @EnvironmentObject private var library: LibraryStore
    let video: VideoItem

    var body: some View {
        Button { player.play(video) } label: { Label("Play", systemImage: "play") }
        Button { Task { await library.perform(.addToPlaylist(video: video.reference, playlistID: LocalPlaylist.watchLaterID)) } } label: {
            Label("Watch later", systemImage: "clock")
        }
        let playlists = library.snapshot.playlists.filter { !$0.isBuiltIn }
        if !playlists.isEmpty {
            Menu {
                ForEach(playlists) { playlist in
                    Button(playlist.name) { Task { await library.perform(.addToPlaylist(video: video.reference, playlistID: playlist.id)) } }
                }
            } label: { Label("Add to playlist", systemImage: "text.badge.plus") }
        }
        if let id = video.channelID {
            Button { player.expanded = false; router.open(.channel(id: id, name: video.channel ?? "")) } label: {
                Label(video.channel ?? "Channel", systemImage: "person.crop.square")
            }
        }
        ShareLink(item: video.watchURL) { Label("Share", systemImage: "square.and.arrow.up") }
    }
}

extension LibraryStore {
    func progress(_ id: String) -> Double? { snapshot.history.first { $0.videoID == id }?.progress }
    func isSubscribed(_ channelID: String?) -> Bool {
        guard let channelID else { return false }
        return snapshot.subscriptions.contains { $0.id == channelID }
    }
    func toggleSubscription(id: String, name: String, avatar: URL? = nil) {
        Task {
            if isSubscribed(id) { await perform(.unsubscribe(id)) }
            else { await perform(.subscribe(LocalSubscription(id: id, name: name, thumbnailURL: avatar))) }
        }
    }
}

struct ErrorRow: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Retry", action: retry).buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}
