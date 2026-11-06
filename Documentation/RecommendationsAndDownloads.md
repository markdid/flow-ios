# FlowNeuro and downloads parity

Upstream: Flow Android Client, https://github.com/Flow-Tube/Flow,
commit `3f3e2a6101fe511003f8b694876fe8c6ece89c66`. Copyright (C) 2025–2026
Flow | A-EDev. Adaptations remain GPL-3.0-only; see ../LICENSE.

## Added: pure FlowNeuro math

`FlowCore/NeuroVectorMath.swift` ports selected operations from
`data/recommendation/NeuroVectorMath.kt` and the `ContentVector` model in
`NeuroModels.kt`:

- 70% topic similarity plus duration/pacing/complexity, with 0.3 scalar-only damping.
- Tagged/untagged migration matches at 0.3 weight and topic-only specificity weighting.
- Evidence-based learning for long-term, recent and time-of-day horizons.
- Weak-word absorption into strong phrases, bounded topics and protected-key exceptions.
- Normalized long-term/recent blending, preserving long-term scalar values.
- Jaccard title-token similarity.

Intentional defensive differences: invalid/nonfinite input is discarded or clamped,
zero-strength learning is a no-op, topic ties and ambiguous migration matches use
lexicographic order instead of Kotlin HashMap iteration. This is a math component,
not the full FlowNeuro engine. It is not yet wired to playback or a recommendation UI.
No user watch data is collected or transmitted by this component.

Synthetic XCTest cases cover exact/disjoint topics, migration matching, specificity,
learning horizons, blending, caps/protected keys, phrase absorption and invalid numbers.
They have not run: this Linux environment has no Swift compiler or iOS SDK.

## Still required for FlowNeuro parity

Tokenizer, stemming, phrase discovery, domain tagging, topic catalog, channel memory,
co-watch/affinity graphs, exclusions, impressions, search-learning, negative feedback,
full `NeuroScoring.scoreCandidate` factor pipeline and smart diversity, discovery seed
selection and persisted/versioned brain storage. MusicBrain is a separate recommendation
pipeline. None of these are replaced by the math component.

## Downloads investigation

Upstream `data/video/downloader/resolve/DownloadStreamResolver.kt` resolves fresh
streams through the same extraction ladder as playback, selects compatible video/audio,
handles alternative audio tracks and obtains caption tracks. `transfer/RangeDownloader.kt`
uses parallel range requests, durable block maps, cancellation and stream-denial policy.
The directory also contains collection planning, subtitle conversion, MP4 remuxing and
metadata/tag writing. Android background services, Room persistence and filesystem APIs
need native replacements, not mechanical syntax conversion.

An iOS download implementation still needs:

1. Reliable signed/throttled stream resolution and expiry refresh. Current direct playback
   URLs are not proof that arbitrary videos can be downloaded.
2. A durable queue and URLSession background-session lifecycle with relaunch recovery,
   HTTP status/content-range validation, cancellation and disk-space handling.
3. Separate-track audio/video compatibility selection and verified AVFoundation remuxing
   (or a reviewed portable muxer), with captions and metadata handling.
4. App-local output ownership, offline playback, exports, collection indexing and cleanup.
5. Real-device testing of suspension, interrupted transfers, expired URLs, low disk space,
   deletion during transfer and app termination.

No download manager or offline capability is claimed by these new files. There is no
credible route to full download parity merely by saving an embedded-player web page.

## Prepared ranking lookups

`NeuroVectorMath.PreparedVector` snapshots a sanitized taste vector and builds tagged and
untagged reverse lookups in one pass. Reuse it with the similarity overloads for many
candidates. Fallback matching performs dictionary lookups rather than sorting/scanning
all keys per topic. Ambiguous aliases still choose the lexicographically smallest key.
The full similarity overload preserves upstream's smaller-to-larger matching direction.

Topic similarity is not a probability and is not guaranteed to be at most 1. Upstream's
migration matching can reuse an untagged user weight for several content aliases. For
example, user `guitar: 1` versus content `guitar: 1, guitar:music: 0.3` scores
`sqrt(1.09)`, about 1.044. This inherited behavior is retained, documented on both overloads,
and covered by a synthetic test. Prepared/unprepared equivalence and deterministic alias
selection also have tests. These tests pass in the Linux Swift 6.0.3 package suite (see Verification.md).
