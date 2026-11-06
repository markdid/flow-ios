// SPDX-License-Identifier: GPL-3.0-only
import Foundation

public struct VideoReference: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public let addedAt: Date

    public init(url: URL, title: String = "", addedAt: Date = Date()) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased() else { throw LinkError.unsupportedURL }
        let components = url.path.split(separator: "/").map(String.init)
        let candidate: String?
        if host == "youtu.be", components.count == 1 {
            candidate = components.first
        } else if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"].contains(host) {
            if url.path == "/watch" {
                candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value
            } else if components.count == 2, ["shorts", "embed", "live"].contains(components[0]) {
                candidate = components[1]
            } else { candidate = nil }
        } else { candidate = nil }
        guard let id = candidate, id.utf8.count == 11,
              id.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { throw LinkError.unsupportedURL }
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? id : title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.addedAt = addedAt
    }

    private enum CodingKeys: String, CodingKey { case id, title, addedAt }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id = try values.decode(String.self, forKey: .id)
        guard id.utf8.count == 11,
              id.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: values, debugDescription: "Invalid video identifier")
        }
        self.id = id
        self.title = try values.decode(String.self, forKey: .title)
        self.addedAt = try values.decode(Date.self, forKey: .addedAt)
    }

    public var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
    public var embedURL: URL { URL(string: "https://www.youtube-nocookie.com/embed/\(id)?playsinline=1")! }
    public enum LinkError: LocalizedError {
        case unsupportedURL
        public var errorDescription: String? { "Enter a valid YouTube video, Shorts, live, or youtu.be link." }
    }
}
