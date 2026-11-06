# Read-only video comments

Swift subset implemented 2026-11-06 from upstream commit 3f3e2a6101fe511003f8b694876fe8c6ece89c66:
- `innertube/pages/VideoCommentsPage.kt`
- `innertube/pages/CommentsParsing.kt`
- `innertube/InnerTube.kt` (`nextWatch`)

Native playback has a Read comments navigation destination. Opening the destination loads a WEB `next` response for the video, selects the exact `comment-item-section` seed, then fetches the first comment page. Sort options and comment totals fall back to the matching comments engagement-panel header when the first page omits them. Requests are read-only; no comment creation, voting, liking or authentication is implemented. Existing ephemeral visitor bootstrap is used.

The parser supports split reload/append endpoint commands, modern comment entities resolved by mutation key, older comment renderers, pinned markers, author/plain text/date/like text, reply buttons and continuation tokens. Replies support modern wrapped/unwrapped view models and legacy renderers. Duplicate IDs are omitted; malformed siblings do not discard valid entries. Missing entities without any usable comment produce an unsupported-response error, even with a header, instead of claiming no comments exist. A genuinely empty recognized command can return an empty page. A missing seed is described as unavailable/disabled/unsupported without claiming to know which.

The UI has sort selection, explicit Load more, nested reply navigation and retry. Generation tokens discard stale results after cancellation/sort/navigation. Repeated pagination tokens stop with a notice. Comments remain plain text: arbitrary server-supplied rich-text commands, HTML and external links are never executed. No avatar-image requests are issued.

Not implemented: posting/reactions, rich text/emoji images/timestamp seeks, author navigation, creator/verified/hearted badges, timed-comments overlays, comments search, full offline caching or moderation. Layout coverage and live API compatibility are incomplete. No live network requests were made for this milestone. SwiftUI compilation/navigation/runtime behavior requires later Apple SDK/device verification.

Eleven portable synthetic-fixture tests cover comment seed scoping, panel fallback, legacy and modern entities, reply tokens/models, split headers/sorts, unavailable/unsupported/empty responses and request fields, blank pinned labels, oversized tokens and partial-result reporting. These tests are not evidence of live compatibility.

Review hardening: parsed seed, pagination, reply and sort tokens are bounded to the request limit (100,000 UTF-8 bytes). Invalid tokens are not exposed as actions. Blank pinned labels do not imply a pin, with property-label fallback preserved. Mixed usable/unsupported comment entries expose an omitted-entry count and the UI retains a partial-results notice across pages. UI lifecycle tests (sort during load, cancelled navigation, returning from replies and stale completions) remain missing and must be performed with Apple tooling; portable parser tests do not substitute for those tests.
