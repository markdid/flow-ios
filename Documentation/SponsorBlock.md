# SponsorBlock subset

Adapted from Flow Android Client SponsorBlockSegment, SponsorBlockActionPolicy,
SponsorBlockHandler and SponsorBlockRepository at upstream commit
3f3e2a6101fe511003f8b694876fe8c6ece89c66. Swift modifications: 2026-11-06.

The native player has an opt-in control for this video visit. The control discloses that the
video ID and IP address are sent to sponsor.ajay.app. The default mode is manual skipping.
An optional automatic-once mode skips each returned segment at most once per visit; rewinding
back into it leaves a manual skip option rather than causing another automatic jump. Disabling
or leaving cancels lookups and clears the active segment state.

Only skip action types and supported categories are requested/read. Mute, highlight points,
per-category action preferences, voting, segment submission, server customization and offline
segment persistence are not ported. No requests are made during tests. HTTP 404 means no
segments; other failures remain visible rather than masquerading as an empty success.

Core fixtures cover malformed ranges, duplicate IDs, unsupported/mute categories, Boolean
values masquerading as timestamps, skip-once behavior, paused playback and request construction.
The SwiftUI/AVPlayer integration still needs device verification: opt-in/off, delayed replies,
leaving/reentering, paused skips, approximate seeks, rewinds and segment overlap.

## Duration validation

Both automatic and manual skip targets now require a known, finite, positive video duration.
Ranges with an end beyond the actual duration are ignored, not clamped to the end of playback.
A valid outro ending exactly at duration remains eligible. Unknown-duration records stay loaded
but skipping is deferred until metadata supplies a usable duration. The UI explains this state.
Manual clicks revalidate against the current position/duration, and duration changes refresh
segment eligibility. Tests cover invalid bounds, exact-end/outro behavior, overlapping invalid
ranges, and unknown duration becoming known without losing the segments or consuming skip-once.
