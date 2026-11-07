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
            ForEach(model.comments) { comment in
                CommentRow(comment: comment, videoID: model.videoID)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .onAppear { if comment.id == model.comments.last?.id, model.continuation != nil { model.load(more: true) } }
            }
            if model.busy {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if let error = model.error {
                ErrorRow(message: error) { model.load(more: model.continuation != nil) }.listRowSeparator(.hidden)
            } else if model.loaded && model.comments.isEmpty {
                Text("No comments").foregroundStyle(.secondary).frame(maxWidth: .infinity).listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle(model.replies ? "Replies" : "Comments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.sorts.isEmpty && !model.replies {
                Menu {
                    ForEach(model.sorts) { option in
                        Button { model.select(option) } label: {
                            if option.token == model.selectedSort { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                        }
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease") }
                .accessibilityLabel("Sort")
            }
        }
        .task { if !model.loaded { model.load() } }
        .onDisappear { model.cancel() }
    }
}

struct CommentRow: View {
    let comment: VideoComment
    let videoID: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ChannelAvatar(url: comment.avatar, name: comment.author, size: 32)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    if comment.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary).accessibilityLabel("Pinned") }
                    Text(comment.author.isEmpty ? "Unknown" : comment.author)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, comment.isCreator ? 6 : 0).padding(.vertical, comment.isCreator ? 2 : 0)
                        .background(comment.isCreator ? Color(.tertiarySystemFill) : .clear, in: Capsule())
                    if let time = comment.published { Text("· " + time).font(.caption).foregroundStyle(.secondary) }
                }
                Text(comment.text).font(.subheadline).textSelection(.enabled)
                HStack(spacing: 16) {
                    Label(comment.likes?.isEmpty == false ? comment.likes! : "0", systemImage: "hand.thumbsup")
                    if comment.hearted { Image(systemName: "heart.fill").foregroundStyle(.red).accessibilityLabel("Hearted by creator") }
                }
                .font(.caption).foregroundStyle(.secondary)
                if let token = comment.repliesToken {
                    NavigationLink { VideoCommentsView(videoID: videoID, repliesToken: token) } label: {
                        Text(comment.replyCount.map { "\($0) \($0 == "1" ? "reply" : "replies")" } ?? "Replies")
                            .font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    }
                }
            }
        }
    }
}
