// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client Copyright (C) 2025-2026 A-EDev.
// Swift adaptation of ChannelRssParser/ChannelRssClient, modified 2026-11-06.
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SubscriptionUpload: Codable, Identifiable, Sendable, Equatable {
    public var id: String { video.id }
    public let video: VideoReference
    public let channelID: String
    public let channelName: String
    public let publishedAt: Date?
    public let viewCount: Int64
    public let isShort: Bool?
}
public struct ChannelRSSFeed: Codable, Sendable {
    public let channelName: String?
    public let uploads: [SubscriptionUpload]
}
public enum RSSFeedError: LocalizedError {
    case malformed, tooLarge, invalidChannel
    public var errorDescription: String? {
        switch self {
        case .malformed: return "YouTube returned a malformed or unsupported channel feed."
        case .tooLarge: return "The channel feed is larger than this app can safely parse."
        case .invalidChannel: return "This subscription does not contain a valid YouTube channel ID."
        }
    }
}

public enum ChannelRSSParser {
    public static func parse(_ data: Data, channelID: String, fallbackName: String = "") throws -> ChannelRSSFeed {
        guard ChannelBrowseClient.validChannelID(channelID) else { throw RSSFeedError.invalidChannel }
        guard data.count <= 2_000_000 else { throw RSSFeedError.tooLarge }
        guard let xml = String(data: data, encoding: .utf8),
              xml.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil else { throw RSSFeedError.malformed }
        let delegate = FeedDelegate(channelID: channelID, fallbackName: fallbackName)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        // FoundationXML can report success for a truncated document while retaining an error.
        guard parser.parse(), parser.parserError == nil, delegate.sawFeed else { throw RSSFeedError.malformed }
        return ChannelRSSFeed(channelName: delegate.channelName, uploads: delegate.uploads)
    }
}

private final class FeedDelegate: NSObject, XMLParserDelegate {
    let channelID: String
    let fallbackName: String
    var channelName: String?
    var uploads: [SubscriptionUpload] = []
    var sawFeed = false
    private var insideEntry = false
    private var currentText = ""
    private var videoID: String?
    private var title: String?
    private var published: Date?
    private var views: Int64 = 0
    private var isShort: Bool?
    private var seen = Set<String>()
    init(channelID: String, fallbackName: String) { self.channelID = channelID; self.fallbackName = fallbackName }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        currentText = ""
        if name == "feed" { sawFeed = true }
        if name == "entry" {
            insideEntry = true; videoID = nil; title = nil; published = nil; views = 0; isShort = nil
        } else if insideEntry && name == "statistics" {
            views = max(0, Int64(attributeDict["views"] ?? "") ?? 0)
        } else if insideEntry && name == "link", isShort == nil, let href = attributeDict["href"], let url = URL(string: href) {
            if url.path.hasPrefix("/shorts/") { isShort = true }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { currentText += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { currentText += String(data: CDATABlock, encoding: .utf8) ?? "" }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if insideEntry {
            if name == "videoid" { videoID = text }
            else if name == "title" && title == nil { title = text }
            else if name == "published" && published == nil {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                published = formatter.date(from: text)
                if published == nil { formatter.formatOptions = [.withInternetDateTime]; published = formatter.date(from: text) }
            } else if name == "entry" {
                insideEntry = false
                guard let id = videoID, let title, !title.isEmpty,
                      let url = URL(string: "https://www.youtube.com/watch?v=\(id)"),
                      let video = try? VideoReference(url: url, title: title, addedAt: published ?? .distantPast),
                      video.id == id, seen.insert(id).inserted else { return }
                uploads.append(SubscriptionUpload(video: video, channelID: channelID,
                    channelName: channelName ?? fallbackName, publishedAt: published, viewCount: views, isShort: isShort))
            }
        } else if name == "name", channelName == nil, !text.isEmpty { channelName = text }
    }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { nil }
}

public struct ChannelRSSClient: Sendable {
    private let session: URLSession
    public init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }
    public func fetch(channelID: String, fallbackName: String = "") async throws -> ChannelRSSFeed {
        guard ChannelBrowseClient.validChannelID(channelID) else { throw RSSFeedError.invalidChannel }
        var request = URLRequest(url: URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)")!)
        request.timeoutInterval = 30
        for attempt in 0...1 {
            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else { throw SearchError.invalidResponse }
                if attempt == 0, http.statusCode == 429 || http.statusCode >= 500 {
                    let seconds = min(10, max(1.5, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 1.5))
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    continue
                }
                guard (200..<300).contains(http.statusCode) else { throw SearchError.httpStatus(http.statusCode) }
                return try ChannelRSSParser.parse(data, channelID: channelID, fallbackName: fallbackName)
            } catch let error as URLError where attempt == 0 && error.code != .cancelled {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
        throw SearchError.invalidResponse
    }
}
