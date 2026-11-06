// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client Copyright (C) 2025-2026 A-EDev.
// Swift subset of ChannelTabsParser/ChannelGridParser, modified 2026-11-06.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ChannelTab: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let params: String?
    public let selected: Bool
}
public struct ChannelBrowsePage: Sendable {
    public let channelID: String
    public let title: String?
    public let tabs: [ChannelTab]
    public let notice: String?
    public let feed: VideoSearchPage
}
public enum ChannelBrowseParser {
    private typealias Object = [String: Any]
    public static func parse(_ data: Data, channelID: String) throws -> ChannelBrowsePage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? Object else { throw SearchError.invalidResponse }
        if root["error"] != nil { throw SearchError.serviceError }
        let metadata = (root["metadata"] as? Object)?["channelMetadataRenderer"] as? Object
        let contents = root["contents"] as? Object
        let browse = contents?["twoColumnBrowseResultsRenderer"] as? Object
        let rawTabs = objects(browse?["tabs"])
        let renderers = rawTabs.compactMap { ($0["tabRenderer"] ?? $0["expandableTabRenderer"]) as? Object }
        let tabs = renderers.enumerated().compactMap { index, renderer -> ChannelTab? in
            guard let title = renderer["title"] as? String else { return nil }
            let endpoint = renderer["endpoint"] as? Object
            let browse = endpoint?["browseEndpoint"] as? Object
            return ChannelTab(id: index, title: title, params: browse?["params"] as? String, selected: renderer["selected"] as? Bool == true)
        }
        let synthetic: Object
        var unsupportedContainer = false
        if let selected = renderers.first(where: { $0["selected"] as? Bool == true }), let content = selected["content"] as? Object {
            let entries: [Object]
            if let grid = content["richGridRenderer"] as? Object, grid["contents"] is [Any] {
                entries = objects(grid["contents"])
            } else if let section = content["sectionListRenderer"] as? Object, section["contents"] is [Any] {
                entries = objects(section["contents"])
            } else {
                entries = []
                unsupportedContainer = true
            }
            synthetic = ["onResponseReceivedCommands": [["appendContinuationItemsAction": ["continuationItems": entries]]]]
        } else if root["onResponseReceivedActions"] is [Any] {
            let commands: [Object] = objects(root["onResponseReceivedActions"]).compactMap { value in
                if value["appendContinuationItemsAction"] != nil { return value }
                if let reload = value["reloadContinuationItemsCommand"] as? Object {
                    return ["appendContinuationItemsAction": reload]
                }
                return nil
            }
            synthetic = ["onResponseReceivedCommands": commands]
        } else if root["onResponseReceivedCommands"] is [Any] { synthetic = root }
        else if let continuation = root["continuationContents"] as? Object,
                let grid = continuation["richGridContinuation"] as? Object {
            synthetic = ["onResponseReceivedCommands": [["appendContinuationItemsAction": ["continuationItems": objects(grid["contents"])]]]]
        } else if !tabs.isEmpty {
            synthetic = ["onResponseReceivedCommands": [["appendContinuationItemsAction": ["continuationItems": []]]]]
            unsupportedContainer = true
        } else { throw SearchError.unsupportedResponse }
        let feed: VideoSearchPage
        let notice: String?
        do {
            feed = try VideoSearchParser.parse(JSONSerialization.data(withJSONObject: synthetic))
            notice = unsupportedContainer ? SearchError.unsupportedResponse.localizedDescription : nil
        } catch SearchError.noSupportedVideos {
            feed = VideoSearchPage(videos: [], continuation: nil, filterGroups: [], presentation: [:])
            notice = SearchError.noSupportedVideos.localizedDescription
        }
        return ChannelBrowsePage(channelID: channelID, title: metadata?["title"] as? String, tabs: tabs, notice: notice, feed: feed)
    }
    private static func objects(_ value: Any?) -> [Object] { (value as? [Any] ?? []).compactMap { $0 as? Object } }
}

public struct ChannelBrowseClient {
    private let session: URLSession
    private let visitor: VisitorSession
    public init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
        visitor = VisitorSession(session: session)
    }
    public static func validChannelID(_ id: String) -> Bool {
        id.hasPrefix("UC") && id.utf8.count == 24 && id.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
    public static func request(channelID: String, params: String? = nil, continuation: String? = nil, visitorData: String? = nil) throws -> URLRequest {
        guard validChannelID(channelID) else { throw LibraryError.invalidData }
        var request = try VideoSearchClient.request(query: "channel", visitorData: visitorData)
        request.url = URL(string: "https://www.youtube.com/youtubei/v1/browse?prettyPrint=false")!
        guard let data = request.httpBody, var body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SearchError.invalidResponse }
        body.removeValue(forKey: "query")
        if let continuation { body["continuation"] = continuation }
        else {
            body["browseId"] = channelID
            if let params { body["params"] = params }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    public func browse(channelID: String, params: String? = nil, continuation: String? = nil) async throws -> ChannelBrowsePage {
        guard Self.validChannelID(channelID) else { throw LibraryError.invalidData }
        let identity = await visitor.visitorData()
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: Self.request(channelID: channelID, params: params, continuation: continuation, visitorData: identity))
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw SearchError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw SearchError.httpStatus(http.statusCode) }
        return try ChannelBrowseParser.parse(data, channelID: channelID)
    }
}
