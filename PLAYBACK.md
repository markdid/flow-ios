# Native playback implementation

New source prepared 2026-11-06. This code has not been compiled against Apple's SDK or tested on a device. No claim of full Flow parity or working live YouTube extraction is made.

## Current default (2026-11-06)

Normal video navigation now opens the official privacy-enhanced YouTube embedded player. The direct WKWebView request identifies the app using its actual `Bundle.main.bundleIdentifier` via the tested `EmbeddedPlaybackRequest` builder. No fabricated identity, custom browser impersonation or restriction bypass is used. Native playback is an explicit experimental action. The one live native test returned `UNPLAYABLE`; no denied-request retry or alternate identity is part of this milestone.

Document load completion is displayed only as “page loaded”, never evidence that media played. Provider errors inside the player (including 101/150/153) remain visible in YouTube’s UI and are not programmatically detected. Diagnostics sit below the player, with an Open on YouTube fallback. Embedded playback has no native history checkpoints, downloads, SponsorBlock or background-playback promise. On navigation away, the source explicitly pauses media and clears the WebView; stale navigation callbacks are ignored. All WebKit behavior still needs Apple runtime verification.

## Native integration

- `NativePlayerView(video:)` provides a native experimental playback screen. It links to the existing `PlaybackView(video:)` embedded fallback. Keep that existing type or update this link if renaming it.
- `NativePlaybackController` is main-actor isolated and owns one AVPlayer. Call `start(videos:index:)` and always `stop()` when its owner exits. The supplied view does this on appear/disappear. Navigating to the fallback stops native playback first.
- `PlaybackQueue` implements next/previous/repeat/shuffle without Apple frameworks. It is in FlowCore and has synthetic XCTest coverage.
- To support a persistent mini-player or queue across screens, promote the controller to a single app-owned instance and move start/stop lifecycle responsibility there. Do not create multiple simultaneous controllers: iOS audio session and remote commands are process-wide.
- Add the audio background mode in app configuration for lock-screen/background playback eligibility. This implementation alone does not grant it. Background, AirPlay and interruption behavior require real-device validation.

## Supported source paths

Player response parser accepts HTTPS googlevideo HLS manifests, directly available muxed MP4 with audio, and AAC-only adaptive streams. It rejects ciphered URLs, untransformed `n` URLs, non-Google stream hosts and video-only streams. It makes an ephemeral anonymous InnerTube WEB player request only when playback is opened. No credentials, cookies or persistent tokens are stored. Playback still contacts YouTube and Google video servers.

The unverified AVPlayer source implements transport, rate, seeking, system player controls, Now Playing metadata, lock-screen commands, audio-session interruptions and headphone disconnection pause. Queue data and repeat/shuffle logic are available; the initial screen currently starts a one-item queue.

## Explicit gaps

Integrated signature deciphering, n transformation, native visitor/PO-token support, SABR, separate audio/video DASH composition, captions discovery, audio-language selection, persistent queue and thumbnail artwork remain incomplete. Separate source now includes direct MP4/AAC download/offline and read-only SponsorBlock subsets, but neither is full parity or device verified. The static WEB client version can expire. Most modern YouTube responses may require one of the unsupported extraction paths; use the embedded fallback rather than assuming native playback will work.

Run `swift test` inside FlowCore, then build with Xcode and test repeated navigation/cancellation, stream errors, audio-only mode, quality switching, repeat/queue boundaries, external interruption, headphone removal, screen lock and resume. Synthetic parser tests do not verify live YouTube behavior.

## Playback review corrections

Shuffle now uses a finite bag with actual traversal history (up to 1,000 entries). Repeat-off exhausts the bag; previous/next retrace the played order. Repeat-all starts a new cycle without an immediate repeat where multiple entries exist. Synthetic tests cover exhaustion, reverse traversal, cycle boundaries, append and replace.

Every asynchronous observer and remote-command callback is scoped to a playback-session identifier. Stopping invalidates the identifier before teardown, resets interruption-resume state, and blocks stale callbacks even after a new session starts. Item-resolution requests also retain their separate cancellation generation. A valid source selection clears earlier errors. Device testing must include stop/restart with queued remote commands and interruption notifications; these corrections are statically reviewed, not executed.

Per-item periodic time observers are invalidated before track replacement and reinstalled with the new item identity and generation. Both are checked inside the queued main-actor Task, so a delayed timestamp from a previous item cannot overwrite the new track's position. Apple-framework regression testing remains required: queue an A time event, switch to B or another source before its Task executes, and verify B's position/duration are unchanged by the old event; repeat across stop/start.

## Intent/replay corrections, 2026-11-06

An initial native source now honors Pause received while its request was pending instead of forcing autoplay merely because no prior source exists. Explicit Play at EOF seeks to zero before starting; unknown/invalid durations alone do not trigger resets. Portable `PlaybackStartPolicy` tests verify decision logic, not AVPlayer effects. Device checks must cover pause during resolution, retry/source switch while paused, natural EOF then Play, repeat-one/all, a failed restart seek and leaving during restart.

Source restoration is deliberately conservative: it now pauses after restoring saved position or switching source and asks the user to press Play. This avoids inferring user intent from AVKit's ambiguous seek/pause state. Only an initial source without position restoration starts intentionally; explicit EOF replay is handled separately. The embedded view offers same-identity Retry player page only for transient networking errors, not inline provider restrictions or TLS/security errors. Main-frame redirects outside the current embed are blocked with an Open on YouTube explanation; child frames/media resources are untouched. Real consent/link behavior remains part of required Apple testing.
