# Watch details and related videos

Implemented 2026-11-06 from upstream commit 3f3e2a6101fe511003f8b694876fe8c6ece89c66:
- `innertube/pages/VideoDescriptionPage.kt`
- `innertube/models/response/WatchMetadataResponse.kt`
- `innertube/InnerTube.kt` (`nextWatch`)

Native playback now links to a separate Video details and related screen. Opening it requests a WEB `next` response through the existing ephemeral visitor/bootstrap and request context. No requests were made during implementation/testing.

The first page displays title, plain-text description, server-formatted views/date and description factoids. It reads the exact primary-info and secondary-info paths; a matching structured-description engagement panel supplies fallback text, factoids and channel details. Channel navigation is enabled only for validated UC IDs; invalid endpoints are displayed as noninteractive channel names. Creator external links, thumbnail/avatar URLs and rich-text commands are neither loaded nor executed. Counts are displayed as supplied, without inventing exact integers from abbreviations.

Related videos come only from `secondaryResults.secondaryResults.results`, including compact video, autoplay, item-section and modern video lockup containers. Unknown/nonvideo/malformed entries are omitted with a partial-results notice. Duplicate videos are collapsed without marking them unsupported. Parsing has 10 MB input, 16-level related-container and 1,000 candidate-video bounds; exceeding related bounds produces a partial notice rather than silently claiming completeness. Explicit empty related lists are distinct from missing/unsupported lists.

This is a first-page YouTube result, not FlowNeuro ranking. Related pagination, API fallback profiles, autoplay queue selection, collaborative creators, rich description links/timestamp actions, live metadata updates and full layout coverage are not implemented. Navigating a related item opens the existing experimental native player and existing local playlist actions are available.

Ten portable synthetic tests cover plain/server-formatted metadata, structured fallback/factoids, channel-ID safety and malformed infocard fallback, panel scoping, wrapped related videos, deduplication, malformed partial results, path isolation, raw video-ID injection rejection and traversal limits. No live API compatibility has been established. The SwiftUI screen is source-only and still needs Apple compilation, accessibility/layout checks and cancellation/navigation lifecycle tests. Stream extraction remains incomplete and unchanged by this milestone.
