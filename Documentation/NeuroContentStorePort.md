# Persistent opened-video topic cache

Adapted from Flow Android Client, https://github.com/Flow-Tube/Flow, commit
`3f3e2a6101fe511003f8b694876fe8c6ece89c66`, Copyright (C) 2025–2026
Flow | A-EDev. GPL-3.0-only; see ../LICENSE.

NeuroContentStore.swift ports the separate opened-video topic cache in
NeuroContentStore.kt. An opened video's richer topics can later be reused when a feed
candidate only supplies a title. It retains the strongest 12 topic weights per video,
up to 1,500 videos, pruning by most recent write time, not read time. It provides per-video
reads, one batch snapshot for ranking, replacements, removal and persistent clear.

The Swift actor serializes access. Writes use atomic JSON replacement and complete before
changing memory. Failed writes therefore leave the last successful snapshot intact.
Existing corrupt, oversized or incompatible files fail to open and are not overwritten.
The file is bounded to 16 MiB and entries/keys/weights are validated on load and write.
Topic weights must be finite, positive and at most one, matching normalized vectors.

## Intentional differences

- Writes are synchronous within the actor and persisted per mutation, not upstream's
  debounced dirty-buffer writes. This favors simple correctness; device performance and
  batching may need later tuning. One actor must own a file, with no cross-process locking.
- Equal weights/timestamps use stable lexical tie-breaking.
- A caller-supplied keySpace separates extractor versions. Incompatible key spaces are
  rejected rather than automatically cleared. Current unstemmed candidate extraction must
  not be labeled as complete Android spec-3 extraction. This storage format is not Android
  JSON import/export compatibility and does not silently migrate Android data.
- Invalid nonempty topic payloads are rejected, rather than persisting NaN or malformed keys.

This is not the distinct-video IDF corpus ledger, the complete user brain, or a sync engine.
There is no UI/watch-event integration, background persistence schedule, encryption or backup
exclusion configured by this component. An eventual app-local destination may be included
in device backups. No source-derived watch data was written during implementation; tests use
synthetic data in temporary directories and remove it afterward.

## Verification

Four XCTest methods cover strongest-topic retention, replacement, reopen, removal, corrupt
and incompatible file preservation, malformed input rejection, failed-write rollback,
1,500-entry pruning by write time and persistent clear.
The then-current full FlowCore suite passed on Swift 6.0.3 Linux on 2026-11-06:
168 tests, zero failures. This is not iOS filesystem/lifecycle validation or full Neuro parity.
