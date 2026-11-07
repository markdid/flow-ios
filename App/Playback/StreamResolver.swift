// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import Foundation
import YouTubeKit

struct StreamQuality: Identifiable, Hashable, Sendable {
    let height: Int
    let url: URL
    let codec: String
    var id: Int { height }
    var label: String { "\(height)p" }
}

struct ResolvedMedia: Sendable {
    let videoID: String
    let qualities: [StreamQuality]
    let audioURL: URL?
    let muxedURL: URL?
    let hlsURL: URL?
    let description: String?
}

enum StreamResolverError: LocalizedError {
    case noPlayableStream
    var errorDescription: String? { "No playable stream" }
}

enum StreamResolver {
    /// Local extraction only: the player script runs in JavaScriptCore on device.
    static func resolve(videoID: String) async throws -> ResolvedMedia {
        let youtube = YouTube(videoID: videoID, methods: [.local])
        let description = try? await youtube.metadata?.description
        if let live = try? await youtube.livestreams.first(where: { $0.streamType == .hls }) {
            return ResolvedMedia(videoID: videoID, qualities: [], audioURL: nil, muxedURL: nil, hlsURL: live.url, description: description)
        }
        let streams = try await youtube.streams
        let audio = streams.filterAudioOnly().filter { $0.isNativelyPlayable && $0.fileExtension == .m4a }
            .max { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }
        var byHeight: [Int: (YouTubeKit.Stream, Int)] = [:]
        for stream in streams where stream.includesVideoTrack && !stream.includesAudioTrack && stream.isNativelyPlayable && stream.fileExtension == .mp4 {
            guard let height = stream.videoResolution else { continue }
            // Prefer H.264 for compatibility, then AV1 where hardware decode exists.
            let rank = stream.videoCodec == .avc1 ? 2 : 1
            if let existing = byHeight[height], existing.1 >= rank { continue }
            byHeight[height] = (stream, rank)
        }
        let qualities = byHeight.map { StreamQuality(height: $0.key, url: $0.value.0.url, codec: $0.value.1 == 2 ? "avc1" : "av01") }
            .sorted { $0.height > $1.height }
        let muxed = streams.filter { $0.includesVideoAndAudioTrack && $0.isNativelyPlayable }
            .max { ($0.videoResolution ?? 0) < ($1.videoResolution ?? 0) }
        guard (audio != nil && !qualities.isEmpty) || muxed != nil || audio != nil else { throw StreamResolverError.noPlayableStream }
        return ResolvedMedia(videoID: videoID, qualities: qualities, audioURL: audio?.url, muxedURL: muxed?.url, hlsURL: nil, description: description)
    }

    /// Picks the best quality at or below the preferred height.
    static func pick(_ qualities: [StreamQuality], preferred: Int) -> StreamQuality? {
        qualities.first { $0.height <= preferred } ?? qualities.last
    }

    /// Builds a player item, combining separate DASH video and audio tracks when needed.
    static func makeItem(media: ResolvedMedia, quality: StreamQuality?, audioOnly: Bool) async throws -> AVPlayerItem {
        if let hls = media.hlsURL { return AVPlayerItem(url: hls) }
        if audioOnly, let audio = media.audioURL { return AVPlayerItem(url: audio) }
        if let quality, let audioURL = media.audioURL {
            do {
                return try await composed(video: quality.url, audio: audioURL)
            } catch {
                if let muxed = media.muxedURL { return AVPlayerItem(url: muxed) }
                throw error
            }
        }
        if let muxed = media.muxedURL { return AVPlayerItem(url: muxed) }
        if let audio = media.audioURL { return AVPlayerItem(url: audio) }
        throw StreamResolverError.noPlayableStream
    }

    private static func composed(video: URL, audio: URL) async throws -> AVPlayerItem {
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        async let videoTracks = videoAsset.loadTracks(withMediaType: .video)
        async let audioTracks = audioAsset.loadTracks(withMediaType: .audio)
        async let videoDuration = videoAsset.load(.duration)
        async let audioDuration = audioAsset.load(.duration)
        guard let videoTrack = try await videoTracks.first, let audioTrack = try await audioTracks.first else {
            throw StreamResolverError.noPlayableStream
        }
        let duration = CMTimeMinimum(try await videoDuration, try await audioDuration)
        let composition = AVMutableComposition()
        let range = CMTimeRange(start: .zero, duration: duration)
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(range, of: videoTrack, at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(range, of: audioTrack, at: .zero)
        return AVPlayerItem(asset: composition)
    }
}
