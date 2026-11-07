// SPDX-License-Identifier: GPL-3.0-only
// Flow Android Client Copyright (C) 2025-2026 A-EDev.
// Swift subset of VideoCommentsPage.kt / CommentsParsing.kt / InnerTube.nextWatch,
// modified 2026-11-06. Read-only; plain text, no executable/rich-text commands.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct VideoComment: Identifiable, Equatable, Sendable {
    public let id: String
    public let author: String
    public let text: String
    public let published: String?
    public let likes: String?
    public let pinned: Bool
    public let repliesToken: String?
    public var avatar: URL? = nil
    public var replyCount: String? = nil
    public var isCreator = false
    public var hearted = false
}
public struct CommentSort: Identifiable, Equatable, Sendable {
    public var id: String { token }
    public let title: String
    public let token: String
    public let selected: Bool
}
public struct VideoCommentsPage: Sendable {
    public let comments: [VideoComment]
    public let continuation: String?
    public let sorts: [CommentSort]
    public let totalText: String?
    public let omittedEntries: Int
}
public struct VideoCommentsSeed: Sendable {
    public let token: String
    public let sorts: [CommentSort]
    public let totalText: String?
}
public enum VideoCommentsError: LocalizedError {
    case unavailable, unsupported
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "No supported comments entry was returned. Comments may be unavailable, disabled, or use a layout this port does not support."
        case .unsupported: return "This comments response uses an unsupported layout."
        }
    }
}
public enum VideoCommentsParser {
    private typealias Object = [String: Any]
    private static func objects(_ value: Any?) -> [Object] { (value as? [Any] ?? []).compactMap { $0 as? Object } }
    private static func path(_ value: Any?, _ keys: String...) -> Any? { keys.reduce(value) { ($0 as? Object)?[$1] } }
    private static func text(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        guard let object = value as? Object else { return nil }
        if let text = object["content"] as? String ?? object["simpleText"] as? String { return text }
        if object["runs"] is [Any] { return objects(object["runs"]).compactMap { $0["text"] as? String }.joined() }
        return nil
    }
    private static func token(_ renderer: Object) -> String? {
        let value = path(renderer, "continuationEndpoint", "continuationCommand", "token") as? String
            ?? path(renderer, "button", "buttonRenderer", "command", "continuationCommand", "token") as? String
        return value.flatMap { validToken($0) ? $0 : nil }
    }
    private static func validToken(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 100_000 }
    private static func sorts(_ menu: Any?) -> [CommentSort] {
        var seen = Set<String>()
        return objects(path(menu, "sortFilterSubMenuRenderer", "subMenuItems")).compactMap { item in
            guard let token = path(item, "serviceEndpoint", "continuationCommand", "token") as? String, validToken(token),
                  let title = text(item["title"]), !title.isEmpty, seen.insert(token).inserted else { return nil }
            return CommentSort(title: title, token: token, selected: item["selected"] as? Bool == true)
        }
    }
    private static func root(_ data: Data) throws -> Object {
        guard data.count <= 10_000_000, let root = try JSONSerialization.jsonObject(with: data) as? Object else { throw SearchError.invalidResponse }
        if root["error"] != nil { throw SearchError.serviceError }
        return root
    }
    public static func seed(_ data: Data) throws -> VideoCommentsSeed {
        let root = try root(data)
        let sections = objects(path(root, "contents", "twoColumnWatchNextResults", "results", "results", "contents"))
        let items = sections.compactMap { $0["itemSectionRenderer"] as? Object }.filter { $0["sectionIdentifier"] as? String == "comment-item-section" }
        guard let token = items.flatMap({ objects($0["contents"]) }).compactMap({ $0["continuationItemRenderer"] as? Object }).compactMap(token).first else { throw VideoCommentsError.unavailable }
        let panel = objects(root["engagementPanels"]).compactMap { $0["engagementPanelSectionListRenderer"] as? Object }.first { $0["panelIdentifier"] as? String == "engagement-panel-comments-section" }
        let header = path(panel, "header", "engagementPanelTitleHeaderRenderer") as? Object
        return VideoCommentsSeed(token: token, sorts: sorts(header?["menu"]), totalText: text(header?["contextualInfo"]))
    }
    public static func parse(_ data: Data, replies: Bool = false) throws -> VideoCommentsPage {
        let root = try root(data)
        guard root["onResponseReceivedEndpoints"] is [Any] else { throw VideoCommentsError.unsupported }
        let commands = objects(root["onResponseReceivedEndpoints"]).compactMap { ($0["reloadContinuationItemsCommand"] ?? $0["appendContinuationItemsAction"]) as? Object }
        let arrays = commands.compactMap { $0["continuationItems"] as? [Any] }
        guard !arrays.isEmpty else { throw VideoCommentsError.unsupported }
        var mutations: [String: Object] = [:]
        for mutation in objects(path(root, "frameworkUpdates", "entityBatchUpdate", "mutations")) {
            if let key = mutation["entityKey"] as? String, let payload = mutation["payload"] as? Object { mutations[key] = payload }
        }
        var comments: [VideoComment] = []; var seen = Set<String>()
        var continuation: String?; var header: Object?; var recognized = false; var hasCommentEntries = false
        let rawItems = arrays.flatMap { $0 }
        let entries = objects(rawItems)
        var omitted = rawItems.count - entries.count
        for entry in entries {
            if let value = entry["commentsHeaderRenderer"] as? Object { header = value; recognized = true; continue }
            if let item = entry["continuationItemRenderer"] as? Object, let value = token(item) { continuation = continuation ?? value; recognized = true; continue }
            let thread = entry["commentThreadRenderer"] as? Object
            if thread != nil || (replies && (entry["commentViewModel"] != nil || entry["commentRenderer"] != nil)) { hasCommentEntries = true }
            let rawModel = (thread ?? entry)["commentViewModel"] as? Object
            let model = rawModel?["commentViewModel"] as? Object ?? rawModel
            let replyRenderer = path(thread, "replies", "commentRepliesRenderer") as? Object
            let replyToken = objects(replyRenderer?["contents"]).compactMap { $0["continuationItemRenderer"] as? Object }.compactMap(token).first
            var comment: VideoComment?
            if (thread != nil || replies), let model, let key = model["commentKey"] as? String,
               let entity = mutations[key]?["commentEntityPayload"] as? Object,
               let properties = entity["properties"] as? Object,
               let id = properties["commentId"] as? String ?? model["commentId"] as? String, !id.isEmpty,
               let content = text(properties["content"]) {
                comment = VideoComment(id: id, author: path(entity, "author", "displayName") as? String ?? "", text: content,
                    published: properties["publishedTime"] as? String, likes: text(path(entity, "toolbar", "likeCountNotliked")),
                    pinned: [text(model["pinnedText"]), text(properties["pinnedText"])].contains(where: { $0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) || thread?["renderingPriority"] as? String == "RENDERING_PRIORITY_PINNED_COMMENT", repliesToken: replyToken)
                comment?.avatar = (path(entity, "author", "avatarThumbnailUrl") as? String).flatMap(URL.init(string:))
                comment?.replyCount = (path(entity, "toolbar", "replyCount") as? String).flatMap { $0.isEmpty ? nil : $0 }
                comment?.isCreator = path(entity, "author", "isCreator") as? Bool ?? false
                comment?.hearted = (path(entity, "toolbar", "heartActiveTooltip") as? String).map { !$0.isEmpty } ?? false
            } else if let legacy = path(thread, "comment", "commentRenderer") as? Object ?? (replies ? entry["commentRenderer"] as? Object : nil),
                      let id = legacy["commentId"] as? String, !id.isEmpty, let content = text(legacy["contentText"]) {
                comment = VideoComment(id: id, author: text(legacy["authorText"]) ?? "", text: content, published: text(legacy["publishedTimeText"]), likes: text(legacy["voteCount"]), pinned: legacy["pinnedCommentBadge"] != nil || thread?["renderingPriority"] as? String == "RENDERING_PRIORITY_PINNED_COMMENT", repliesToken: replyToken)
            }
            if let comment { recognized = true; if seen.insert(comment.id).inserted { comments.append(comment) } }
            else { omitted += 1 }
        }
        guard !hasCommentEntries || !comments.isEmpty else { throw VideoCommentsError.unsupported }
        guard omitted == 0 || !comments.isEmpty || continuation != nil else { throw VideoCommentsError.unsupported }
        guard rawItems.isEmpty || recognized else { throw VideoCommentsError.unsupported }
        return VideoCommentsPage(comments: comments, continuation: continuation, sorts: sorts(header?["sortMenu"]), totalText: text(header?["commentsCount"] ?? header?["countText"]), omittedEntries: omitted)
    }
}
public struct VideoCommentsClient {
    private let session: URLSession
    private let visitor: VisitorSession
    public init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session; visitor = VisitorSession(session: session) }
    public static func request(videoID: String? = nil, continuation: String? = nil, visitorData: String? = nil) throws -> URLRequest {
        guard (videoID == nil) != (continuation == nil) else { throw LibraryError.invalidData }
        if let videoID { guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)"), try VideoReference(url: url).id == videoID else { throw LibraryError.invalidData } }
        if let continuation { guard !continuation.isEmpty, continuation.utf8.count <= 100_000 else { throw LibraryError.invalidData } }
        var request = try VideoSearchClient.request(query: "comments", visitorData: visitorData)
        request.url = URL(string: "https://www.youtube.com/youtubei/v1/next?prettyPrint=false")!
        var body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        body.removeValue(forKey: "query")
        if let videoID { body["videoId"] = videoID }; if let continuation { body["continuation"] = continuation }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    private func fetch(videoID: String? = nil, continuation: String? = nil) async throws -> Data {
        let identity = await visitor.visitorData(); try Task.checkCancellation()
        let (data, response) = try await session.data(for: Self.request(videoID: videoID, continuation: continuation, visitorData: identity))
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw SearchError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw SearchError.httpStatus(http.statusCode) }
        return data
    }
    public func first(videoID: String) async throws -> VideoCommentsPage {
        let seed = try VideoCommentsParser.seed(await fetch(videoID: videoID))
        let page = try await page(continuation: seed.token)
        return VideoCommentsPage(comments: page.comments, continuation: page.continuation, sorts: page.sorts.isEmpty ? seed.sorts : page.sorts, totalText: page.totalText ?? seed.totalText, omittedEntries: page.omittedEntries)
    }
    public func page(continuation: String, replies: Bool = false) async throws -> VideoCommentsPage {
        try VideoCommentsParser.parse(await fetch(continuation: continuation), replies: replies)
    }
}
