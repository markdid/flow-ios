// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import FlowCore

@MainActor final class SponsorBlockModel: ObservableObject {
    enum Mode: String, CaseIterable { case manual = "Manual skip", once = "Automatic once" }
    @Published private(set) var enabled = false
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var current: SponsorSegment?
    @Published private(set) var count = 0
    @Published var mode: Mode = .manual
    private var session = SponsorSkipSession(segments: [])
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var position: Double = 0
    private var duration: Double = 0
    func setEnabled(_ enabled: Bool, videoID: String, position: Double, duration: Double) {
        disable()
        guard enabled else { return }
        self.enabled = true; self.position = position; self.duration = duration; loading = true
        let currentGeneration = UUID(); generation = currentGeneration
        task = Task {
            do {
                let segments = try await SponsorBlockClient().fetch(videoID: videoID)
                guard !Task.isCancelled, generation == currentGeneration, self.enabled else { return }
                session = SponsorSkipSession(segments: segments)
                count = segments.count
                current = session.current(at: self.position, duration: self.duration)
            } catch {
                guard !Task.isCancelled, generation == currentGeneration, self.enabled else { return }
                self.error = error.localizedDescription
            }
            if generation == currentGeneration { loading = false }
        }
    }
    func update(position: Double, isPlaying: Bool, duration: Double) -> Double? {
        self.position = position
        self.duration = duration
        guard enabled else { current = nil; return nil }
        current = session.current(at: position, duration: duration)
        guard mode == .once, let segment = session.automaticTarget(at: position, isPlaying: isPlaying, duration: duration) else { return nil }
        return segment.end
    }
    func manualTarget(position: Double, duration: Double) -> Double? {
        guard enabled else { return nil }
        return session.manualTarget(at: position, duration: duration)?.end
    }
    func disable() {
        task?.cancel(); generation = UUID(); enabled = false; loading = false
        current = nil; count = 0; error = nil; session = SponsorSkipSession(segments: [])
    }
}

struct SponsorBlockControls: View {
    @ObservedObject var model: SponsorBlockModel
    let videoID: String
    let position: Double
    let duration: Double
    let seek: (Double) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("SponsorBlock for this video", isOn: Binding(get: { model.enabled }, set: {
                model.setEnabled($0, videoID: videoID, position: position, duration: duration)
            }))
            Text("Turning this on sends this video’s ID and your IP address to sponsor.ajay.app to retrieve community segments. Off by default; applies only to native playback during this visit.")
                .font(.caption).foregroundStyle(.secondary)
            if model.enabled {
                Picker("Skip behavior", selection: $model.mode) {
                    ForEach(SponsorBlockModel.Mode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                }.pickerStyle(.segmented)
                if model.loading { ProgressView("Loading segments…") }
                else if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
                else { Text("\(model.count) segment records loaded. Mute, highlight, voting and submission are not implemented.").font(.caption) }
                if !duration.isFinite || duration <= 0 {
                    Text("Skipping waits until the video duration is known. Out-of-range segments are ignored rather than clamped.").font(.caption)
                }
                if let segment = model.current {
                    Button("Skip \(segment.category.replacingOccurrences(of: "_", with: " "))") {
                        if let target = model.manualTarget(position: position, duration: duration) { seek(target) }
                    }.buttonStyle(.bordered)
                }
            }
        }
    }
}
