// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

@main struct FlowApp: App {
    @StateObject private var library = LibraryStore()
    @State private var cache = MetadataCache()
    @State private var player = PlayerModel()
    @State private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environment(cache)
                .environment(player)
                .environment(router)
                .onAppear {
                    player.configure(library: library, cache: cache)
                    DebugLaunch.run(player: player, router: router)
                }
        }
    }
}

struct RootView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        @Bindable var player = player
        TabView(selection: $router.tab) {
            tab(.home, path: $router.home) { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
            tab(.subscriptions, path: $router.subscriptions) { SubscriptionsView() }
                .tabItem { Label("Subscriptions", systemImage: "play.square.stack") }
            tab(.library, path: $router.library) { LibraryView() }
                .tabItem { Label("Library", systemImage: "books.vertical") }
        }
        .modifier(MiniPlayerAccessory())
        .overlay {
            if player.expanded {
                WatchView()
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }
        }
        .animation(.snappy(duration: 0.3), value: player.expanded)
    }

    private func tab<Content: View>(_ tab: AppTab, path: Binding<[Route]>, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: path) {
            content()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .channel(let id, let name): ChannelView(channelID: id, name: name)
                    case .playlist(let id): PlaylistView(id: id)
                    case .history: HistoryView()
                    case .search(let query): SearchView(initial: query)
                    }
                }
        }
        .tag(tab)
    }
}

/// Uses the system tab accessory on iOS 26+, an inset bar above the tab bar before that.
struct MiniPlayerAccessory: ViewModifier {
    @Environment(PlayerModel.self) private var player

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if player.current != nil {
                content.tabViewBottomAccessory { MiniPlayer() }
            } else {
                content
            }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if player.current != nil {
                    MiniPlayer()
                        .frame(height: 56)
                        .background(.bar)
                        .overlay(alignment: .top) { Divider() }
                        .padding(.bottom, 49)
                }
            }
        }
    }
}

/// Launch arguments for simulator checks: `-play <id>`, `-search <query>`, `-channel <id>`.
enum DebugLaunch {
    @MainActor static func run(player: PlayerModel, router: Router) {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        if let id = value("-play") { player.play(VideoItem(id: id, title: "")) }
        if arguments.contains("-comments") {
            Task { try? await Task.sleep(for: .seconds(6)); player.commentsPresented = true }
        }
        if let query = value("-search") { router.home.append(.search(query)) }
        if let id = value("-channel") { router.home.append(.channel(id: id, name: "")) }
    }
}
