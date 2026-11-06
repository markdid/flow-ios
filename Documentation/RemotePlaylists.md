# Public remote playlists

Implemented 2026-11-06 from upstream commit 3f3e2a6101fe511003f8b694876fe8c6ece89c66:
- `innertube/pages/VideoPlaylistPage.kt`
- `innertube/YouTube.kt` (`videoPlaylistPage`)
- `data/repository/YouTubePlaylistRepository.kt`

The library’s Open YouTube playlist screen accepts public PL, UU and OLAK5uy_ IDs or HTTPS YouTube playlist/watch links. An explicit Open sends the request. WEB `browse` requests use `VL<id>` initially and continuation alone on later pages. Visitor bootstrap is shared with existing browse clients. No request has been made during implementation/testing.

Parser supports modern item-section video lockups, rich Shorts grids, legacy playlist video lists, append actions, and old/new continuation item forms. Explicit empty lists are distinct from unsupported containers. Non-object siblings do not discard valid videos. Duplicate videos are collapsed, matching upstream. Parsing is bounded and rejects budget overflow. Like upstream, a Shorts grid triggers one attempt at the `wgYCCAA=` pageable view; failure preserves the grid with an incompleteness notice.

Users can open individual videos or use existing local playlist actions. Load more is explicit; repeated continuation tokens stop pagination. Stale/cancelled UI results are discarded. Only loaded entries are represented, never advertised as a complete saved copy.

Not implemented: mix queues (`RD`), authenticated/private playlists, course metadata, owner links/header counts, full-playlist import/sync/cache, linked deep-video queue walking, queue-wide playback, full renderer coverage. Unsupported responses produce errors instead of being represented as successful empty playlists. Live compatibility, iOS screen compilation and runtime behavior remain unverified.

Tests use constructed offline fixtures for modern/legacy/grid shapes, continuation forms, malformed siblings, unavailable entries, public-ID validation and request body semantics. These fixtures validate contract handling, not live YouTube compatibility.
