// SPDX-License-Identifier: GPL-3.0-only
import FlowCore
import SwiftUI

@MainActor @Observable final class SearchModel {
    var query = ""
    private(set) var items: [VideoItem] = []
    private(set) var filters: [SearchFilterGroup] = []
    private(set) var continuation: String?
    private(set) var loading = false
    private(set) var error: String?
    private(set) var submitted = ""
    private var params: String?
    private var task: Task<Void, Never>?

    func search(more: Bool = false, cache: MetadataCache) {
        let query = more ? submitted : self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !(more && continuation == nil) else { return }
        if !more { task?.cancel(); items = []; continuation = nil; submitted = query }
        loading = true; error = nil
        let token = more ? continuation : nil
        let params = params
        task = Task {
            do {
                let page = try await VideoSearchClient().search(query: query, continuation: token, params: params)
                guard !Task.isCancelled else { return }
                let new = page.items.filter { item in !self.items.contains { $0.id == item.id } }
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
}

struct SearchView: View {
    @Environment(MetadataCache.self) private var cache
    @State private var model = SearchModel()
    @FocusState private var focused: Bool
    var initial = ""

    var body: some View {
        List {
            ForEach(model.items) { video in
                VideoRow(video: video)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .onAppear { if video.id == model.items.last?.id { model.search(more: true, cache: cache) } }
            }
            if model.loading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if let error = model.error {
                ErrorRow(message: error) { model.search(more: !model.items.isEmpty, cache: cache) }.listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle(model.submitted.isEmpty ? "Search" : model.submitted)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always))
        .onSubmit(of: .search) { model.search(cache: cache) }
        .toolbar {
            if !model.filters.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
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
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                    .accessibilityLabel("Filters")
                }
            }
        }
        .onAppear {
            if !initial.isEmpty, model.submitted.isEmpty { model.query = initial; model.search(cache: cache) }
        }
    }
}
