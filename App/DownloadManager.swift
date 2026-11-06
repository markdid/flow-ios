// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AVFoundation
import FlowCore

@MainActor final class DownloadManager: ObservableObject {
    @Published private(set) var records: [DownloadedMedia] = []
    @Published private(set) var runningTitle: String?
    @Published private(set) var loading = true
    @Published var message: String?
    @Published var error: String?
    private var store: DownloadStore?
    private var startup: Task<Void, Never>?
    private var transfer: Task<Void, Never>?
    private var mutations: Task<Void, Never>?
    private var cancelled = false
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FlowPrototype/Downloads")
        startup = Task {
            do {
                let store = try await Task.detached { try DownloadStore(directory: directory) }.value
                self.store = store; records = await store.snapshot()
                let recovered = try await store.recoveredTransferCount()
                if recovered > 0 { message = "\(recovered) interrupted transfer(s) were preserved in recovery storage. They are not listed as completed downloads." }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
    func download(video: VideoReference, source: PlaybackSource) {
        guard transfer == nil else { return }
        error = nil; message = nil; cancelled = false; runningTitle = video.title
        transfer = Task {
            do {
                await startup?.value
                try Task.checkCancellation()
                guard store != nil else { throw DownloadError.invalidIndex }
                let result = try await Self.receive(source)
                defer { try? FileManager.default.removeItem(at: result.url) }
                try Task.checkCancellation()
                try await mutate(allowed: { !self.cancelled }) { store in
                    try await store.commit(temporaryFile: result.url, video: video, kind: result.kind, expectedBytes: result.bytes)
                }
                message = "Download saved for offline playback."
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { message = "Download cancelled." }
                else { self.error = error.localizedDescription }
            }
            runningTitle = nil; transfer = nil
        }
    }
    func cancel() { cancelled = true; message = "Cancelling download…"; transfer?.cancel() }
    func remove(_ record: DownloadedMedia) async {
        do { try await mutate { store in try await store.remove(record.id) } }
        catch { self.error = error.localizedDescription }
    }
    private func mutate(allowed: @escaping @MainActor () -> Bool = { true },
                        _ operation: @escaping @Sendable (DownloadStore) async throws -> [DownloadedMedia]) async throws {
        let previous = mutations
        let work = Task { @MainActor () -> Result<Void, Error> in
            await previous?.value
            await startup?.value
            guard allowed() else { return .failure(CancellationError()) }
            guard let store else { return .failure(DownloadError.invalidIndex) }
            do { records = try await operation(store); return .success(()) }
            catch { records = await store.snapshot(); return .failure(error) }
        }
        mutations = Task { _ = await work.value }
        try await work.value.get()
    }
    func localURL(_ record: DownloadedMedia) async throws -> URL {
        await startup?.value
        guard let store else { throw DownloadError.invalidIndex }
        return try await store.fileURL(for: record.id)
    }
    private struct Received: Sendable { let url: URL; let kind: DownloadedMedia.Kind; let bytes: Int64 }
    nonisolated private static func receive(_ source: PlaybackSource) async throws -> Received {
        let kind = try DownloadPolicy.kind(for: source)
        var request = URLRequest(url: source.url)
        request.timeoutInterval = 60
        let session = URLSession(configuration: .ephemeral, delegate: DownloadRedirectGuard(source: source), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, let finalURL = http.url else { throw DownloadError.invalidResponse }
        _ = try DownloadPolicy.kind(for: PlaybackSource(id: source.id, url: finalURL, label: source.label, kind: source.kind, height: source.height))
        let size = Int64(try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        try DownloadPolicy.validateResponse(status: http.statusCode, mimeType: http.mimeType,
            expectedBytes: http.expectedContentLength, actualBytes: size, kind: kind)
        try Task.checkCancellation()
        let spool = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + (kind == .video ? ".mp4" : ".m4a"))
        do {
            try FileManager.default.copyItem(at: temporary, to: spool)
            let asset = AVURLAsset(url: spool)
            guard try await asset.load(.isPlayable) else { throw DownloadError.emptyFile }
            let audio = try await asset.loadTracks(withMediaType: .audio)
            guard !audio.isEmpty else { throw DownloadError.emptyFile }
            if kind == .video {
                let video = try await asset.loadTracks(withMediaType: .video)
                guard !video.isEmpty else { throw DownloadError.emptyFile }
            }
            try Task.checkCancellation()
            return Received(url: spool, kind: kind, bytes: size)
        } catch {
            try? FileManager.default.removeItem(at: spool)
            throw error
        }
    }
}

/// Validate before following every redirect, not after transmitting to its destination.
private final class DownloadRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let source: PlaybackSource
    init(source: PlaybackSource) { self.source = source }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url,
              (try? DownloadPolicy.kind(for: PlaybackSource(id: source.id, url: url, label: source.label, kind: source.kind, height: source.height))) != nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
