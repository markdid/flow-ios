// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import FlowCore
import WebKit

@main struct FlowPrototypeApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var downloads = DownloadManager()
    var body: some Scene {
        WindowGroup { LibraryView().environmentObject(library).environmentObject(downloads) }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var adding = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("An independent iOS port in development, inspired by Flow Android Client. The official embedded YouTube player is the default. Native playback remains experimental.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink("Search YouTube videos") { SearchView() }
                    NavigationLink("Playlists") { PlaylistsView() }
                    NavigationLink("Open YouTube playlist") { RemotePlaylistView() }
                    NavigationLink("Downloads") { DownloadsView() }
                    NavigationLink("Watch history") { HistoryView() }
                    NavigationLink("Subscriptions") { SubscriptionsView() }
                    NavigationLink("Import Google Takeout CSV") { TakeoutImportView() }
                    NavigationLink("Latest uploads") { SubscriptionFeedView() }
                }
                if library.loading { ProgressView("Loading library…") }
                Section("Saved videos") {
                    if library.videos.isEmpty { Text("Add a YouTube link to start your local library.") }
                    ForEach(library.videos) { video in
                        NavigationLink { PlaybackView(video: video) } label: {
                            Label(video.title, systemImage: "play.rectangle")
                        }
                        .contextMenu { PlaylistActions(video: video) }
                    }.onDelete(perform: library.remove)
                }
                Section("About") {
                    Link("Original Flow Android Client · GPL-3.0", destination: URL(string: "https://github.com/Flow-Tube/Flow")!)
                    Text("Background playback, complete downloads, music integration and full FlowNeuro recommendations remain incomplete.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Flow Prototype")
            .toolbar { Button { adding = true } label: { Label("Add video", systemImage: "plus") } }
            .sheet(isPresented: $adding) { AddVideoView() }
            .alert("Library error", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
                Button("OK") { library.error = nil }
            } message: { Text(library.error ?? "") }
        }
    }
}

struct AddVideoView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var title = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("YouTube link", text: $link).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("Title (optional)", text: $title)
                if let error { Text(error).foregroundStyle(.red) }
                Text("Bookmarks are stored in the app and may be included in your device backups. Opening a video connects to YouTube, which may receive your IP address and playback activity.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Add video")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    Task {
                    do {
                        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw VideoReference.LinkError.unsupportedURL }
                        if await library.add(try VideoReference(url: url, title: title)) { dismiss() }
                        else { error = library.error }
                    } catch { self.error = error.localizedDescription }
                    }
                }.disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }
}

struct PlaybackView: View {
    let video: VideoReference
    @State private var active = false
    @StateObject private var lifetime = EmbeddedPlayerLifetime()
    @State private var status = "Preparing official player…"
    @State private var failure: String?
    @State private var canRetryPage = false
    @State private var blockedNavigation: String?
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Keep diagnostics outside the official player's controls and minimum viewport.
                EmbeddedPlayer(video: video, active: active, lifetime: lifetime, status: $status, failure: $failure, canRetry: $canRetryPage, blockedNavigation: $blockedNavigation)
                    .frame(minWidth: 200, maxWidth: .infinity).frame(height: 240)
                Text(status).font(.footnote).foregroundStyle(.secondary)
                if let failure { Text(failure).font(.footnote).foregroundStyle(.red) }
                if canRetryPage { Button("Retry player page") { lifetime.retry() } }
                if let blockedNavigation { Text(blockedNavigation).font(.footnote).foregroundStyle(.secondary) }
                Text("Tap Play in YouTube's official player. A loaded page does not confirm playback. If YouTube asks you to sign in or confirm you are not a bot, use Open on YouTube to continue in YouTube or your browser. Signing in there does not sign this private embedded player in. This app does not bypass YouTube restrictions.")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("Open on YouTube", destination: video.watchURL)
                NavigationLink("Video details and related") { WatchDetailsView(video: video) }
                NavigationLink("Read comments") { VideoCommentsView(videoID: video.id) }
                PlaylistActions(video: video)
                NavigationLink("Try experimental native player") { NativePlayerView(video: video) }
                Text("Native extraction is incomplete and has not passed live playback verification. Embedded playback does not provide native downloads, SponsorBlock, background playback or watch-position tracking.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle(video.title).navigationBarTitleDisplayMode(.inline)
            .onAppear { active = true }
            .onDisappear { lifetime.stop(); active = false }
    }
}

@MainActor final class EmbeddedPlayerLifetime: ObservableObject {
    var stopPlayback: (() -> Void)?
    var retryPage: (() -> Void)?
    func retry() { retryPage?() }
    func stop() { stopPlayback?() }
}

