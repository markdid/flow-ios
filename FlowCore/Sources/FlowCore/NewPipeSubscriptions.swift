// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client Copyright (C) 2025-2026 A-EDev.
// Swift subset of NewPipeSubscriptionCodec.kt, modified 2026-11-06.
import Foundation

public struct NewPipeImportPreview: Sendable {
    public let subscriptions: [LocalSubscription]
    public let unresolvedURLs: [String]
    public let skipped: Int
}
public struct NewPipeExport: Sendable {
    public let data: Data
    public let skipped: Int
}
public enum SubscriptionTransferError: LocalizedError {
    case tooLarge, wrongFormat
    public var errorDescription: String? {
        switch self {
        case .tooLarge: return "Subscription import and export support at most 10 MB and 10,000 entries. No file was imported or exported."
        case .wrongFormat: return "This is not a valid NewPipe subscription JSON export. Malformed fields reject the entire file; nothing was imported."
        }
    }
}
public enum NewPipeSubscriptions {
    public static let maximumBytes = 10_000_000
    public static let maximumEntries = 10_000
    private struct Envelope: Decodable { let subscriptions: [Item] }
    private struct Item: Codable {
        let service_id: Int
        let url: String
        let name: String
        private enum CodingKeys: String, CodingKey { case service_id, url, name }
        init(url: String, name: String) { service_id = 0; self.url = url; self.name = name }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            service_id = try values.decodeIfPresent(Int.self, forKey: .service_id) ?? 0
            url = try values.decodeIfPresent(String.self, forKey: .url) ?? ""
            name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        }
    }
    private struct ExportEnvelope: Encodable {
        let app_version: String
        let app_version_int: Int
        let subscriptions: [Item]
    }
    public static func preview(_ data: Data, importedAt: Date = Date()) throws -> NewPipeImportPreview {
        guard data.count <= maximumBytes else { throw SubscriptionTransferError.tooLarge }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw SubscriptionTransferError.wrongFormat }
        guard envelope.subscriptions.count <= maximumEntries else { throw SubscriptionTransferError.tooLarge }
        var subscriptions: [LocalSubscription] = []
        var unresolved: [String] = []
        var seen = Set<String>()
        var skipped = 0
        for item in envelope.subscriptions {
            guard item.service_id == 0, let url = canonicalYouTubeURL(item.url) else { skipped += 1; continue }
            let parts = url.path.split(separator: "/").map(String.init)
            if parts.count >= 2, parts[0] == "channel", ChannelBrowseClient.validChannelID(parts[1]) {
                let id = parts[1]
                guard seen.insert(id).inserted else { skipped += 1; continue }
                let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                subscriptions.append(LocalSubscription(id: id, name: name.isEmpty ? id : name, subscribedAt: importedAt))
            } else if let first = parts.first, first.hasPrefix("@") || ((first == "c" || first == "user") && parts.count >= 2) {
                if seen.insert(url.absoluteString).inserted { unresolved.append(url.absoluteString) }
                else { skipped += 1 }
            } else { skipped += 1 }
        }
        return NewPipeImportPreview(subscriptions: subscriptions, unresolvedURLs: unresolved, skipped: skipped)
    }
    public static func export(_ subscriptions: [LocalSubscription]) throws -> NewPipeExport {
        let items = subscriptions.compactMap { subscription -> Item? in
            guard ChannelBrowseClient.validChannelID(subscription.id) else { return nil }
            return Item(url: "https://www.youtube.com/channel/\(subscription.id)", name: subscription.name.isEmpty ? subscription.id : subscription.name)
        }
        guard items.count <= maximumEntries else { throw SubscriptionTransferError.tooLarge }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(ExportEnvelope(app_version: "Flow iOS development", app_version_int: 1, subscriptions: items))
        guard data.count <= maximumBytes else { throw SubscriptionTransferError.tooLarge }
        return NewPipeExport(data: data, skipped: subscriptions.count - items.count)
    }
    private static func canonicalYouTubeURL(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: input), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil,
              ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"].contains(url.host?.lowercased() ?? "") else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"; components?.host = "www.youtube.com"
        components?.query = nil; components?.fragment = nil
        return components?.url
    }
}
