// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import FlowCore

struct VideoItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var title: String
    var channel: String?
    var channelID: String?
    var duration: String?
    var views: String?
    var published: String?
    var isShort: Bool = false

    var thumbnail: URL { URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")! }
    var largeThumbnail: URL { URL(string: "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg")! }
    var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
    var reference: VideoReference {
        (try? VideoReference(url: watchURL, title: title)) ?? (try! VideoReference(url: watchURL))
    }
    var subtitle: String {
        [channel, views.map(Self.shortViews), published].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    init(id: String, title: String, channel: String? = nil, channelID: String? = nil, duration: String? = nil,
         views: String? = nil, published: String? = nil, isShort: Bool = false) {
        self.id = id; self.title = title; self.channel = channel; self.channelID = channelID
        self.duration = duration; self.views = views; self.published = published; self.isShort = isShort
    }

    init(_ reference: VideoReference, _ presentation: VideoPresentation?) {
        self.init(id: reference.id, title: reference.title, channel: presentation?.channel, channelID: presentation?.channelID,
                  duration: presentation?.duration, views: presentation?.views, published: presentation?.published,
                  isShort: presentation?.isShort ?? false)
    }

    /// Fills missing fields from another copy of the same video.
    func merged(with other: VideoItem) -> VideoItem {
        var result = self
        if result.title.isEmpty { result.title = other.title }
        result.channel = result.channel ?? other.channel
        result.channelID = result.channelID ?? other.channelID
        result.duration = result.duration ?? other.duration
        result.views = result.views ?? other.views
        result.published = result.published ?? other.published
        return result
    }

    static func shortViews(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("watching") { return raw }
        let digits = raw.filter(\.isNumber)
        guard raw.contains(","), let count = Double(digits) else {
            return lower.contains("view") ? raw : raw + " views"
        }
        switch count {
        case 1_000_000_000...: return String(format: "%.1fB views", count / 1_000_000_000).replacingOccurrences(of: ".0B", with: "B")
        case 1_000_000...: return String(format: "%.1fM views", count / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        case 1_000...: return String(format: "%.0fK views", count / 1_000)
        default: return "\(Int(count)) views"
        }
    }
}

extension VideoSearchPage {
    var items: [VideoItem] { videos.map { VideoItem($0, presentation[$0.id]) } }
}

extension WatchDetails {
    var relatedItems: [VideoItem] { related.map { VideoItem($0, relatedPresentation[$0.id]) } }
}
