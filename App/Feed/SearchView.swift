// SPDX-License-Identifier: GPL-3.0-only
import FlowCore
import SwiftUI

enum SearchSuggestions {
    static func fetch(_ query: String) async -> [String] {
        var components = URLComponents(string: "https://suggestqueries-clients6.youtube.com/complete/search")!
        components.queryItems = [.init(name: "client", value: "youtube"), .init(name: "ds", value: "yt"),
                                 .init(name: "hl", value: "en"), .init(name: "q", value: query)]
        guard let url = components.url,
              let (data, _) = try? await URLSession(configuration: .ephemeral).data(from: url),
              let body = String(data: data, encoding: .utf8),
              let start = body.firstIndex(of: "("), let end = body.lastIndex(of: ")"),
              let json = try? JSONSerialization.jsonObject(with: Data(body[body.index(after: start)..<end].utf8)) as? [Any],
              json.count > 1, let entries = json[1] as? [[Any]] else { return [] }
        return entries.compactMap { $0.first as? String }.prefix(10).map { $0 }
    }
}

@MainActor @Observable final class SearchModel {
    var query = "" { didSet { if query != submitted { suggest() } } }
    private(set) var items: [VideoItem] = []
    private(set) var filters: [SearchFilterGroup] = []
    private(set) var continuation: String?
    private(set) var loading = false
    private(set) var error: String?
    private(set) var submitted = ""
    private(set) var suggestions: [String] = []
    private(set) var recent: [String] = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []
    private var params: String?
    private var task: Task<Void, Never>?
    private var suggestTask: Task<Void, Never>?

    /// Puts the submitted query back after the field loses focus without a new search.
    func restoreSubmitted() {
        if !submitted.isEmpty, query != submitted { query = submitted }
    }

    func suggest() {
        suggestTask?.cancel()
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { suggestions = []; return }
        suggestTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let results = await SearchSuggestions.fetch(query)
            guard !Task.isCancelled else { return }
            suggestions = results
        }
    }

    func search(_ text: String? = nil, more: Bool = false, cache: MetadataCache) {
        if let text { query = text; params = nil }
        let query = more ? submitted : self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !(more && continuation == nil), !(more && loading) else { return }
        if !more {
            task?.cancel(); items = []; continuation = nil; submitted = query; self.query = query
            recent.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
            recent.insert(query, at: 0)
            recent = Array(recent.prefix(20))
            UserDefaults.standard.set(recent, forKey: "recentSearches")
        }
        loading = true; error = nil
        let token = more ? continuation : nil
        let params = params
        task = Task {
            do {
                let page = try await VideoSearchClient().search(query: query, continuation: token, params: params)
                guard !Task.isCancelled else { return }
                let new = page.items.filter { item in !item.isShort && !self.items.contains { $0.id == item.id } }
                cache.remember(new)
                self.items += new
                self.continuation = page.continuation
                if !page.filterGroups.isEmpty { self.filters = page.filterGroups }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            self.loading = false
        }
    }

    func apply(_ option: SearchFilterOption, cache: MetadataCache) {
        params = option.params
        search(cache: cache)
    }

    func removeRecent(_ text: String) {
        recent.removeAll { $0 == text }
        UserDefaults.standard.set(recent, forKey: "recentSearches")
    }
}

struct SearchView: View {
    @Environment(MetadataCache.self) private var cache
    @State private var model = SearchModel()
    @FocusState private var focused: Bool
    var initial = ""

    private var showingResults: Bool { !model.submitted.isEmpty && !focused }

    var body: some View {
        content
            .modifier(TopBar { searchField.padding(.horizontal, 16).padding(.bottom, 8) })
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu.disabled(!showingResults || model.filters.isEmpty)
                }
            }
            .onAppear {
                guard model.submitted.isEmpty else { return }
                if initial.isEmpty { focused = true } else { model.search(initial, cache: cache) }
            }
            .onChange(of: focused) { _, isFocused in
                if isFocused { model.suggest() } else { model.restoreSubmitted() }
            }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search YouTube", text: $model.query)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { submit() }
            if focused, !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(.fill.tertiary, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { focused = true }
    }

    private func submit(_ term: String? = nil) {
        focused = false
        model.search(term, cache: cache)
    }

    @ViewBuilder private var content: some View {
        if showingResults {
            ScrollView {
                LazyVStack(spacing: 22) {
                    ForEach(model.items) { video in
                        VideoCard(video: video)
                            .onAppear { if video.id == model.items.last?.id { model.search(more: true, cache: cache) } }
                    }
                    if model.loading {
                        if model.items.isEmpty { ForEach(0..<3, id: \.self) { _ in SkeletonCard() } }
                        else { ProgressView() }
                    } else if let error = model.error {
                        ErrorRow(message: error) { model.search(more: !model.items.isEmpty, cache: cache) }
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.immediately)
        } else {
            List {
                let terms = model.query.trimmingCharacters(in: .whitespaces).isEmpty ? model.recent : model.suggestions
                ForEach(terms, id: \.self) { term in
                    let isRecent = model.recent.contains(term)
                    Button { submit(term) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: isRecent ? "clock.arrow.circlepath" : "magnifyingglass").foregroundStyle(.secondary).frame(width: 20)
                            Text(term).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.left").font(.footnote).foregroundStyle(.tertiary)
                                .onTapGesture { model.query = term + " " }
                                .accessibilityLabel("Edit")
                        }
                    }
                    .swipeActions {
                        if isRecent { Button("Remove", role: .destructive) { model.removeRecent(term) } }
                    }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private var filterMenu: some View {
        Menu {
            ForEach(model.filters, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.options, id: \.label) { option in
                        Button { model.apply(option, cache: cache) } label: {
                            if option.selected { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
                        }
                    }
                }
            }
        } label: { Image(systemName: "slider.horizontal.3") }
        .accessibilityLabel("Filters")
    }
}

/// Pins content under the navigation bar so scrolling content passes beneath it.
private struct TopBar<Bar: View>: ViewModifier {
    @ViewBuilder var bar: Bar

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .top) { bar }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) { bar.background(.bar) }
        }
    }
}
