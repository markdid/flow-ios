// SPDX-License-Identifier: GPL-3.0-only
// New local Takeout import UI, 2026-11-06.
import SwiftUI
import UniformTypeIdentifiers
import FlowCore

struct TakeoutImportView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var choosing = false
    @State private var busy = false
    @State private var committing = false
    @State private var preview: TakeoutPreview?
    @State private var playlistName = "Imported playlist"
    @State private var error: String?
    @State private var status: String?
    @State private var generation = UUID()
    @State private var preparation: Task<Void, Never>?
    @State private var reader: Task<TakeoutPreview, Error>?
    var body: some View {
        Form {
            Section("Google Takeout CSV") {
                Text("Choose an extracted subscriptions CSV or a playlist's video CSV. ZIP archives, watch/search history, playlist metadata and music-library CSV files are not supported. Nothing is uploaded and no YouTube lookup is performed.").font(.footnote)
                Button("Choose CSV file") { choosing = true }.disabled(busy || library.loading)
            }
            if busy { ProgressView("Processing local file…") }
            if let error { Text(error).foregroundStyle(.red) }
            if let status { Text(status) }
            if let preview {
                switch preview {
                case .subscriptions(let channels, let skipped):
                    Section("Preview") {
                        Text("\(channels.count) channels; \(skipped) invalid or duplicate rows skipped.")
                        ForEach(Array(channels.prefix(20))) { Text($0.name) }
                        Text("Merge updates matching names, preserving subscription dates and notification preferences. It does not remove existing channels.").font(.footnote)
                        Button("Import \(channels.count) channels") { commit(preview) }.disabled(busy || channels.isEmpty)
                    }
                case .playlist(let videos, let skipped):
                    Section("Preview") {
                        Text("\(videos.count) videos; \(skipped) invalid or duplicate rows skipped.")
                        TextField("New playlist name", text: $playlistName)
                        ForEach(Array(videos.prefix(20))) { Text($0.id) }
                        Text("Creates a new local playlist in CSV order. These files contain IDs, not video titles. Existing titles are preserved; new videos use their IDs. Original added timestamps are checked but not restored. Reimporting creates another playlist.").font(.footnote)
                        Button("Create playlist") { commit(preview) }.disabled(busy || videos.isEmpty || playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Button("Cancel preview", role: .cancel) { self.preview = nil }.disabled(busy)
            }
        }.navigationTitle("Import Takeout CSV")
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.commaSeparatedText], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { prepare(url) }
                case .failure(let failure): error = failure.localizedDescription
                }
            }
            .onDisappear { preparation?.cancel(); reader?.cancel(); generation = UUID(); if !committing { busy = false } }
    }
    private func prepare(_ url: URL) {
        preparation?.cancel(); reader?.cancel()
        let current = UUID(); generation = current; busy = true; preview = nil; error = nil; status = nil
        preparation = Task {
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw TakeoutError.unsupported }
                    guard (values.fileSize ?? 0) <= TakeoutCSV.maximumBytes else { throw TakeoutError.limit }
                    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                    var bytes = Data()
                    while bytes.count <= TakeoutCSV.maximumBytes {
                        try Task.checkCancellation()
                        let amount = min(65_536, TakeoutCSV.maximumBytes + 1 - bytes.count)
                        let chunk = try handle.read(upToCount: amount) ?? Data()
                        if chunk.isEmpty { break }
                        bytes.append(chunk)
                    }
                    return try TakeoutCSV.preview(bytes)
                }
                reader = worker
                let parsed = try await worker.value
                guard !Task.isCancelled, generation == current else { return }
                preview = parsed
                // User can edit this; never infer a cloud destination or upload anything.
                playlistName = String(url.deletingPathExtension().lastPathComponent.prefix(1000))
            } catch { if !Task.isCancelled, generation == current { self.error = error.localizedDescription } }
            if generation == current { busy = false }
        }
    }
    private func commit(_ preview: TakeoutPreview) {
        committing = true; busy = true; error = nil
        let command: LibraryCommand
        switch preview {
        case .subscriptions(let channels, _): command = .importSubscriptions(channels)
        case .playlist(let videos, _):
            command = .importPlaylist(playlist: LocalPlaylist(name: playlistName.trimmingCharacters(in: .whitespacesAndNewlines), videoIDs: videos.map(\.id)), videos: videos)
        }
        Task {
            if await library.perform(command) { self.preview = nil; status = "Imported into your local library." }
            else { error = library.error }
            committing = false; busy = false
        }
    }
}
