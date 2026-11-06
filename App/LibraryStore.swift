// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import FlowCore

@MainActor final class LibraryStore: ObservableObject {
    @Published private(set) var snapshot = LibrarySnapshot()
    @Published private(set) var loading = true
    @Published var error: String?
    var videos: [VideoReference] { snapshot.videos }
    private var repository: LibraryRepository?
    private var startup: Task<Void, Never>?
    private var pending: Task<Bool, Never>?

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FlowPrototype")
        startup = Task {
            do {
                let repository = try await Task.detached(priority: .userInitiated) {
                    try LibraryRepository(fileURL: directory.appendingPathComponent("collection-v1.json"), legacyBookmarksURL: directory.appendingPathComponent("library.json"))
                }.value
                self.repository = repository
                self.snapshot = await repository.snapshot()
            } catch {
                self.error = "Could not load your library. Existing files have not been overwritten. \(error.localizedDescription)"
            }
            self.loading = false
        }
    }

    @discardableResult func perform(_ command: LibraryCommand) async -> Bool {
        await startup?.value
        let previous = pending
        let operation = Task { @MainActor in
            _ = await previous?.value
            guard let repository else {
                error = "Saving is disabled because the library could not be loaded."
                return false
            }
            do {
                snapshot = try await repository.apply(command)
                return true
            } catch {
                self.error = error.localizedDescription
                return false
            }
        }
        pending = operation
        return await operation.value
    }
    func beginWatch(videoID: String) async -> WatchSession? {
        await startup?.value
        _ = await pending?.value
        return await repository?.beginWatch(videoID: videoID)
    }
    func add(_ video: VideoReference) async -> Bool { await perform(.saveVideo(video)) }
    func remove(at offsets: IndexSet) {
        let ids = offsets.compactMap { videos.indices.contains($0) ? videos[$0].id : nil }
        Task { for id in ids { _ = await perform(.deleteVideo(id)) } }
    }
}
