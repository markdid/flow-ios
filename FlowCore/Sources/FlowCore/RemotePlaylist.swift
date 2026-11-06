// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client Copyright (C) 2025-2026 A-EDev.
// Adapted from VideoPlaylistPage.kt / YouTubePlaylistRepository.kt, 2026-11-06.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct RemotePlaylistID: Equatable, Sendable {
    public let value: String
    public init(_ input: String) throws {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if let url = URLComponents(string: input), let host = url.host {
            guard url.scheme == "https", ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"].contains(host.lowercased()),
                  ["/playlist", "/watch"].contains(url.path), url.user == nil, url.password == nil, url.port == nil,
                  let list = url.queryItems?.first(where: { $0.name == "list" })?.value else { throw LibraryError.invalidData }
            candidate = list
        } else { candidate = input }
        // Mixes use a different next endpoint; private account lists require authentication.
        guard (candidate.hasPrefix("PL") || candidate.hasPrefix("UU") || candidate.hasPrefix("OLAK5uy_")),
              (12...128).contains(candidate.utf8.count), candidate.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { throw LibraryError.invalidData }
        value = candidate
    }
}
public struct RemotePlaylistPage: Sendable {
    public let title: String?
    public let feed: VideoSearchPage
    public let isShortsGrid: Bool
}
public enum RemotePlaylistParser {
    private typealias Object = [String: Any]
    public static func parse(_ data: Data) throws -> RemotePlaylistPage {
        guard data.count <= 10_000_000, let root = try JSONSerialization.jsonObject(with: data) as? Object else { throw SearchError.invalidResponse }
        if root["error"] != nil { throw SearchError.serviceError }
        var nodes: [Object] = []
        var exceededBudget = false
        func walk(_ value: Any, _ depth: Int) {
            guard depth < 48, nodes.count < 20000 else { exceededBudget = true; return }
            if let object = value as? Object {
                nodes.append(object)
                for key in object.keys.sorted() { walk(object[key]!, depth + 1) }
            } else if let array = value as? [Any] { for child in array { walk(child, depth + 1) } }
        }
        var entries: [Any]?
        var grid = false
        if let actions = root["onResponseReceivedActions"] as? [Any] ?? root["onResponseReceivedCommands"] as? [Any] {
            let arrays = actions.compactMap { (($0 as? Object)?["appendContinuationItemsAction"] as? Object)?["continuationItems"] as? [Any] }
            if !arrays.isEmpty { entries = arrays.flatMap { $0 } }
        } else {
            // Follow verified primary browse paths. Never search secondaryContents or
            // arbitrary recommendation shelves for a playlist-looking container.
            func list(_ node: Object) -> ([Any], Bool)? {
                if let items = (node["playlistVideoListRenderer"] as? Object)?["contents"] as? [Any] { return (items, false) }
                if let items = (node["richGridRenderer"] as? Object)?["contents"] as? [Any] { return (items, true) }
                if let section = (node["itemSectionRenderer"] as? Object)?["contents"] as? [Any] {
                    if section.isEmpty || section.contains(where: { ($0 as? Object)?["lockupViewModel"] != nil }) { return (section, false) }
                    for child in section.compactMap({ $0 as? Object }) {
                        if let items = (child["playlistVideoListRenderer"] as? Object)?["contents"] as? [Any] { return (items, false) }
                        if let items = (child["richGridRenderer"] as? Object)?["contents"] as? [Any] { return (items, true) }
                    }
                }
                return nil
            }
            let contents = root["contents"] as? Object ?? [:]
            var primary = contents
            if let browse = contents["twoColumnBrowseResultsRenderer"] as? Object ?? contents["singleColumnBrowseResultsRenderer"] as? Object {
                let tabs = (browse["tabs"] as? [Any] ?? []).compactMap { ($0 as? Object)?["tabRenderer"] as? Object }
                guard let selected = tabs.first(where: { $0["selected"] as? Bool == true }), let content = selected["content"] as? Object else { throw SearchError.unsupportedResponse }
                primary = content
            }
            if let result = list(primary) { entries = result.0; grid = result.1 }
            else if let sections = (primary["sectionListRenderer"] as? Object)?["contents"] as? [Any] {
                for section in sections.compactMap({ $0 as? Object }) {
                    if let result = list(section) { entries = result.0; grid = result.1; break }
                }
                if sections.isEmpty { entries = [] }
            }
        }
        guard !exceededBudget else { throw SearchError.unsupportedResponse }
        guard let entries else { throw SearchError.unsupportedResponse }
        var unavailableCount = 0
        let normalized = entries.compactMap { item -> Object? in
            guard var object = item as? Object else { return nil }
            if let renderer = object["playlistVideoRenderer"] as? Object {
                if renderer["isPlayable"] as? Bool == false { unavailableCount += 1; return nil }
                object = ["videoRenderer": renderer]
            }
            if let model = object["continuationItemViewModel"] as? Object,
               let command = (model["continuationCommand"] as? Object)?["innertubeCommand"] as? Object {
                object = ["continuationItemRenderer": ["continuationEndpoint": command]]
            }
            return object
        }
        if !entries.isEmpty && normalized.isEmpty && unavailableCount == 0 { throw SearchError.noSupportedVideos }
        let synthetic: Object = ["onResponseReceivedCommands": [["appendContinuationItemsAction": ["continuationItems": normalized]]]]
        let feed = try VideoSearchParser.parse(JSONSerialization.data(withJSONObject: synthetic))
        nodes = []; walk(root["header"] ?? [:], 0)
        var title: String?
        for node in nodes {
            if let header = node["pageHeaderRenderer"] as? Object { title = header["pageTitle"] as? String }
            if title == nil, let header = node["playlistHeaderRenderer"] as? Object { title = text(header["title"]) }
            if title == nil, let header = node["pageHeaderViewModel"] as? Object { title = text(((header["title"] as? Object)?["dynamicTextViewModel"] as? Object)?["text"]) }
            if title != nil { break }
        }
        guard !exceededBudget else { throw SearchError.unsupportedResponse }
        return RemotePlaylistPage(title: title, feed: feed, isShortsGrid: grid)
    }
    private static func text(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        guard let object = value as? Object else { return nil }
        return object["simpleText"] as? String ?? object["content"] as? String ?? (object["runs"] as? [Object])?.compactMap { $0["text"] as? String }.joined()
    }
}
public struct RemotePlaylistClient {
    private let session: URLSession
    private let visitor: VisitorSession
    public init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session; visitor = VisitorSession(session: session) }
    public static func request(id: RemotePlaylistID, continuation: String? = nil, showUnavailable: Bool = false, visitorData: String? = nil) throws -> URLRequest {
        var request = try VideoSearchClient.request(query: "playlist", visitorData: visitorData)
        request.url = URL(string: "https://www.youtube.com/youtubei/v1/browse?prettyPrint=false")!
        var body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        body.removeValue(forKey: "query")
        if let continuation { body["continuation"] = continuation }
        else { body["browseId"] = "VL" + id.value; if showUnavailable { body["params"] = "wgYCCAA=" } }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    public func browse(id: RemotePlaylistID, continuation: String? = nil) async throws -> RemotePlaylistPage {
        let identity = await visitor.visitorData()
        func fetch(_ showUnavailable: Bool) async throws -> RemotePlaylistPage {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: Self.request(id: id, continuation: continuation, showUnavailable: showUnavailable, visitorData: identity))
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw SearchError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw SearchError.httpStatus(http.statusCode) }
            return try RemotePlaylistParser.parse(data)
        }
        let page = try await fetch(false)
        if continuation == nil && page.isShortsGrid {
            // Like upstream, try the pageable list for Shorts grids. Never swallow cancellation.
            do { let list = try await fetch(true); if !list.feed.videos.isEmpty { return RemotePlaylistPage(title: page.title ?? list.title, feed: list.feed, isShortsGrid: list.isShortsGrid) } }
            catch { try Task.checkCancellation() }
        }
        return page
    }
}
