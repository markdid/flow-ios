# Flow iOS foundation

Independent, incomplete SwiftUI iOS prototype inspired by **Flow Android Client**:
https://github.com/Flow-Tube/Flow

Upstream inspected: `3f3e2a6101fe511003f8b694876fe8c6ece89c66` (2026-11-06).
Licensed GPL-3.0-only; full upstream license retained in LICENSE. Not an official Flow release.
No upstream artwork or brand assets are included.

## Current build verification (2026-11-06)

[GitHub Actions run 42296567191](https://github.com/markdid/flow-ios/actions/runs/42296567191)
passed for source commit `8ec150106c0af8bb46a791b49936d28bac87ae62` on a standard
GitHub-hosted macOS runner: 188 FlowCore tests in debug and release, six dormant solver
gate tests, XcodeGen generation and an unsigned iOS Simulator app build (arm64/x86_64).
No simulator app launch, device test, live playback validation, signing or IPA was performed.
Older milestone notes below describe the evidence available when those features were added;
this build result supersedes their statements that Apple compilation had not yet run.

## Implemented source

- SwiftUI library/navigation and add/cancel/delete flows.
- YouTube URL validation, title normalization, duplicate replacement.
- Atomic app-local JSON persistence (may be included in device backups); corrupt existing libraries are not overwritten.
- User-initiated, nonpersistent WKWebView embedded playback and YouTube fallback link.
- Experimental native InnerTube video search with cancellation, bounded renderer parsing, pagination, server-provided search filters and save-to-library.
- Separate Swift package with validation, search fixture and serialization tests.

Embedded playback is deliberately limited. It is not Flow's native player, ad blocking,
background audio, downloads, or a proof that YouTube extraction works on iOS. YouTube
may refuse embedded videos. The request now supplies the actual app bundle identity according to YouTube’s documented iOS requirements, but Apple/live embedded playback is still unverified. Normal video links use this official player; native playback is an explicit experimental option.
Opening playback contacts YouTube; local bookmark storage does not make playback anonymous.

## Build on a Mac

Requires Xcode with iOS SDK, plus XcodeGen from its official Homebrew distribution.
No dependency is installed or account changed by this project.

1. From FlowCore: `swift test`.
2. From this folder: `xcodegen generate`.
3. Run `xcodebuild -project FlowPrototype.xcodeproj -scheme FlowPrototype -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build`.
4. Open FlowPrototype.xcodeproj, select an available iPhone simulator, and run.
5. For a physical device, choose your own bundle identifier and signing team in Xcode.

FlowCore has been compiled and its 188 tests pass on Linux with official Swift 6.0.3.
See [verification details](Documentation/Verification.md) for commands and configurations.
The SwiftUI app now compiles for iOS Simulator in GitHub Actions. Simulator UI/runtime
behavior and device playback remain untested. There is no IPA.

## GitHub Actions checks

`.github/workflows/ios.yml` uses a standard GitHub-hosted `macos-15` runner,
read-only repository permissions and no signing credentials. It runs FlowCore debug
and release tests, compiles and tests the dormant solver package's pre-execution
gates, generates the Xcode project with XcodeGen and builds an unsigned iOS Simulator
app. The workflow has a 30-minute timeout and cancels superseded runs.

The workflow passed at the source commit linked above. Compilation does not establish
simulator UI behavior, device playback, signing or installability. No IPA is produced.

## Verification on device still required

Add valid/invalid links, replace duplicate, restart and confirm persistence, delete,
cancel without saving, playback success/refusal, leave player and confirm playback stops,
repeat navigation, offline failure, corrupt-storage recovery, accessibility and rotation.

## Port roadmap

1. Target personal installation through Xcode signing. Confirm the selected Apple account’s provisioning limits; signing is not configured here. Keep GPL notices and corresponding source when redistributing.
2. Make the prototype compile and pass all tests on Mac; validate embedded playback.
3. Finish and test the partial search/channel-browse and native playback clients.
4. Port network and extraction behavior with real integration tests. Current upstream uses
   native InnerTube, signature handling, SABR, Android WebView PO-token machinery, and NewPipe/JVM types. The checked playback resolver has no NewPipe fallback; stale upstream architecture prose describes one. NewPipe/JVM and Android platform APIs cannot simply run on iOS.
5. Use AVFoundation/AVPlayer plus proper audio-session/lifecycle support for native playback.
6. Port storage, subscriptions, music and recommendation components incrementally. FlowNeuro
   has separable scoring logic but also Android Context, persistence and Java dependencies.
7. Measure background behavior and battery on real devices; review platform/content-service
   rules. App Store acceptance is not guaranteed by technical feasibility or GPL licensing.

## Search port scope

The search request and bounded first-page/continuation traversal are adapted from upstream
`InnerTube.webSearch`, `SearchPageParser.kt` and `FeedItemParsers.kt` at the commit above.
Standard video/gridVideo, video lockup and basic reel renderers, including bounded video shelves. Playlist results, advanced Shorts renderers, dynamic client-version discovery and locale selection are not ported. Visitor-data bootstrap is implemented with ephemeral caching and bounded retries. Server-provided filter groups are ported; unsupported content types still cannot be rendered.
The static upstream WEB version is a fallback, not a guarantee the service still accepts it.
No live YouTube requests were made during preparation. Search is unverified on device.
Fixture checks are synthetic structural examples, not captured production responses.

## Review fixes (2026-11-06)

- Xcode SWIFT_VERSION uses language mode 5.0; the Swift package tools version remains 5.9.
- Privacy text explicitly mentions device backups.
- Mixed JSON arrays preserve valid objects. Unknown command layouts and result-only unsupported
  renderers report errors instead of silently producing an empty screen. Recognized empty feeds
  display a no-results message.
- Search filters come from the response header, with upstream params passed on the initial
  request only. Pagination retains the active search.
- Added synthetic fixture tests covering these cases. These package tests now pass on Linux; see the verification report.

## Integrated source milestone

- Actor-backed library migration and serialized writes; playlists, ordering, history controls and
  local subscriptions have SwiftUI screens. Device backups may include app data.
- Native player navigation is connected, with embedded playback retained as fallback.
- Native watch checkpoints capture a library WatchSession once per playback visit. Clearing,
  removing, deleting or pausing history invalidates stale writes; no token is minted per callback.
- Experimental channel browse covers selected video grids, tab endpoints and continuation
  actions. Unsupported content is reported. Channel IDs are validated before requests.
- Search handles server-provided filters, visitor bootstrap, video lockups, basic reel items,
  video shelves, thumbnails and selected metadata.

App integration remains source-level only; portable package tests pass on Linux. No iOS build, simulator, live extraction or real-device
verification has passed in the Linux preparation environment. This is not yet a full or ready port.

## Subscription feed and lifecycle milestone

Recent subscription uploads now have an RSS-based source and screen, adapted from upstream
ChannelRssParser/ChannelRssClient. Refreshes use at most three concurrent channel fetches, one
bounded retry for transient failures, a 15-minute in-memory cache, and retain older successful
results when a channel fails. The cache is not yet persisted across app launches. RSS contains
only recent entries, not complete channel history. Unknown Shorts classification remains unknown.

Playback now restores saved position before accepting history checkpoints. Native controller
checkpoints include periodic, pause, playback end and stop; the view checkpoints when leaving
the active scene. Stale sessions and stale seeks remain guarded. These lifecycle changes require
real-device verification. Channel tabs remain usable when initial content is unsupported, and
action-only tab responses do not leave the previous tab falsely selected.

StreamURLResolver is used for direct URL validation only; no decipher/PO-token/SABR support is
claimed. The portable package fixtures now pass on Linux; this does not validate live playback.

## Subscription transfer and Neuro preparation

The subscription screen now links to local NewPipe JSON import/export. Import previews supported
channels and explicitly reports unresolved handles/legacy URLs before an atomic merge. Export
uses the system file destination chooser. See Documentation/SubscriptionTransfer.md for limits.

NeuroBatchScorer prepares the existing math component for explicit content vectors, with
batch-equivalence tests. It is not connected to feed ordering because tokenizer/profile-learning/
full-ranking components have not been faithfully ported. No recommendation feed is fabricated.
See Documentation/NeuroIntegrationBoundary.md. Portable package tests pass on Linux. SwiftUI integration remains uncompiled and untested.

## SponsorBlock subset

Native playback now has an explicit per-video SponsorBlock opt-in with privacy wording,
manual skipping and optional automatic-once behavior. This does not apply to embedded playback.
Mute/highlight actions, voting, submissions and complete upstream settings are not implemented.
See Documentation/SponsorBlock.md. The iOS integration remains uncompiled and unverified.

## Direct downloads subset

Native playback exposes a Download menu for supported direct muxed MP4/AAC sources. The app has
local download storage, cancellation, a downloads list, confirmed deletion and local playback.
HLS/DASH merging and background/resumable transfers are not implemented. The 1 GB limit is checked
after transfer, not a bandwidth cap. AVFoundation validation and all iOS UI remain unverified.
See Documentation/Downloads.md for the exact scope and storage behavior.

## Public YouTube playlists

The library now includes an explicit Open YouTube playlist screen with paged public-playlist browsing and per-video playback/local playlist actions. It accepts public PL, UU and OLAK5uy_ IDs or links. Modern list and Shorts-grid handling follow upstream, including a pageable-list retry for Shorts grids. Mixes, private lists, whole-playlist synchronization and queue-wide playback are not implemented. No live API or iOS UI verification has been performed. See Documentation/RemotePlaylists.md.

## Read-only video comments

Native playback now links to a comments screen with public comment pagination, sorting and replies. Modern entity and legacy renderers follow upstream; comments render as plain text. No posting/likes, rich-text actions or live compatibility verification. See Documentation/Comments.md. The iOS screen remains uncompiled in this Linux environment.

## Watch details and related videos

Native playback links to a first-page watch details screen: plain description, server-formatted views/date/factoids, validated channel navigation and related videos from YouTube. These are not FlowNeuro recommendations. Rich links/timestamps, related pagination and live metadata refresh are absent; stream extraction and Apple UI verification remain outstanding. See Documentation/WatchDetails.md.

## Local Takeout CSV import

The library includes local CSV import for Google Takeout subscriptions and playlist-video lists, with preview and an explicit import button. Playlist creation is atomic and preserves existing video titles. No network is used. ZIP/history/music-library/full restore support is absent. See Documentation/TakeoutImport.md; the file-picker UI still requires Apple verification.
