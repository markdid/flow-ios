// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Flow Android Client, SearchPageParser.kt and InnerTube.webSearch.
// https://github.com/Flow-Tube/Flow/tree/3f3e2a6101fe511003f8b694876fe8c6ece89c66
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SearchFilterOption: Sendable {
    public let label: String
    public let selected: Bool
    public let params: String?
}

public struct SearchFilterGroup: Sendable {
    public let title: String
    public let options: [SearchFilterOption]
}

public struct VideoPresentation: Sendable {
    public let channel: String?
    public let channelID: String?
    public let duration: String?
    public let views: String?
    public let published: String?
    public let thumbnailURL: URL
    public let isShort: Bool
}

public struct VideoSearchPage: Sendable {
    public let videos: [VideoReference]
    public let continuation: String?
    public let filterGroups: [SearchFilterGroup]
    public let presentation: [String: VideoPresentation]
}

public enum VideoSearchParser {
    private typealias Object = [String: Any]
    public static func parse(_ data: Data) throws -> VideoSearchPage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? Object else { throw SearchError.invalidResponse }
        if root["error"] != nil { throw SearchError.serviceError }
        let contents = root["contents"] as? Object
        let twoColumn = contents?["twoColumnSearchResultsRenderer"] as? Object
        let primary = twoColumn?["primaryContents"] as? Object
        let sections = primary?["sectionListRenderer"] as? Object
        let entries: [Object]
        if let sections {
            guard sections["contents"] is [Any] else { throw SearchError.unsupportedResponse }
            entries = flatten(sections["contents"])
        } else if root["onResponseReceivedCommands"] is [Any] {
            let actions = objects(root["onResponseReceivedCommands"]).compactMap { $0["appendContinuationItemsAction"] as? Object }
            guard !actions.isEmpty, actions.contains(where: { $0["continuationItems"] is [Any] }) else { throw SearchError.unsupportedResponse }
            entries = actions.flatMap { flatten($0["continuationItems"]) }
        } else { throw SearchError.unsupportedResponse }
        var seen = Set<String>()
        var videos: [VideoReference] = []
        var continuation: String?
        var presentation: [String: VideoPresentation] = [:]
        for entry in entries.flatMap(expandShelf) {
            let item = entry["continuationItemRenderer"] as? Object
            let endpoint = item?["continuationEndpoint"] as? Object
            let command = endpoint?["continuationCommand"] as? Object
            if let token = command?["token"] as? String, !token.isEmpty { continuation = token; continue }
            let rich = entry["richItemRenderer"] as? Object
            let content = rich?["content"] as? Object ?? entry
            guard let parsed = video(content), seen.insert(parsed.0.id).inserted else { continue }
            videos.append(parsed.0)
            presentation[parsed.0.id] = parsed.1
        }
        if videos.isEmpty, continuation == nil, !entries.isEmpty {
            throw SearchError.noSupportedVideos
        }
        return VideoSearchPage(videos: videos, continuation: continuation, filterGroups: filters(root), presentation: presentation)
    }
    private static func video(_ content: Object) -> (VideoReference, VideoPresentation)? {
        let renderer = (content["videoRenderer"] ?? content["gridVideoRenderer"] ?? content["reelItemRenderer"]) as? Object
        let lockup = content["lockupViewModel"] as? Object
        let metadata = (lockup?["metadata"] as? Object)?["lockupMetadataViewModel"] as? Object
        if let type = lockup?["contentType"] as? String,
           ["LOCKUP_CONTENT_TYPE_PLAYLIST", "LOCKUP_CONTENT_TYPE_PODCAST", "LOCKUP_CONTENT_TYPE_ALBUM", "LOCKUP_CONTENT_TYPE_COURSE", "LOCKUP_CONTENT_TYPE_CHANNEL"].contains(type) { return nil }
        guard let id = renderer?["videoId"] as? String ?? lockup?["contentId"] as? String,
              id.utf8.count == 11, id.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }),
              let title = text(renderer?["title"] ?? renderer?["headline"] ?? metadata?["title"]),
              let url = URL(string: "https://www.youtube.com/watch?v=\(id)"),
              let reference = try? VideoReference(url: url, title: title) else { return nil }
        let ownerRuns = renderer?["ownerText"] ?? renderer?["shortBylineText"] ?? renderer?["longBylineText"]
        let rows = objects(path(metadata, "metadata", "contentMetadataViewModel", "metadataRows"))
        let rowTexts = rows.map { objects($0["metadataParts"]).compactMap { text($0["text"]) } }
        let parts = rowTexts.flatMap { $0 }
        func isViews(_ value: String) -> Bool {
            let lower = value.lowercased()
            return lower.contains("view") || lower.contains("watching") || (value.last.map { "KMB".contains($0) } ?? false) && value.first?.isNumber == true
        }
        func isDate(_ value: String) -> Bool {
            let lower = value.lowercased()
            return lower.contains("ago") || lower.hasPrefix("streamed") || lower.hasPrefix("premiere") || lower.hasPrefix("scheduled")
        }
        let channel = text(ownerRuns) ?? rowTexts.first?.first.flatMap { isViews($0) || isDate($0) ? nil : $0 }
        let channelID = (objects(path(ownerRuns, "runs")).compactMap { path($0, "navigationEndpoint", "browseEndpoint", "browseId") as? String }.first
            ?? path(metadata, "image", "decoratedAvatarViewModel", "rendererContext", "commandContext", "onTap", "innertubeCommand", "browseEndpoint", "browseId") as? String)
            .flatMap { $0.hasPrefix("UC") ? $0 : nil }
        let badge = objects(path(lockup, "contentImage", "thumbnailViewModel", "overlays"))
            .flatMap { objects(path($0, "thumbnailBottomOverlayViewModel", "badges")) + objects(path($0, "thumbnailOverlayBadgeViewModel", "thumbnailBadges")) }
            .compactMap { path($0, "thumbnailBadgeViewModel", "text") as? String }.first
        let isShort = content["reelItemRenderer"] != nil || ["LOCKUP_CONTENT_TYPE_SHORTS", "LOCKUP_CONTENT_TYPE_SHORT"].contains(lockup?["contentType"] as? String ?? "")
        let details = VideoPresentation(channel: channel, channelID: channelID,
            duration: text(renderer?["lengthText"]) ?? badge,
            views: text(renderer?["viewCountText"]) ?? parts.first(where: isViews),
            published: text(renderer?["publishedTimeText"]) ?? parts.first(where: isDate),
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(reference.id)/hqdefault.jpg")!, isShort: isShort)
        return (reference, details)
    }
    private static func expandShelf(_ entry: Object) -> [Object] {
        let rich = entry["richSectionRenderer"] as? Object
        let holder = rich?["content"] as? Object ?? entry
        if let grid = holder["gridShelfViewModel"] as? Object { return objects(grid["contents"]) }
        guard let shelf = (holder["shelfRenderer"] ?? holder["reelShelfRenderer"]) as? Object else { return [entry] }
        if shelf["items"] is [Any] { return objects(shelf["items"]) }
        if shelf["contents"] is [Any] { return objects(shelf["contents"]) }
        let content = shelf["content"] as? Object
        for key in ["verticalListRenderer", "horizontalListRenderer", "expandedShelfContentsRenderer", "gridRenderer"] {
            if let list = content?[key] as? Object, list["items"] is [Any] { return objects(list["items"]) }
        }
        return [entry]
    }
    private static func filters(_ root: Object) -> [SearchFilterGroup] {
        let header = root["header"] as? Object
        let renderer = header?["searchHeaderRenderer"] as? Object
        let filterButton = renderer?["searchFilterButton"] as? Object
        let button = filterButton?["buttonRenderer"] as? Object
        let command = button?["command"] as? Object
        let action = command?["openPopupAction"] as? Object
        let popup = action?["popup"] as? Object
        let dialog = popup?["searchFilterOptionsDialogRenderer"] as? Object
        return objects(dialog?["groups"]).compactMap { entry in
            guard let group = entry["searchFilterGroupRenderer"] as? Object,
                  let title = text(group["title"]) else { return nil }
            let options = objects(group["filters"]).compactMap { value -> SearchFilterOption? in
                guard let filter = value["searchFilterRenderer"] as? Object,
                      let label = text(filter["label"]) else { return nil }
                let endpoint = filter["navigationEndpoint"] as? Object
                let search = endpoint?["searchEndpoint"] as? Object
                return SearchFilterOption(label: label,
                    selected: filter["status"] as? String == "FILTER_STATUS_SELECTED",
                    params: search?["params"] as? String)
            }
            return options.isEmpty ? nil : SearchFilterGroup(title: title, options: options)
        }
    }
    private static func objects(_ value: Any?) -> [Object] {
        (value as? [Any] ?? []).compactMap { $0 as? Object }
    }
    private static func path(_ value: Any?, _ keys: String...) -> Any? { keys.reduce(value) { ($0 as? Object)?[$1] } }
    private static func flatten(_ value: Any?) -> [Object] {
        objects(value).flatMap { entry -> [Object] in
            guard let section = entry["itemSectionRenderer"] as? Object,
                  section["contents"] is [Any] else { return [entry] }
            return objects(section["contents"])
        }
    }
    private static func text(_ value: Any?) -> String? {
        if let string = value as? String { return string.isEmpty ? nil : string }
        guard let object = value as? Object else { return nil }
        if let simple = object["simpleText"] as? String,
           !simple.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return simple }
        if let content = object["content"] as? String, !content.isEmpty { return content }
        let value = objects(object["runs"]).compactMap { ($0["text"] ?? $0["content"]) as? String }.joined()
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }
}

