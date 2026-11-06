# Player JavaScript feasibility review

Reviewed upstream commit `3f3e2a6101fe511003f8b694876fe8c6ece89c66`.

## Completed independent stage

`PlayerScriptMetadata.swift` ports bounded, read-only player version discovery from
`utils/cipher/PlayerJsFetcher.kt`, canonical player URL construction, and the timestamp
recognition stage of `utils/cipher/FunctionNameExtractor.kt`. It handles escaped iframe-API
paths, rejects ambiguous versions/timestamps, and distinguishes a path identifier from a
cryptographic hash. It does not copy the partial-content MD5 or hardcoded-player fallbacks.
Five synthetic XCTest cases accompany it. No JavaScript is downloaded or executed.
The metadata stage is not yet connected to the playback client.

## Why a complete JavaScriptCore engine was not added

The existing upstream engine is not just a few isolated arithmetic/string functions:

- `CipherWebView.kt` injects exports into the complete player at `})(_yt_player);`, then
  loads that script in an Android WebView with a browser global environment. If the export
  insertion fails, it appends code, which cannot reliably reach closure-local functions.
- Signature calls can include multiple dispatcher constants and a preprocessing call.
  n transforms can be array entries, functions or whole-URL wrappers.
- The fallback discovery invokes unrelated global single-argument functions until a return
  value resembles a token. This heuristic does not prove the function is the correct transform.
- `FunctionNameExtractor.kt` explicitly records that newer runtime-computed array indices can
  defeat signature discovery. `CipherDeobfuscator.kt` reports the unparseable player version;
  even the checked Android source does not promise success for every current player.

A bare JavaScriptCore JSContext does not supply a browser DOM or the full browser globals
used by player scripts. Replacing those with empty stubs cannot establish faithful behavior.
Evaluating a whole remote script also needs an enforceable execution budget and resource
isolation: timing out a Swift Task does not stop an already-running synchronous JS evaluation.
At initial review this environment had no Swift compiler, Apple JavaScriptCore SDK/runtime, WebKit runtime,
or captured player-script integration fixtures to validate such an executor. No complete
JavaScriptCore implementation was added, rather than silently accepting guessed transforms.

This is an implementation/verification blocker, not an observed permission denial. No action
was denied and no script execution was attempted. No login, DRM, region or other service
restriction was bypassed. Source review alone does not prove live YouTube compatibility.

## Required next engineering work

1. Obtain authorized representative player fixtures with expected signature/n outputs and
   player-version provenance, including modern dispatcher and URL-wrapper variants.
2. Choose and validate an iOS execution design with browser compatibility where necessary,
   no exposed native/file/network bridge, and genuine cancellation/resource containment.
3. Port version-bound discovery and cache invalidation; reject unsupported player variants.
4. Test initialization failure, exceptions, nontermination, cancellation, stale replies,
   concurrent requests and version rollover before connecting transforms to playback.
5. Add device/live-service integration checks. Keep embedded fallback and explicit failure
   paths until extraction succeeds for the tested player versions.

## Verification status

After installing official Swift 6.0.3, all five metadata tests pass as part of the
69-test Linux package suite (see Verification.md). No Apple SDK build, remote JS execution,
live playback or device verification has passed in this environment.
