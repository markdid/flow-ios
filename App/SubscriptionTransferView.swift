// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UniformTypeIdentifiers
import FlowCore

private struct SubscriptionJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SubscriptionTransferView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var importing = false
    @State private var exporting = false
    @State private var busy = false
    @State private var preview: NewPipeImportPreview?
    @State private var document = SubscriptionJSONDocument()
    @State private var exportSkipped = 0
    @State private var status: String?
    @State private var error: String?
    var body: some View {
        List {
            Section("NewPipe subscriptions") {
                Text("Import a NewPipe subscription JSON file, or export your saved channels in that format. Files are read locally. No channel lookup or upload happens during import. Malformed field types reject the whole file; unsupported URLs and services are skipped only in an otherwise valid file.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Choose import file") { importing = true }.disabled(busy)
                Button("Export subscriptions") { prepareExport() }.disabled(busy || library.loading)
            }
            if busy { ProgressView("Processing subscriptions…") }
            if let status { Text(status) }
            if let error { Text(error).foregroundStyle(.red) }
            if let preview {
                Section("Import preview") {
                    Text("\(preview.subscriptions.count) supported channels")
                    Text("\(preview.unresolvedURLs.count) handle or legacy URLs need channel-ID resolution, which is not implemented. They will not be imported.")
                        .font(.footnote)
                    Text("\(preview.skipped) invalid URLs, duplicates or non-YouTube services skipped.").font(.footnote)
                    ForEach(Array(preview.subscriptions.prefix(20))) { subscription in
                        Text(subscription.name)
                    }
                    if preview.subscriptions.count > 20 { Text("And \(preview.subscriptions.count - 20) more…").font(.caption) }
                    Text("Import merges subscriptions without deleting existing channels or changing notification preferences. Matching channel names are updated.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Import \(preview.subscriptions.count) channels") { commit(preview) }
                        .disabled(busy || preview.subscriptions.isEmpty)
                    Button("Cancel preview", role: .cancel) { self.preview = nil }.disabled(busy)
                }
            }
        }.navigationTitle("Import and export")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { prepareImport(url) }
                case .failure(let failure): error = failure.localizedDescription
                }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "flow-subscriptions") { result in
                switch result {
                case .success: status = exportSkipped == 0 ? "Subscription export saved." : "Subscription export saved; \(exportSkipped) unsupported channel identifiers were excluded."
                case .failure(let failure): error = failure.localizedDescription
                }
            }
    }
    private func prepareImport(_ url: URL) {
        busy = true; preview = nil; error = nil; status = nil
        Task {
            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= NewPipeSubscriptions.maximumBytes else { throw SubscriptionTransferError.tooLarge }
                    return try NewPipeSubscriptions.preview(Data(contentsOf: url, options: .mappedIfSafe))
                }.value
                preview = parsed
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    private func prepareExport() {
        error = nil; status = nil
        do {
            let result = try NewPipeSubscriptions.export(library.snapshot.subscriptions)
            document = SubscriptionJSONDocument(data: result.data)
            exportSkipped = result.skipped
            if result.skipped > 0 { status = "\(result.skipped) unsupported channel identifiers are excluded from this export." }
            exporting = true
        } catch { self.error = error.localizedDescription }
    }
    private func commit(_ preview: NewPipeImportPreview) {
        busy = true; error = nil
        Task {
            if await library.perform(.importSubscriptions(preview.subscriptions)) {
                status = "Imported or updated \(preview.subscriptions.count) subscriptions."
                self.preview = nil
            } else { error = library.error }
            busy = false
        }
    }
}