public enum SearchError: LocalizedError {
    case invalidResponse, unsupportedResponse, noSupportedVideos, serviceError, emptyQuery, httpStatus(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "YouTube returned an invalid response."
        case .unsupportedResponse: return "This YouTube response layout is not supported yet."
        case .noSupportedVideos: return "YouTube returned results, but none use a video format supported by this prototype."
        case .serviceError: return "YouTube rejected the search request."
        case .emptyQuery: return "Enter a search query."
        case .httpStatus(let code): return "YouTube returned HTTP \(code). Please try again later."
        }
    }
}

public struct VideoSearchClient {
    private let session: URLSession
    private let visitorSession: VisitorSession
    public init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
        self.visitorSession = VisitorSession(session: session)
    }
    public static func request(query: String, continuation: String? = nil, params: String? = nil, visitorData: String? = nil) throws -> URLRequest {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw SearchError.emptyQuery }
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/search?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        let version = "2.20260710.06.00"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("SOCS=CAE=", forHTTPHeaderField: "Cookie")
        request.setValue("en, en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0", forHTTPHeaderField: "User-Agent")
        var client: [String: Any] = ["clientName": "WEB", "clientVersion": version, "hl": "en", "gl": "US", "originalUrl": "https://www.youtube.com", "platform": "DESKTOP", "utcOffsetMinutes": 0]
        if let visitorData {
            client["visitorData"] = visitorData
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        var body: [String: Any] = ["context": ["client": client, "user": [String: Any]()]]
        if let continuation { body["continuation"] = continuation } else {
            body["query"] = query
            if let params { body["params"] = params }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    public func search(query: String, continuation: String? = nil, params: String? = nil) async throws -> VideoSearchPage {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SearchError.emptyQuery }
        let visitor = await visitorSession.visitorData()
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: Self.request(query: query, continuation: continuation, params: params, visitorData: visitor))
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw SearchError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw SearchError.httpStatus(response.statusCode) }
        return try VideoSearchParser.parse(data)
    }
}
