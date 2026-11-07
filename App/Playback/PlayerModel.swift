// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import FlowCore
import MediaPlayer
import Observation
import SwiftUI

enum Settings {
    static let qualityKey = "preferredQuality"
    static let autoplayKey = "autoplay"
    static let sponsorBlockKey = "sponsorBlock"
    static let sponsorAutoSkipKey = "sponsorAutoSkip"
    static let defaults: [String: Any] = [qualityKey: 1080, autoplayKey: true, sponsorBlockKey: true,
                                          sponsorAutoSkipKey: ["sponsor", "selfpromo", "interaction"]]
    static var autoSkipCategories: Set<String> { Set(UserDefaults.standard.stringArray(forKey: sponsorAutoSkipKey) ?? []) }
}

@MainActor @Observable final class PlayerModel {
    enum Status: Equatable { case idle, loading, ready, failed(String) }

    let player = AVPlayer()
    private(set) var current: VideoItem?
    private(set) var details: WatchDetails?
    private(set) var related: [VideoItem] = []
    private(set) var media: ResolvedMedia?
    private(set) var quality: StreamQuality?
    private(set) var status: Status = .idle
    private(set) var isPlaying = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var audioOnly = false
    private(set) var history: [VideoItem] = []
    private(set) var lastSkipped: SponsorSegment?
    /// All segments for the current video, for the timeline strip.
    private(set) var segments: [SponsorSegment] = []
    /// A segment the playhead is inside that isn't auto-skipped, offered as a skip button.
    private(set) var manualSegment: SponsorSegment?
    private(set) var commentPreview: VideoComment?
    private(set) var commentCount: String?
    var expanded = false
    var commentsPresented = false

    @ObservationIgnored private var library: LibraryStore?
    @ObservationIgnored private var cache: MetadataCache?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var sponsor = SponsorSkipSession(segments: [])
    @ObservationIgnored private var watchSession: WatchSession?
    @ObservationIgnored private var lastCheckpoint = Date.distantPast
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var artworkTask: Task<Void, Never>?


