# Pending playback intent regression checks

Source change: 2026-11-06. These checks are not executed in the current Linux environment.

The native controller now keeps explicit Play requests made while preparing/seeking separate
from the state it preserves around an ordinary seek. Only the latest matching session, item
and seek completion can consume that request. Pause, stop, a new load and failed restore clear it.

Required device/simulator checks:

1. Pause, start a custom seek, press custom Play before completion. The latest successful seek
   should start playback once, without waiting for another Play press.
2. Pause and seek without pressing Play. Seek completion must leave playback paused.
3. During a seek, press Play then Pause. Completion must leave playback paused.
4. Start two overlapping seeks, press Play during preparation, and let the older completion
   arrive. Only the newer seek may consume the request.
5. Press Play during a seek, then leave the player. A late completion must not resume playback.
6. Pause using AVKit's own controls, change source, and perform a custom seek. Neither action
   should resume unless explicitly requested.
7. Fail a seek after requesting Play. Report the failure and do not start playback at zero or
   overwrite the previously stored resume position.

8. Start native resolution, issue remote Pause before the request completes, then allow source readiness. It must remain paused. Explicit Play during pending resolution should still start when ready.
9. At the last item with repeat off, reach EOF and press Play. The source should seek to zero and start once, not remain at EOF. Repeat with unknown duration/end notification, a failed seek, and navigation away before completion.
10. Open default embedded playback, tap Play, then navigate to native/details/comments and back. Only the visible player may produce audio; stale blank-page/old-player callbacks must not overwrite current diagnostics. Verify request Referer uses the actual configured bundle ID and that page-loaded does not claim media playback.

Current conservative source-restoration policy: after a saved position or source-switch position is restored, the controller pauses and displays “Position restored. Press Play to continue.” It does not automatically consume a Play made during that restoration, because an AVKit pause cannot be distinguished reliably from seek state here. Initial playback with no restore is still intentional, and explicit EOF replay is separate. Portable policy tests cover those decisions; AVKit event ordering still requires Apple runtime checks.

Embedded retry is shown only for transient URL-loading failures (timeout/offline/lost connection/host or DNS lookup/connect failure), never missing identity, security errors or provider restrictions. Verify retry after restoring connectivity, leaving during retry, old navigation callbacks after a new load, and no retry offered for inline provider errors. Main-frame documents are confined to the current official embed; other page requests get an Open on YouTube explanation, while subframes/media remain unrestricted. Verify real consent/player-link behavior before treating the integration as ready.
