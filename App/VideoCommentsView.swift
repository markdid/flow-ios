// SPDX-License-Identifier: GPL-3.0-only
// New read-only comments UI, 2026-11-06.
import SwiftUI
import FlowCore

@MainActor final class VideoCommentsModel: ObservableObject {
    @Published private(set) var comments: [VideoComment] = []
    @Published private(set) var sorts: [CommentSort] = []
    @Published private(set) var selectedSort: String?
    @Published private(set) var totalText: String?
    @Published private(set) var continuation: String?
    @Published private(set) var busy = false
    @Published private(set) var loaded = false
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    let videoID: String
    let replies: Bool
    private var firstToken: String?
    private var seenTokens = Set<String>()
    private var hasOmissions = false
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private let client = VideoCommentsClient()
    init(videoID: String, repliesToken: String? = nil) { self.videoID = videoID; self.firstToken = repliesToken; self.replies = repliesToken != nil }
    func select(_ option: CommentSort) {
        cancel(); firstToken = option.token; selectedSort = option.token; load()
    }
    func load(more: Bool = false) {
        guard !busy, !more || continuation != nil else { return }
        let token = more ? continuation : firstToken
        if !more { comments = []; continuation = nil; seenTokens = []; loaded = false; hasOmissions = false }
        busy = true; error = nil; notice = nil
        let current = UUID(); generation = current
        task = Task {
            do {
                let page: VideoCommentsPage
                if let token { page = try await client.page(continuation: token, replies: replies) }
                else { page = try await client.first(videoID: videoID) }
                guard !Task.isCancelled, current == generation else { return }
                var seen = Set(comments.map(\.id))
                comments.append(contentsOf: page.comments.filter { seen.insert($0.id).inserted })
                if !page.sorts.isEmpty { sorts = page.sorts; if selectedSort == nil { selectedSort = page.sorts.first(where: { $0.selected })?.token } }
                if let total = page.totalText { totalText = total }
                hasOmissions = hasOmissions || page.omittedEntries > 0
                if hasOmissions { notice = "Some entries could not be displayed. These are partial results." }
                if let token { seenTokens.insert(token) }
                if let next = page.continuation, !seenTokens.contains(next) { continuation = next }
                else {
                    continuation = nil
                    if page.continuation != nil { notice = (notice.map { $0 + " " } ?? "") + "YouTube repeated a page token. More comments may exist, but pagination was stopped." }
                }
                loaded = true
            } catch {
                guard !Task.isCancelled, current == generation else { return }
                self.error = error.localizedDescription
            }
            if current == generation { busy = false }
        }
    }
    func cancel() { task?.cancel(); generation = UUID(); busy = false }
}
struct VideoCommentsView: View {
    @StateObject private var model: VideoCommentsModel
    init(videoID: String, repliesToken: String? = nil) { _model = StateObject(wrappedValue: VideoCommentsModel(videoID: videoID, repliesToken: repliesToken)) }
    var body: some View {
        List {
            Section {
                Text("Read-only public comments from YouTube. Opening this screen connects to YouTube. Posting, likes and rich-text links are not supported.").font(.footnote).foregroundStyle(.secondary)
                if let total = model.totalText { Text(total) }
                if !model.sorts.isEmpty && !model.replies {
                    Menu("Sort comments") {
                        ForEach(model.sorts) { option in Button(option.title) { model.select(option) }.disabled(option.token == model.selectedSort) }
                    }
                }
            }
            ForEach(model.comments) { comment in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(comment.author.isEmpty ? "Unknown author" : comment.author).font(.headline)
                        if comment.pinned { Image(systemName: "pin.fill").accessibilityLabel("Pinned") }
                    }
                    Text(comment.text).textSelection(.enabled)
                    HStack {
                        if let time = comment.published { Text(time) }
                        if let likes = comment.likes, !likes.isEmpty { Text("Likes: \(likes)") }
                    }.font(.caption).foregroundStyle(.secondary)
                    if let token = comment.repliesToken {
                        NavigationLink("View replies") { VideoCommentsView(videoID: model.videoID, repliesToken: token) }
                    }
                }.padding(.vertical, 4)
            }
            if let notice = model.notice { Text(notice).font(.footnote) }
            if let error = model.error { Text(error).foregroundStyle(.red) }
            if model.busy { ProgressView("Loading comments…") }
            else {
                if model.loaded && model.comments.isEmpty { Text("No comments in this response.") }
                if model.error != nil { Button("Retry") { model.load(more: model.continuation != nil) } }
                else if model.continuation != nil { Button("Load more") { model.load(more: true) } }
            }
        }.navigationTitle(model.replies ? "Replies" : "Comments")
            .task { if !model.loaded { model.load() } }
            .onDisappear { model.cancel() }
    }
}