    init() {
        UserDefaults.standard.register(defaults: Settings.defaults)
        player.allowsExternalPlayback = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        observations.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            print("[player] timeControl=\(player.timeControlStatus.rawValue) waiting=\(player.reasonForWaitingToPlay?.rawValue ?? "-") t=\(String(format: "%.1f", player.currentTime().seconds))")
            Task { @MainActor in self?.isPlaying = playing; self?.updateNowPlaying() }
        })
        NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
                self.finished()
            }
        }
        configureRemoteCommands()
    }

    func configure(library: LibraryStore, cache: MetadataCache) {
        self.library = library; self.cache = cache
    }

    var upNext: VideoItem? {
        let played = Set(history.map(\.id))
        return related.first { !played.contains($0.id) && !$0.isShort }
    }

    // MARK: Loading

    func play(_ video: VideoItem, expand: Bool = true) {
        if current?.id == video.id, status != .idle {
            if expand { expanded = true }
            if case .failed = status { reload() } else { player.play() }
            return
        }
        checkpoint(force: true)
        if let current { history.removeAll { $0.id == current.id }; history.append(current) }
        let video = cache?.items[video.id].map { video.merged(with: $0) } ?? video
        current = video
        details = nil; related = []; media = nil; quality = nil; duration = 0; position = 0; lastSkipped = nil
        commentPreview = nil; commentCount = nil
        sponsor = SponsorSkipSession(segments: []); segments = []; manualSegment = nil
        if expand { expanded = true }
        player.replaceCurrentItem(with: nil)
        updateNowPlaying(); loadArtwork(for: video)
        load(video)
    }

    func reload() { if let current { load(current) } }

    private func load(_ video: VideoItem) {
        generation += 1
        let generation = generation
        loadTask?.cancel()
        status = .loading
        let resume = resumePosition(for: video.id)
        let preferred = UserDefaults.standard.integer(forKey: Settings.qualityKey)
        let audioOnly = audioOnly
        loadTask = Task { [weak self] in
            async let detailsResult = try? WatchDetailsClient().details(videoID: video.id)
            async let comments = try? VideoCommentsClient().first(videoID: video.id)
            async let segments = UserDefaults.standard.bool(forKey: Settings.sponsorBlockKey)
                ? ((try? await SponsorBlockClient().fetch(videoID: video.id)) ?? []) : []
            do {
                let started = Date()
                func log(_ message: String) { print("[load \(video.id)] +\(String(format: "%.1f", Date().timeIntervalSince(started)))s \(message)") }
                log("resolve start")
                let media = try await StreamResolver.resolve(videoID: video.id)
                log("resolved qualities=\(media.qualities.map { "\($0.height)\($0.codec)" }) audio=\(media.audioURL != nil) muxed=\(media.muxedURL != nil) hls=\(media.hlsURL != nil)")
                let quality = StreamResolver.pick(media.qualities, preferred: preferred)
                let (item, used) = try await StreamResolver.makeItem(media: media, quality: quality, audioOnly: audioOnly)
                log("item built quality=\(used?.label ?? "combined") \(used?.codec ?? "")")
                guard let self, !Task.isCancelled, generation == self.generation else { return }
                self.media = media; self.quality = used
                self.start(item, at: resume)
                self.watchSession = await self.library?.beginWatch(videoID: video.id)
            } catch {
                guard let self, !Task.isCancelled, generation == self.generation else { return }
                print("[load \(video.id)] failed: \(error)")
                self.status = .failed(error.localizedDescription)
            }
            let details = await detailsResult
            let fetched = await segments
            guard let self, !Task.isCancelled, generation == self.generation else { return }
            let autoSkip = Settings.autoSkipCategories
            self.segments = SponsorSkipSession(segments: fetched).segments
            self.sponsor = SponsorSkipSession(segments: fetched.filter { autoSkip.contains($0.category) })
            if let details { self.apply(details, to: video) }
            let page = await comments
            guard !Task.isCancelled, generation == self.generation else { return }
            self.commentPreview = page?.comments.first
            self.commentCount = page?.totalText
        }
    }

    private func apply(_ details: WatchDetails, to video: VideoItem) {
        self.details = details
        related = details.relatedItems
        var updated = current ?? video
        if let title = details.title, !title.isEmpty { updated.title = title }
        updated.channel = details.channel?.name ?? updated.channel
        updated.channelID = details.channel?.id ?? updated.channelID
        updated.views = details.views ?? updated.views
        updated.published = details.published ?? updated.published
        updated.channelAvatar = details.channel?.avatar ?? updated.channelAvatar
        current = updated
        cache?.remember([updated] + related)
        updateNowPlaying()
    }

    private func start(_ item: AVPlayerItem, at seconds: Double) {
        activateAudioSession()
        player.replaceCurrentItem(with: item)
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let failure = item.status == .failed ? (item.error?.localizedDescription ?? "Playback failed") : nil
            Task { @MainActor in
                guard let self, self.player.currentItem === item else { return }
                print("[item] status=\(item.status.rawValue) error=\(String(describing: item.error))")
                if let failure { self.status = .failed(failure) }
                else if item.status == .readyToPlay {
                    self.status = .ready
                    let seconds = item.duration.seconds
                    if seconds.isFinite { self.duration = seconds }
                    self.updateNowPlaying()
                }
            }
        }
        if seconds > 0 { item.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), completionHandler: nil) }
        player.play()
    }

    private func resumePosition(for id: String) -> Double {
        guard let entry = library?.snapshot.history.first(where: { $0.videoID == id }),
              entry.progress < 0.95, entry.position > 10 else { return 0 }
        return entry.position
    }

    // MARK: Controls

    func toggle() { isPlaying ? player.pause() : resume() }
    func resume() { activateAudioSession(); player.play() }
    func pause() { player.pause(); checkpoint(force: true) }

    func seek(by delta: Double) { seek(to: max(0, position + delta)) }
    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        position = seconds
    }

    func undoSkip() {
        guard let segment = lastSkipped else { return }
        lastSkipped = nil
        seek(to: segment.start)
    }

    func skipManual() {
        guard let segment = manualSegment else { return }
        manualSegment = nil
        seek(to: segment.end)
    }

    func select(quality: StreamQuality) { switchSource(quality: quality, audioOnly: false) }
    func setAudioOnly(_ value: Bool) { switchSource(quality: quality, audioOnly: value) }

    private func switchSource(quality: StreamQuality?, audioOnly: Bool) {
        guard let media else { self.audioOnly = audioOnly; return }
        let at = position, wasPlaying = isPlaying
        self.quality = quality; self.audioOnly = audioOnly
        generation += 1
        let generation = generation
        loadTask = Task { [weak self] in
            guard let (item, used) = try? await StreamResolver.makeItem(media: media, quality: quality, audioOnly: audioOnly),
                  let self, generation == self.generation else { return }
            if !audioOnly { self.quality = used }
            self.start(item, at: at)
            if !wasPlaying { self.player.pause() }
        }
    }

    func next() {
        guard let upNext else { return }
        play(upNext, expand: expanded)
    }

    func previous() {
        if position > 5 { seek(to: 0); return }
        guard let last = history.popLast() else { seek(to: 0); return }
        let currentItem = current
        play(last, expand: expanded)
        if let currentItem { related.insert(currentItem, at: 0) }
    }

    func close() {
        checkpoint(force: true)
        loadTask?.cancel()
        player.replaceCurrentItem(with: nil)
        current = nil; details = nil; related = []; media = nil; status = .idle; expanded = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func finished() {
        checkpoint(force: true)
        if UserDefaults.standard.bool(forKey: Settings.autoplayKey), upNext != nil { next() }
    }

    // MARK: Ticks

    @ObservationIgnored private var lastLoggedSecond = -10.0
    private func tick(_ seconds: Double) {
        guard seconds.isFinite, current != nil else { return }
        if abs(seconds - lastLoggedSecond) >= 5 {
            lastLoggedSecond = seconds
            let item = player.currentItem
            print("[tick] t=\(Int(seconds)) rate=\(player.rate) buffered=\(item?.loadedTimeRanges.last.map { Int(CMTimeRangeGetEnd($0.timeRangeValue).seconds) } ?? -1) likelyToKeepUp=\(item?.isPlaybackLikelyToKeepUp ?? false) err=\(item?.errorLog()?.events.last.map { "\($0.errorStatusCode) \($0.errorComment ?? "")" } ?? "-")")
        }
        position = seconds
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 { duration = itemDuration }
        if let segment = sponsor.automaticTarget(at: seconds, isPlaying: isPlaying, duration: duration > 0 ? duration : nil) {
            seek(to: segment.end)
            lastSkipped = segment
            let id = segment.id
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                if self?.lastSkipped?.id == id { self?.lastSkipped = nil }
            }
        }
        let autoSkip = Settings.autoSkipCategories
        let inside = segments.first { $0.contains(seconds) && !autoSkip.contains($0.category) && $0.end - seconds > 1 }
        if inside?.id != manualSegment?.id { manualSegment = inside }
        checkpoint()
    }

    private func checkpoint(force: Bool = false) {
        guard let current, let library, let session = watchSession, session.videoID == current.id,
              position > 0, force || Date().timeIntervalSince(lastCheckpoint) > 10 else { return }
        lastCheckpoint = Date()
        let entry = LocalWatchEntry(videoID: current.id, position: position, duration: duration, isShort: current.isShort)
        let reference = current.reference
        Task { await library.perform(.recordWatch(video: reference, entry: entry, session: session)) }
    }

    // MARK: System integration

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
        try? session.setActive(true)
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.resume() }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.toggle() }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.seek(to: event.positionTime) }
            return .success
        }
    }

    @ObservationIgnored private var artwork: MPMediaItemArtwork?

    private func loadArtwork(for video: VideoItem) {
        artwork = nil
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: video.thumbnail),
                  let image = UIImage(data: data), let self, self.current?.id == video.id else { return }
            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.updateNowPlaying()
        }
    }

    private func updateNowPlaying() {
        guard let current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(player.rate) : 0,
        ]
        if let channel = current.channel { info[MPMediaItemPropertyArtist] = channel }
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
