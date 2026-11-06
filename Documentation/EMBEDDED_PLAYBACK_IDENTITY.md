# Correct app identity for embedded playback

The existing direct WKWebView embed load omitted an explicit Referer. YouTube's current
[official WebView integration requirements](https://developers.google.com/youtube/terms/required-minimum-functionality#api-client-identity-and-credentials)
document supplying an HTTPS URL whose host is the app's actual bundle identifier. This also
applies to sideloaded apps using their installed identity. The official
[player API revision history](https://developers.google.com/youtube/iframe_api_revision_history)
identifies missing client identity as a cause of error 153.

`EmbeddedPlaybackRequest.make(video:bundleIdentifier:)` implements this request contract.
The caller must pass `Bundle.main.bundleIdentifier`, not another app's ID or a fabricated site.
The builder keeps the existing official privacy-enhanced embed URL and manual playback,
validates the identity, and throws on missing/invalid values rather than inventing one.
It performs no network access or JavaScript execution.

This corrects a documented integration omission. It is not a demonstrated diagnosis of an
observed error 153 on this app: no Apple/WebKit playback test has run. It is separate from the
prior refused InnerTube request; no attempt has been made to evade that refusal.

## Integration and validation

The UI integrator owns WKWebView changes. Use the built request in `load(_:)`, expose request
construction/navigation failures, and retain an ordinary “Open on YouTube” link. Document-load
completion is not proof of video playback and will not reliably capture an inline YouTube
player error. Owner-disabled embeds and other service restrictions must remain respected.

Five Linux tests cover actual-identity formatting, retained manual/privacy-enhanced request,
missing identity, injection rejection and length bounds. Apple verification remains necessary:
request identity propagation, actual video start/audio, fullscreen, return navigation, repeated
opens, unavailable/embedding-disabled videos, network errors and teardown stopping playback.

Verification 2026-11-06 14:20 UTC: the five identity tests passed, then the complete shared
FlowCore snapshot passed 183 Linux tests with zero failures using Swift 6.0.3. This does not
compile or exercise the WKWebView/SwiftUI app. Later shared-source edits require a fresh run.