struct EmbeddedPlayer: UIViewRepresentable {
    let video: VideoReference
    let active: Bool
    let lifetime: EmbeddedPlayerLifetime
    @Binding var status: String
    @Binding var failure: String?
    @Binding var canRetry: Bool
    @Binding var blockedNavigation: String?
    func makeCoordinator() -> Coordinator { Coordinator(status: $status, failure: $failure, canRetry: $canRetry, blockedNavigation: $blockedNavigation) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        let coordinator = context.coordinator
        lifetime.stopPlayback = { [weak view, weak coordinator] in
            guard let view else { return }
            coordinator?.deactivate(view)
        }
        lifetime.retryPage = { [weak view, weak coordinator] in
            guard let view else { return }
            coordinator?.retry(view)
        }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.update(view, video: video, active: active)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.deactivate(view)
        view.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let status: Binding<String>
        private let failure: Binding<String?>
        private let canRetry: Binding<Bool>
        private let blockedNavigation: Binding<String?>
        private var retryAllowed = false
        private var requestedVideo: VideoReference?
        private var loadedVideoID: String?
        private var active = false
        private var generation = UUID()
        private var currentNavigation: WKNavigation?
        private var documentLoading = false
        init(status: Binding<String>, failure: Binding<String?>, canRetry: Binding<Bool>, blockedNavigation: Binding<String?>) { self.status = status; self.failure = failure; self.canRetry = canRetry; self.blockedNavigation = blockedNavigation }
        func update(_ view: WKWebView, video: VideoReference, active: Bool) {
            guard active else { if self.active { deactivate(view) }; return }
            guard !self.active || loadedVideoID != video.id else { return }
            self.active = true; loadedVideoID = video.id; requestedVideo = video; retryAllowed = false; generation = UUID()
            do {
                let request = try EmbeddedPlaybackRequest.make(video: video, bundleIdentifier: Bundle.main.bundleIdentifier)
                publishBlocked(nil)
                publish("Loading official player…")
                documentLoading = true
                currentNavigation = view.load(request)
            } catch { publish("Official player could not be configured.", error: error.localizedDescription) }
        }
        func retry(_ view: WKWebView) {
            guard active, retryAllowed, let requestedVideo else { return }
            loadedVideoID = nil
            update(view, video: requestedVideo, active: true)
        }
        func deactivate(_ view: WKWebView) {
            retryAllowed = false; documentLoading = false
            active = false; generation = UUID(); loadedVideoID = nil; currentNavigation = nil
            view.pauseAllMediaPlayback(completionHandler: nil)
            view.stopLoading()
            view.loadHTMLString("", baseURL: nil)
        }
        private func publish(_ text: String, error: String? = nil, retry: Bool = false) {
            let expected = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.active, self.generation == expected else { return }
                self.status.wrappedValue = text; self.failure.wrappedValue = error; self.canRetry.wrappedValue = retry
            }
        }
        private func publishBlocked(_ text: String?) {
            let expected = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.active, self.generation == expected else { return }
                self.blockedNavigation.wrappedValue = text
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // YouTube's required frames/media resources remain untouched. Only the top-level
            // document (or a new-window request) is confined to this video's official embed.
            if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
            if !active {
                decisionHandler(navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
                return
            }
            if let requestedVideo, EmbeddedNavigationPolicy.permitsMainFrame(navigationAction.request.url, video: requestedVideo) {
                decisionHandler(.allow)
            } else {
                publishBlocked("YouTube requested another page. This view stays on the embedded player; Open on YouTube to continue there.")
                if navigationAction.targetFrame?.isMainFrame == true, navigationAction.navigationType == .other, documentLoading {
                    // A redirect/script continuation of the initial document is different from
                    // a separate popup or tapped link: cancelling it ends this load.
                    documentLoading = false; currentNavigation = nil; retryAllowed = false
                    publish("Player page could not finish in this view.", error: "YouTube requested a different page. Open on YouTube to continue.")
                }
                decisionHandler(.cancel)
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard active, let navigation, let currentNavigation, navigation === currentNavigation else { return }
            documentLoading = false
            publish("Official player page loaded. Tap Play; playback is not yet verified.")
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard active, let navigation, let currentNavigation, navigation === currentNavigation, (error as NSError).code != NSURLErrorCancelled else { return }
            documentLoading = false
            let failure = error as NSError
            retryAllowed = failure.domain == NSURLErrorDomain && [NSURLErrorTimedOut, NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed].contains(failure.code)
            publish("Player page failed to load.", error: error.localizedDescription, retry: retryAllowed)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            self.webView(webView, didFail: navigation, withError: error)
        }
    }
}
