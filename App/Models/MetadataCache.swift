// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Observation

/// Remembers card metadata for videos the library only stores by ID and title.
@MainActor @Observable final class MetadataCache {
    private(set) var items: [String: VideoItem] = [:]
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FlowPrototype")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("video-metadata.json")
        if let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode([String: VideoItem].self, from: data) {
            items = decoded
        }
    }

    func item(_ id: String, fallbackTitle: String = "") -> VideoItem {
        items[id] ?? VideoItem(id: id, title: fallbackTitle)
    }

    func remember(_ videos: [VideoItem]) {
        var changed = false
        for video in videos {
            let merged = items[video.id].map { video.merged(with: $0) } ?? video
            if items[video.id] != merged { items[video.id] = merged; changed = true }
        }
        if changed { scheduleSave() }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = items.count > 5000 ? Dictionary(uniqueKeysWithValues: items.suffix(5000).map { ($0.key, $0.value) }) : items
        let url = fileURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
