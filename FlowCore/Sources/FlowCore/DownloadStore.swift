// SPDX-License-Identifier: GPL-3.0-only
// New iOS storage boundary for Flow's download feature, 2026-11-06.
// Flow Android Client Copyright (C) 2025-2026 A-EDev; see Documentation/Downloads.md.
import Foundation

public struct DownloadedMedia: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case video, audio }
    public let id: UUID
    public let video: VideoReference
    public let kind: Kind
    public let byteCount: Int64
    public let completedAt: Date
    public var filename: String { id.uuidString.lowercased() + (kind == .video ? ".mp4" : ".m4a") }
}
public enum DownloadError: LocalizedError {
    case unsupportedSource, invalidResponse, sizeLimit, emptyFile, invalidIndex, missingFile, cleanupFailed
    case recoveryRequired(String)
    public var errorDescription: String? {
        switch self {
        case .unsupportedSource: return "Only direct muxed MP4 video and AAC audio downloads are supported. HLS and separate video/audio downloads are not yet implemented."
        case .invalidResponse: return "The download was incomplete or did not return the expected media type."
        case .sizeLimit: return "This download exceeds the 1 GB file limit. It was not added to the library."
        case .emptyFile: return "The downloaded media file is empty or invalid."
        case .invalidIndex: return "The downloads index could not be read safely. Existing files were preserved."
        case .missingFile: return "This downloaded file is missing."
        case .cleanupFailed: return "The download was removed from the list, but cleanup is pending. Reopen the app to retry recovery."
        case .recoveryRequired(let detail): return "A download transaction needs recovery. Existing files were preserved. \(detail)"
        }
    }
}
public enum DownloadPolicy {
    public static let maximumBytes: Int64 = 1_000_000_000
    public static func kind(for source: PlaybackSource) throws -> DownloadedMedia.Kind {
        guard (try? StreamURLResolver.resolve(directURL: source.url.absoluteString)) != nil else { throw DownloadError.unsupportedSource }
        let query = URLComponents(url: source.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard !query.contains(where: { $0.name == "range" }) else { throw DownloadError.unsupportedSource }
        switch source.kind {
        case .video: return .video
        case .audio: return .audio
        case .hls: throw DownloadError.unsupportedSource
        }
    }
    public static func validateResponse(status: Int, mimeType: String?, expectedBytes: Int64,
                                        actualBytes: Int64, kind: DownloadedMedia.Kind) throws {
        guard status == 200 else { throw DownloadError.invalidResponse }
        guard actualBytes > 0 else { throw DownloadError.emptyFile }
        guard actualBytes <= maximumBytes, expectedBytes <= maximumBytes else { throw DownloadError.sizeLimit }
        guard expectedBytes <= 0 || expectedBytes == actualBytes else { throw DownloadError.invalidResponse }
        let mime = (mimeType ?? "").lowercased().split(separator: ";").first.map(String.init) ?? ""
        let allowed = kind == .video ? ["video/mp4", "application/octet-stream"] : ["audio/mp4", "audio/x-m4a", "application/octet-stream"]
        guard allowed.contains(mime) else { throw DownloadError.invalidResponse }
    }
}

/// Stores metadata only, never signed stream URLs. Every media/index mutation has a durable
/// journal and deterministic staging path. Ambiguous recovery preserves files and blocks writes.
public actor DownloadStore {
    private struct Index: Codable { let version: Int; var records: [DownloadedMedia] }
    private struct Journal: Codable {
        enum Kind: String, Codable { case add, delete }
        let version: Int
        let kind: Kind
        let record: DownloadedMedia
        var originalFileExisted: Bool? = nil
    }
    private let directory: URL
    private let indexURL: URL
    private let journalURL: URL
    private var records: [DownloadedMedia]
    public init(directory: URL) throws {
        self.directory = directory
        indexURL = directory.appendingPathComponent("downloads-v1.json")
        journalURL = directory.appendingPathComponent("download-operation-v1.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let loaded: [DownloadedMedia]
        if FileManager.default.fileExists(atPath: indexURL.path) {
            try Self.regularFile(indexURL)
            let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))
            guard index.version == 1, Set(index.records.map(\.id)).count == index.records.count,
                  index.records.allSatisfy(Self.validRecord) else { throw DownloadError.invalidIndex }
            loaded = index.records
        } else { loaded = [] }
        records = try Self.recover(directory: directory, records: loaded)
    }
    public func snapshot() -> [DownloadedMedia] { records }
    public func recoveredTransferCount() throws -> Int {
        let recovery = directory.appendingPathComponent("Recovery")
        guard FileManager.default.fileExists(atPath: recovery.path) else { return 0 }
        return try FileManager.default.contentsOfDirectory(atPath: recovery.path).count
    }
    public func fileURL(for id: UUID) throws -> URL {
        guard let record = records.first(where: { $0.id == id }) else { throw DownloadError.missingFile }
        let url = directory.appendingPathComponent(record.filename)
        guard FileManager.default.fileExists(atPath: url.path) else { throw DownloadError.missingFile }
        try Self.regularFile(url)
        return url
    }
    public func commit(temporaryFile: URL, video: VideoReference, kind: DownloadedMedia.Kind,
                       expectedBytes: Int64? = nil, now: Date = Date()) throws -> [DownloadedMedia] {
        // Cancellation is honored before the transaction. After journaling, finish atomically.
        try Task.checkCancellation()
        try ensureNoPendingOperation()
        try Self.regularFile(temporaryFile)
        let bytes = Int64(try temporaryFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard bytes > 0 else { throw DownloadError.emptyFile }
        guard bytes <= DownloadPolicy.maximumBytes else { throw DownloadError.sizeLimit }
        if let expectedBytes, expectedBytes > 0, expectedBytes != bytes { throw DownloadError.invalidResponse }
        let record = DownloadedMedia(id: UUID(), video: video, kind: kind, byteCount: bytes, completedAt: now)
        let staging = Self.staging(record, in: directory, operation: .add)
        let destination = directory.appendingPathComponent(record.filename)
        try writeJournal(.init(version: 1, kind: .add, record: record))
        do {
            try FileManager.default.copyItem(at: temporaryFile, to: staging)
            try Self.checkSize(staging, record: record)
            try FileManager.default.moveItem(at: staging, to: destination)
            let next = [record] + records
            try Self.persist(next, in: directory)
            records = next
        } catch {
            do {
                for url in [staging, destination] where FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.removeItem(at: journalURL)
            } catch let rollbackError {
                throw DownloadError.recoveryRequired("Rollback failed: \(rollbackError.localizedDescription)")
            }
            throw error
        }
        do { try FileManager.default.removeItem(at: journalURL) }
        catch { throw DownloadError.recoveryRequired("The file was saved, but journal cleanup failed.") }
        return records
    }
    public func remove(_ id: UUID) throws -> [DownloadedMedia] {
        try Task.checkCancellation()
        try ensureNoPendingOperation()
        guard let record = records.first(where: { $0.id == id }) else { throw DownloadError.missingFile }
        let source = directory.appendingPathComponent(record.filename)
        let staging = Self.staging(record, in: directory, operation: .delete)
        let hadFile = FileManager.default.fileExists(atPath: source.path)
        try writeJournal(.init(version: 1, kind: .delete, record: record, originalFileExisted: hadFile))
        do {
            if hadFile { try Self.regularFile(source); try FileManager.default.moveItem(at: source, to: staging) }
            let next = records.filter { $0.id != id }
            try Self.persist(next, in: directory)
            records = next
        } catch {
            do {
                if FileManager.default.fileExists(atPath: staging.path) {
                    guard !FileManager.default.fileExists(atPath: source.path) else { throw DownloadError.invalidIndex }
                    try FileManager.default.moveItem(at: staging, to: source)
                }
                try FileManager.default.removeItem(at: journalURL)
            } catch let rollbackError {
                throw DownloadError.recoveryRequired("Delete restoration failed: \(rollbackError.localizedDescription)")
            }
            throw error
        }
        do {
            if hadFile { try FileManager.default.removeItem(at: staging) }
            try FileManager.default.removeItem(at: journalURL)
        } catch { throw DownloadError.cleanupFailed }
        return records
    }
    private func ensureNoPendingOperation() throws {
        guard !FileManager.default.fileExists(atPath: journalURL.path) else { throw DownloadError.recoveryRequired("Reopen the app to reconcile its pending journal.") }
    }
    private func writeJournal(_ journal: Journal) throws {
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
    }
    private static func validRecord(_ record: DownloadedMedia) -> Bool {
        record.byteCount > 0 && record.byteCount <= DownloadPolicy.maximumBytes
    }
    private static func regularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw DownloadError.emptyFile }
    }
    private static func checkSize(_ url: URL, record: DownloadedMedia) throws {
        try regularFile(url)
        guard Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) == record.byteCount else {
            throw DownloadError.recoveryRequired("A staged file is incomplete. It has not been deleted.")
        }
    }
    private static func staging(_ record: DownloadedMedia, in directory: URL, operation: Journal.Kind) -> URL {
        directory.appendingPathComponent("pending-" + operation.rawValue + "-" + record.filename)
    }
    private static func persist(_ records: [DownloadedMedia], in directory: URL) throws {
        try JSONEncoder().encode(Index(version: 1, records: records)).write(to: directory.appendingPathComponent("downloads-v1.json"), options: .atomic)
    }
    private static func quarantineIncompleteAdd(record: DownloadedMedia, staged: URL, journalURL: URL, directory: URL) throws {
        let folder = directory.appendingPathComponent("Recovery").appendingPathComponent("add-" + record.id.uuidString.lowercased())
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let evidence = folder.appendingPathComponent("operation.json")
        let journalData = try Data(contentsOf: journalURL)
        if FileManager.default.fileExists(atPath: evidence.path) {
            try regularFile(evidence)
            guard try Data(contentsOf: evidence) == journalData else { throw DownloadError.recoveryRequired("Existing recovery evidence does not match the pending add.") }
        } else { try journalData.write(to: evidence, options: .atomic) }
        let preserved = folder.appendingPathComponent(staged.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: preserved.path) else { throw DownloadError.recoveryRequired("The recovery destination already contains a file.") }
        try FileManager.default.moveItem(at: staged, to: preserved)
        try FileManager.default.removeItem(at: journalURL)
    }
    private static func recover(directory: URL, records: [DownloadedMedia]) throws -> [DownloadedMedia] {
        let journalURL = directory.appendingPathComponent("download-operation-v1.json")
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return records }
        try regularFile(journalURL)
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
        guard journal.version == 1, validRecord(journal.record) else { throw DownloadError.invalidIndex }
        let record = journal.record
        let final = directory.appendingPathComponent(record.filename)
        let staged = staging(record, in: directory, operation: journal.kind)
        let hasFinal = FileManager.default.fileExists(atPath: final.path)
        let hasStaged = FileManager.default.fileExists(atPath: staged.path)
        let indexed = records.first { $0.id == record.id }
        guard !hasFinal || !hasStaged, indexed == nil || indexed == record else {
            throw DownloadError.recoveryRequired("The journal and stored files disagree.")
        }
        var result = records
        switch journal.kind {
        case .add:
            if indexed == nil && hasStaged && !hasFinal {
                try regularFile(staged)
                let size = Int64(try staged.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                if size != record.byteCount {
                    try quarantineIncompleteAdd(record: record, staged: staged, journalURL: journalURL, directory: directory)
                    return records
                }
            }
            if hasFinal || hasStaged {
                let candidate = hasFinal ? final : staged
                try checkSize(candidate, record: record)
                if hasStaged { try FileManager.default.moveItem(at: staged, to: final) }
                if indexed == nil { result.insert(record, at: 0); try persist(result, in: directory) }
            } else if indexed != nil { throw DownloadError.recoveryRequired("An indexed download is missing its file.") }
        case .delete:
            if indexed != nil {
                if hasStaged { try checkSize(staged, record: record); try FileManager.default.moveItem(at: staged, to: final) }
                else if !hasFinal {
                    if journal.originalFileExisted == false {
                        result = records.filter { $0.id != record.id }
                        try persist(result, in: directory)
                    } else { throw DownloadError.recoveryRequired("A pending deletion cannot restore its missing file.") }
                }
            } else {
                guard !hasFinal else { throw DownloadError.recoveryRequired("An unindexed file conflicts with a delete journal.") }
                if hasStaged { try regularFile(staged); try FileManager.default.removeItem(at: staged) }
            }
        }
        try FileManager.default.removeItem(at: journalURL)
        return result
    }
}
