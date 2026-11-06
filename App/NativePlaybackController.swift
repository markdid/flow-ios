// SPDX-License-Identifier: GPL-3.0-only
// New AVFoundation implementation for the Flow iOS port, 2026-11-06.
import AVFoundation
import Combine
import MediaPlayer
import FlowCore

@MainActor final class NativePlaybackController: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var queue = PlaybackQueue()
    @Published private(set) var sources: [PlaybackSource] = []
    @Published private(set) var selectedSource: PlaybackSource?
    @Published private(set) var loading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var error: String?
    @Published private(set) var notice: String?
    @Published private(set) var rate: Float = 1
    private var resolveTask: Task<Void, Never>?
    private var generation = UUID()
    private var sessionID: UUID?
    private var playbackItemID = UUID()
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var playbackObservation: NSKeyValueObservation?
    private var notifications: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var wasPlayingBeforeInterruption = false
    private var initialResume: Double = 0
    private var historyReady = false
    private var wantsPlayback = false
    private var pendingExplicitPlay = false
    private var reachedEnd = false
    private var seekID = UUID()
    private var itemPrepared = false
    private var lastCheckpoint = Date.distantPast
    var onCheckpoint: ((VideoReference, Double, Double) -> Void)?

    func start(videos: [VideoReference], index: Int = 0, resumeAt: Double = 0) {
        stop()
        sessionID = UUID()
        wantsPlayback = true
        initialResume = resumeAt.isFinite ? max(0, resumeAt) : 0
        queue.replace(with: videos, startAt: index)
        configureObservers()
        configureRemoteCommands()
        loadCurrent()
    }
    #if DEBUG
    /// Test-only local fixture entry. Never resolves or requests remote media.
    func startLocalTestFixture(_ url: URL) {
        precondition(url.isFileURL)
        stop()
        sessionID = UUID()
        wantsPlayback = true
        initialResume = 0
        queue.replace(with: [])
        configureObservers()
        let source = PlaybackSource(id: "local-test-fixture", url: url,
                                    label: "Generated local test video", kind: .video)
        sources = [source]
        selectedSource = nil
        position = 0
        duration = 0
        select(source)
    }
    #endif

    private func loadCurrent() {
        guard sessionID != nil else { return }
        resolveTask?.cancel()
        generation = UUID()
        let expectedGeneration = generation
        historyReady = false
        pendingExplicitPlay = false
        reachedEnd = false
        invalidateItemTimeObserver()
        player.pause()
        player.replaceCurrentItem(with: nil)
        sources = []; selectedSource = nil; position = 0; duration = 0; error = nil; notice = nil
        guard let video = queue.current else { loading = false; return }
        loading = true
        updateNowPlaying()
        resolveTask = Task { [weak self] in
            do {
                let resolved = try await PlaybackClient().resolve(video)
                try Task.checkCancellation()
                guard let self, self.generation == expectedGeneration else { return }
                self.sources = resolved
                self.loading = false
                if let source = resolved.first { self.select(source) }
            } catch is CancellationError { }
            catch {
                guard let self, self.generation == expectedGeneration else { return }
                self.loading = false
                self.error = error.localizedDescription
            }
        }
    }
    func retry() { checkpoint(); initialResume = max(position, initialResume); loadCurrent() }
    func select(_ source: PlaybackSource) {
        guard let expectedSession = sessionID, sources.contains(source) else { return }
        checkpoint()
        let resumeAt = max(position, initialResume)
        historyReady = false
        itemPrepared = false
        let shouldPlay = PlaybackStartPolicy.shouldStart(firstSource: selectedSource == nil, requested: wantsPlayback, pendingPlay: pendingExplicitPlay, actualRate: Double(player.rate), waiting: player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
        wantsPlayback = shouldPlay
        selectedSource = source
        error = nil
        let item = AVPlayerItem(url: source.url)
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            Task { @MainActor in
                guard let self, self.sessionID == expectedSession, let item, self.player.currentItem === item else { return }
                if item.status == .failed { self.error = item.error?.localizedDescription ?? "The native player could not open this stream." }
                if item.status == .readyToPlay && !self.itemPrepared {
                    self.itemPrepared = true
                    let total = item.duration.seconds
                    self.duration = total.isFinite ? max(0, total) : 0
                    if resumeAt > 0 { self.restorePosition(resumeAt, item: item, allowPendingPlay: false) }
                    else {
                        self.historyReady = true
                        self.lastCheckpoint = Date()
                        if self.wantsPlayback { self.play() }
                    }
                }
            }
        }
        invalidateItemTimeObserver()
        player.replaceCurrentItem(with: item)
        configureItemTimeObserver(item)

    }
    func play() {
        guard sessionID != nil else { return }
        wantsPlayback = true
        guard historyReady, player.currentItem != nil else {
            pendingExplicitPlay = true
            return
        }
        pendingExplicitPlay = false
        if PlaybackStartPolicy.shouldRestart(ended: reachedEnd, position: player.currentTime().seconds, duration: duration), let item = player.currentItem {
            restorePosition(0, item: item, playWhenReady: true)
            return
        }
        notice = nil
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            player.playImmediately(atRate: rate)
        } catch { self.error = error.localizedDescription }
    }
    func pause() { wantsPlayback = false; pendingExplicitPlay = false; player.pause(); checkpoint() }
    func toggle() { isPlaying ? pause() : play() }
    func seek(to seconds: Double) {
        guard sessionID != nil, seconds.isFinite, let item = player.currentItem else { return }
        restorePosition(seconds, item: item)
    }
    private func restorePosition(_ seconds: Double, item: AVPlayerItem, playWhenReady: Bool = false, allowPendingPlay: Bool = true) {
        guard let expectedSession = sessionID else { return }
        let expectedItem = playbackItemID
        let expectedSeek = UUID()
        seekID = expectedSeek
        let value = max(0, duration > 0 ? min(seconds, duration) : seconds)
        historyReady = false
        player.seek(to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak item] finished in
            Task { @MainActor in
                guard let self, let item, self.sessionID == expectedSession,
                      self.playbackItemID == expectedItem, self.seekID == expectedSeek, self.player.currentItem === item else { return }
                guard finished else {
                    self.pendingExplicitPlay = false
                    self.error = "Could not restore playback position. Retry to keep your saved place."
                    return
                }
                self.initialResume = 0
                self.reachedEnd = false
                self.position = value
                self.historyReady = true
                self.lastCheckpoint = Date()
                self.updateNowPlaying()
                let shouldStart = PlaybackStartPolicy.shouldStartAfterSeek(sourceRestoration: !allowPendingPlay, explicitReplay: playWhenReady, pendingPlay: self.pendingExplicitPlay, requested: self.wantsPlayback)
                self.pendingExplicitPlay = false
                if shouldStart { self.play() }
                else if !allowPendingPlay {
                    // AVKit does not expose a distinct user-pause event during restoration.
                    // Favor silence over overriding a pause: the user can explicitly Play now.
                    self.wantsPlayback = false
                    self.player.pause()
                    self.notice = "Position restored. Press Play to continue."
                }
            }
        }
    }
    func checkpoint() {
        guard sessionID != nil, historyReady, let video = queue.current, let item = player.currentItem else { return }
        let current = player.currentTime().seconds
        let total = item.duration.seconds
        guard current.isFinite, current >= 0 else { return }
        onCheckpoint?(video, current, total.isFinite ? max(0, total) : 0)
        lastCheckpoint = Date()
    }
    func setRate(_ value: Float) {
        guard [Float(0.5), 0.75, 1, 1.25, 1.5, 1.75, 2].contains(value) else { return }
        rate = value
        if player.rate != 0 { player.rate = value }
    }
    func setRepeat(_ value: PlaybackQueue.RepeatMode) { queue.repeatMode = value }
    func toggleShuffle() { queue.shuffled.toggle() }
    func enqueue(_ video: VideoReference) { queue.append(video) }
    func next(automatic: Bool = false) {
        guard sessionID != nil else { return }
        checkpoint()
        initialResume = 0
        if queue.next(automatic: automatic) != nil {
            if automatic { wantsPlayback = true }
            loadCurrent()
        }
        else { pause() }
    }
    func previous() {
        guard sessionID != nil else { return }
        if position > 3 { seek(to: 0) }
        else {
            checkpoint()
            initialResume = 0
            if queue.previous() != nil { loadCurrent() }
        }
    }
    func stop() {
        checkpoint()
        historyReady = false
        wantsPlayback = false
        pendingExplicitPlay = false
        sessionID = nil
        wasPlayingBeforeInterruption = false
        reachedEnd = false
        resolveTask?.cancel(); resolveTask = nil; generation = UUID()
        player.pause(); player.replaceCurrentItem(with: nil)
        itemObservation = nil; playbackObservation = nil
        invalidateItemTimeObserver()
        for observer in notifications { NotificationCenter.default.removeObserver(observer) }
        notifications.removeAll()
        for (command, target) in remoteTargets { command.removeTarget(target) }
        remoteTargets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        loading = false; isPlaying = false
    }
    private func invalidateItemTimeObserver() {
        // Invalidate first: removing an observer cannot retract already queued Tasks.
        playbackItemID = UUID()
        if let observer = timeObserver { player.removeTimeObserver(observer); timeObserver = nil }
    }
    private func configureItemTimeObserver(_ item: AVPlayerItem) {
        guard let expectedSession = sessionID else { return }
        let expectedItemID = playbackItemID
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self, weak item] time in
            Task { @MainActor in
                guard let self, let item,
                      self.sessionID == expectedSession,
                      self.playbackItemID == expectedItemID,
                      self.player.currentItem === item else { return }
                guard self.historyReady else { return }
                self.position = time.seconds.isFinite ? max(0, time.seconds) : 0
                let total = item.duration.seconds
                self.duration = total.isFinite ? max(0, total) : 0
                self.updateNowPlaying()
                if Date().timeIntervalSince(self.lastCheckpoint) >= 10 { self.checkpoint() }
            }
        }
    }
    private func configureObservers() {
        guard let expectedSession = sessionID else { return }
        playbackObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.sessionID == expectedSession else { return }
                let status = self.player.timeControlStatus
                self.isPlaying = status != .paused
                if self.historyReady {
                    if status == .playing { self.wantsPlayback = true }
                    else if status == .paused && self.player.rate == 0 { self.wantsPlayback = false }
                }
                if !self.isPlaying { self.checkpoint() }
                self.updateNowPlaying()
            }
        }
        notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            guard let item = notification.object as? AVPlayerItem else { return }
            Task { @MainActor in
                guard let self, self.sessionID == expectedSession, self.player.currentItem === item else { return }
                self.reachedEnd = true
                self.checkpoint()
                self.next(automatic: true)
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self, self.sessionID == expectedSession else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.wasPlayingBeforeInterruption = self.isPlaying
                    self.pause()
                } else if type == AVAudioSession.InterruptionType.ended.rawValue {
                    if self.wasPlayingBeforeInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) { self.play() }
                    self.wasPlayingBeforeInterruption = false
                }
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in
                    guard let self, self.sessionID == expectedSession else { return }
                    self.pause()
                }
            }
        })
    }
    private func configureRemoteCommands() {
        guard let expectedSession = sessionID else { return }
        let center = MPRemoteCommandCenter.shared()
        func register(_ command: MPRemoteCommand, action: @escaping @MainActor () -> Void) {
            command.isEnabled = true
            let target = command.addTarget { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.sessionID == expectedSession else { return }
                    action()
                }
                return .success
            }
            remoteTargets.append((command, target))
        }
        register(center.playCommand) { [weak self] in self?.play() }
        register(center.pauseCommand) { [weak self] in self?.pause() }
        register(center.togglePlayPauseCommand) { [weak self] in self?.toggle() }
        register(center.nextTrackCommand) { [weak self] in self?.next() }
        register(center.previousTrackCommand) { [weak self] in self?.previous() }
        let target = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds = event.positionTime
            Task { @MainActor in
                guard let self, self.sessionID == expectedSession else { return }
                self.seek(to: seconds)
            }
            return .success
        }
        remoteTargets.append((center.changePlaybackPositionCommand, target))
    }
    private func updateNowPlaying() {
        guard sessionID != nil, let video = queue.current else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: video.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: player.rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: rate]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
