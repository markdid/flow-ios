// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Flow Android Client, Copyright (C) 2025-2026 Flow | A-EDev.
// https://github.com/Flow-Tube/Flow at 3f3e2a6101fe511003f8b694876fe8c6ece89c66.
// NeuroContentStore.kt: 1,500 opened-video entries, strongest 12 topics, write-time pruning.
import Foundation

/// Local tag-rich topic cache, not the IDF corpus ledger or the user's complete brain.
/// Own one actor per file. Callers choose a keySpace matching their actual extractor version;
/// unstemmed candidate keys must never be labeled as Android spec-3 keys.
public actor NeuroContentStore {
    public enum StoreError: Error, Equatable {
        case invalidKeySpace, incompatibleSchema, incompatibleKeySpace, oversizedFile, invalidData
    }
    public struct Entry: Codable, Equatable, Sendable {
        public let topics: [String: Double]
        public let updatedAt: Date
    }
    private struct State: Codable {
        let schemaVersion: Int
        let keySpace: String
        var entries: [String: Entry]
    }
    public static let maximumEntries = 1500
    public static let topicsPerEntry = 12
    private static let maximumFileBytes = 16 * 1024 * 1024
    private let fileURL: URL
    private var state: State

    public init(fileURL: URL, keySpace: String) throws {
        guard !keySpace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              keySpace.utf16.count <= 128 else { throw StoreError.invalidKeySpace }
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= Self.maximumFileBytes else { throw StoreError.oversizedFile }
            let data = try Data(contentsOf: fileURL)
            guard data.count <= Self.maximumFileBytes else { throw StoreError.oversizedFile }
            let loaded = try JSONDecoder().decode(State.self, from: data)
            guard loaded.schemaVersion == 1 else { throw StoreError.incompatibleSchema }
            guard loaded.keySpace == keySpace else { throw StoreError.incompatibleKeySpace }
            guard loaded.entries.count <= Self.maximumEntries else { throw StoreError.invalidData }
            for (id, entry) in loaded.entries {
                guard Self.validID(id), entry.updatedAt.timeIntervalSince1970.isFinite,
                      !entry.topics.isEmpty, entry.topics.count <= Self.topicsPerEntry,
                      entry.topics.allSatisfy({ Self.validTopic($0.key, $0.value) }) else { throw StoreError.invalidData }
            }
            state = loaded
        } else {
            state = State(schemaVersion: 1, keySpace: keySpace, entries: [:])
        }
    }

    public func topics(for videoID: String) -> [String: Double]? { state.entries[videoID]?.topics }
    /// Batch ranking can await one snapshot instead of one actor call per candidate.
    public func snapshot() -> [String: Entry] { state.entries }

    /// Saves before updating memory. A failure leaves the previous in-memory snapshot intact.
    /// Empty input is ignored as upstream; malformed nonempty input is rejected, not persisted.
    public func put(videoID: String, topics: [String: Double], now: Date = Date()) throws {
        guard Self.validID(videoID), now.timeIntervalSince1970.isFinite else { throw StoreError.invalidData }
        guard !topics.isEmpty else { return }
        guard topics.allSatisfy({ Self.validTopic($0.key, $0.value) }) else { throw StoreError.invalidData }
        let strongest = topics.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(Self.topicsPerEntry)
        var next = state
        next.entries[videoID] = Entry(topics: Dictionary(uniqueKeysWithValues: strongest.map { ($0.key, $0.value) }), updatedAt: now)
        if next.entries.count > Self.maximumEntries {
            let retained = next.entries.sorted {
                $0.value.updatedAt == $1.value.updatedAt ? $0.key < $1.key : $0.value.updatedAt > $1.value.updatedAt
            }.prefix(Self.maximumEntries)
            next.entries = Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
        }
        try commit(next)
    }
    public func remove(videoID: String) throws {
        guard state.entries[videoID] != nil else { return }
        var next = state
        next.entries.removeValue(forKey: videoID)
        try commit(next)
    }
    public func clear() throws {
        var next = state
        next.entries = [:]
        try commit(next)
    }
    private func commit(_ next: State) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(next)
        guard data.count <= Self.maximumFileBytes else { throw StoreError.oversizedFile }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        state = next
    }
    private static func validID(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= 256
    }
    private static func validTopic(_ key: String, _ value: Double) -> Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && key.utf16.count <= 40
            && value.isFinite && value > 0 && value <= 1
    }
}
