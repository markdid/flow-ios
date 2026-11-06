# Local library port

Modified Swift adaptation prepared 2026-11-06. Flow Android Client copyright
(C) 2025-2026 A-EDev; GPL-3.0-only, see ../LICENSE and ../ATTRIBUTION.txt.
Reference: https://github.com/Flow-Tube/Flow at
3f3e2a6101fe511003f8b694876fe8c6ece89c66.

## Source and scope

The domain is adapted from upstream `data/local/entity/PlaylistEntity.kt`,
`PlaylistVideoCrossRef.kt`, `WatchHistoryEntity.kt`,
`data/local/SubscriptionRepository.kt` (`ChannelSubscription`) and
`data/local/PlaylistRepository.kt` (built-in playlist identifiers).
Paths are relative to `app/src/main/java/io/github/aedev/flow/`.
This is a Swift redesign of that local subset, not an Android database/backup codec.

Implemented: ordered unique playlist membership, built-in Watch Later/Saved Shorts,
playlist rename/delete protections, local subscribe/unsubscribe/preferences, unique
watch entries, resume position, history pause/delete/clear, stale-callback protection,
atomic versioned persistence, non-destructive failure and one-time bookmark migration.
Deleting a saved video cascades through local playlist membership and watch history.
Removing playlist membership does not delete the saved video. Removing history leaves
saved video metadata intact. All subscriptions are local and never change a Google account.

## Integration contract

Create exactly one `LibraryRepository` actor for a new application-support filename
such as `FlowPrototype/collection-v1.json`. Supply the existing `library.json` as
`legacyBookmarksURL`. Initialization is throwing: show the error and keep editing
unavailable if it fails, rather than silently opening an empty replacement store.
Perform initialization off the main thread. Call `await repository.snapshot()` for
initial state and `try await repository.apply(command)` for mutations. Publish the
returned snapshot to UI only after success. Do not keep writing through the old
LibraryStore simultaneously after switching; its bookmark file becomes migration-only.
No existing API or UI was replaced by this component.

For playback, obtain `await repository.beginWatch(videoID:)` once at an explicit
playback start and retain its `WatchSession`. Pass it as `session:` in `recordWatch`.
Do not mint sessions from progress callbacks. Beginning returns nil while history is
paused. Clear history invalidates every session; remove history/delete video invalidate
that video’s session; pausing invalidates all sessions. Unpausing does not restore them.
A newly opened repository rejects all sessions from previous instances. Invalidated
callbacks are no-ops, even if they carry new timestamps. Token invalidation commits
only when the associated disk write succeeds. Start a new explicit playback session
to record again after deletion or pause.

Emit `recordWatch` on pause/end/background and at a coarse interval,
not every frame. `position` and `duration` are **seconds**, not Android milliseconds.
Pass video metadata alongside each entry. History pause does not erase old entries.
The actor exposes snapshots, not an observation stream; a shared UI view model owns
observable state and forwards commands. Built-ins are created on first add.

## Limits and verification

JSON is suitable for a small personal collection, not upstream's indexed SQLite
history at tens of thousands of entries. Writes serialize the complete state. No
cross-process coordination, subscription feed refresh, notification scheduling,
Android import, sync, likes, music/local-file metadata, encryption, or download
management is provided. Notification preference is data only.

Eight XCTest cases cover ordering, cascade, failed mutation rollback, reload, history,
built-ins, subscriptions, one-time migration, bad/future files, failed disk writes, invalidated playback callbacks and safe lookup
of directly decoded malformed snapshots.
Run `cd FlowCore && swift test` on a Swift-enabled host. At authoring, this Linux
workspace had no Swift executable; neither these tests nor iOS integration had run.
