// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client Copyright (C) 2025-2026 A-EDev.
// Swift subset of VideoDescriptionPage.kt / WatchMetadataResponse.kt, 2026-11-06.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct WatchFact: Equatable, Sendable { public let value: String; public let label: String }
public struct WatchChannel: Equatable, Sendable { public let name: String; public let id: String?; public let subscribers: String? }
public struct WatchDetails: Sendable {
    public let title: String?
    public let description: String?
    public let views: String?
    public let published: String?
    public let facts: [WatchFact]
    public let channel: WatchChannel?
    public let related: [VideoReference]
    public let relatedNotice: String?
    public var relatedPresentation: [String: VideoPresentation] = [:]
    public var relatedContinuation: String?
}
public enum WatchDetailsParser {
    private typealias Object = [String: Any]
    private static func objects(_ value: Any?) -> [Object] { (value as? [Any] ?? []).compactMap { $0 as? Object } }
    private static func path(_ value: Any?, _ keys: String...) -> Any? { keys.reduce(value) { ($0 as? Object)?[$1] } }
    private static func text(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        guard let object = value as? Object else { return nil }
        if let value = object["content"] as? String ?? object["simpleText"] as? String { return value }
        if object["runs"] is [Any] { return objects(object["runs"]).compactMap { $0["text"] as? String }.joined() }
        return nil
    }
    public static func parse(_ data: Data) throws -> WatchDetails {
        guard data.count <= 10_000_000, let root = try JSONSerialization.jsonObject(with: data) as? Object else { throw SearchError.invalidResponse }
        if root["error"] != nil { throw SearchError.serviceError }
        guard let watch = path(root, "contents", "twoColumnWatchNextResults") as? Object else { throw SearchError.unsupportedResponse }
        let results = objects(path(watch, "results", "results", "contents"))
        let primary = results.compactMap { $0["videoPrimaryInfoRenderer"] as? Object }.first
        let secondary = results.compactMap { $0["videoSecondaryInfoRenderer"] as? Object }.first
        let panels = objects(root["engagementPanels"]).compactMap { $0["engagementPanelSectionListRenderer"] as? Object }.filter { $0["panelIdentifier"] as? String == "engagement-panel-structured-description" }
        let items = panels.flatMap { objects(path($0, "content", "structuredDescriptionContentRenderer", "items")) }
        let description = text(secondary?["attributedDescription"])
            ?? items.compactMap { text(path($0, "expandableVideoDescriptionBodyRenderer", "attributedDescriptionBodyText")) }.first
        var channel: WatchChannel?
        let structuredChannel = items.compactMap { item -> WatchChannel? in
            guard let card = item["videoDescriptionInfocardsSectionRenderer"] as? Object,
                  let name = text(card["sectionTitle"]), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let id = path(card, "channelEndpoint", "browseEndpoint", "browseId") as? String
            return WatchChannel(name: name, id: id.flatMap { ChannelBrowseClient.validChannelID($0) ? $0 : nil }, subscribers: text(card["sectionSubtitle"]))
        }.first
        if let structuredChannel { channel = structuredChannel
        } else if let owner = path(secondary, "owner", "videoOwnerRenderer") as? Object, let name = text(owner["title"]), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let id = path(owner, "navigationEndpoint", "browseEndpoint", "browseId") as? String
            channel = WatchChannel(name: name, id: id.flatMap { ChannelBrowseClient.validChannelID($0) ? $0 : nil }, subscribers: text(owner["subscriberCountText"]))
        }
        let facts = items.flatMap { objects(path($0, "videoDescriptionHeaderRenderer", "factoid")) }.compactMap { wrapper -> WatchFact? in
            let renderer = wrapper["factoidRenderer"] as? Object ?? wrapper.keys.sorted().compactMap { path(wrapper[$0], "factoid", "factoidRenderer") as? Object }.first
            guard let renderer, let value = text(renderer["value"]), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return WatchFact(value: value, label: text(renderer["label"]) ?? "")
        }
        let rawRelated = path(watch, "secondaryResults", "secondaryResults", "results") as? [Any]
        var related: [VideoReference] = []; var notice: String?; var relatedPresentation: [String: VideoPresentation] = [:]
        if let rawRelated {
            var normalized: [Object] = []; var omitted = 0; var exhausted = false
            func flatten(_ values: [Any], depth: Int) {
                guard depth < 16, normalized.count < 1000 else { exhausted = true; return }
                for value in values {
                    guard let item = value as? Object else { omitted += 1; continue }
                    if let renderer = item["compactVideoRenderer"] as? Object { normalized.append(["videoRenderer": renderer]) }
                    else if let lockup = item["lockupViewModel"] as? Object {
                        if let type = lockup["contentType"] as? String, type != "LOCKUP_CONTENT_TYPE_VIDEO" { omitted += 1 }
                        else { normalized.append(item) }
                    } else if let children = path(item, "compactAutoplayRenderer", "contents") as? [Any] ?? path(item, "itemSectionRenderer", "contents") as? [Any] { flatten(children, depth: depth + 1) }
                    else { omitted += 1 }
                    if normalized.count >= 1000 { exhausted = true; break }
                }
            }
            flatten(rawRelated, depth: 0)
            var seen = Set<String>()
            for item in normalized {
                let synthetic: Object = ["onResponseReceivedCommands": [["appendContinuationItemsAction": ["continuationItems": [item]]]]]
                do {
                    let page = try VideoSearchParser.parse(JSONSerialization.data(withJSONObject: synthetic))
                    for video in page.videos where seen.insert(video.id).inserted { related.append(video); relatedPresentation[video.id] = page.presentation[video.id] }
                } catch SearchError.noSupportedVideos { omitted += 1 }
            }
            if omitted > 0 || exhausted { notice = "Some related items could not be displayed. This is a partial first page." }
        } else { notice = "No supported related-video section was returned." }
        guard primary != nil || secondary != nil || !items.isEmpty || rawRelated != nil else { throw SearchError.unsupportedResponse }
        return WatchDetails(title: text(primary?["title"]), description: description,
            views: text(path(primary, "viewCount", "videoViewCountRenderer", "viewCount")), published: text(primary?["dateText"]),
            facts: facts, channel: channel, related: related, relatedNotice: notice, relatedPresentation: relatedPresentation)
    }
}
public struct WatchDetailsClient {
    private let session: URLSession
    private let visitor: VisitorSession
    public init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session; visitor = VisitorSession(session: session) }
    public func details(videoID: String) async throws -> WatchDetails {
        // Validate before starting the optional visitor-bootstrap request.
        _ = try VideoCommentsClient.request(videoID: videoID)
        let identity = await visitor.visitorData(); try Task.checkCancellation()
        let (data, response) = try await session.data(for: VideoCommentsClient.request(videoID: videoID, visitorData: identity))
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw SearchError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw SearchError.httpStatus(http.statusCode) }
        return try WatchDetailsParser.parse(data)
    }
}
