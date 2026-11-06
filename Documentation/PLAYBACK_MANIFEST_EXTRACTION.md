# Offline player-response extraction adapter

`PlaybackManifestExtractor` is a separate pure processing stage in FlowCore. It connects the
existing portable `StreamURLResolver` to ordinary player-response format lists and returns a
`PlaybackExtractionReport` containing compatible source candidates and per-format rejection
reasons. It does not replace or modify PlaybackClient or the native controller/UI.

## Scope

- Require playability status `OK`; refuse login/age/unplayable/error responses before invoking
  transforms. No fallback requests, networking, account access, relay, or JS execution.
- Accept direct HTTPS googlevideo HLS URLs, muxed H.264/MP4+AAC candidates in `formats`, and
  MP4 audio candidates in `adaptiveFormats`. Codec declarations are checked conservatively;
  actual decoding remains an AVPlayer/device responsibility. No promise of playback follows
  from an accepted URL or declared codec alone.
- Resolve signatureCipher/cipher and n only when the caller explicitly supplies matching
  transforms. No default identity transform or speculative algorithm is provided. The caller
  must bind transforms to the exact player version that produced the response.
- Reject DRM-marked formats, video-only adaptive streams, unsupported/missing codec declarations,
  unsafe/ambiguous URLs, conflicting cipher envelopes and duplicate successful itags.
- Preserve other valid sources when a format cannot resolve. Diagnostics contain IDs and typed
  reasons, not signed URLs, tokens or raw transform exception text.
- Bound JSON to 10 MB and combined format entries to 512. Existing resolver bounds continue to
  apply to cipher/URL/transform inputs. An empty source list is a diagnostic result, not success
  at playback, and callers must retain an explicit unsupported-extraction fallback.

The upstream reference for per-format cipher assembly is
`player/stream/InnerTubeVideoStreamExtractor.kt:decipherWhilePossible`, commit
`3f3e2a6101fe511003f8b694876fe8c6ece89c66`. Its remote decoder paths were not copied.
Codec selection and structured diagnostics are specific to this iOS port.

## Verification on 2026-11-06

Swift 6.0.3 Linux targeted run passed 22 tests, zero failures:
- 9 PlaybackManifestExtractor tests, including injected synthetic signature/n transforms,
  refusals before transform calls, mixed usable/unsupported formats, DRM/video-only rejection,
  malformed entries, duplicate itags, hostile URLs, bounds and sanitized failures.
- 8 StreamURLResolver tests.
- 5 PlayerScriptMetadata tests.

The separate dormant solver package passed 6 pre-execution gate tests on Linux. These are not
JavaScriptCore tests: that branch is excluded on Linux. No third-party JS was executed.

No iOS SDK build, real player transform, service request, stream playback or device behavior
was tested. Native extraction parity still needs a contained, verified engine, player-version
lifecycle, public ordinary-stream integration testing, and the other documented playback gaps.

A subsequent complete FlowCore Linux suite at 13:29 UTC also passed: 89 tests, zero failures
for the shared source snapshot present at that run. The dormant solver package was rerun and
again passed its 6 gates. Concurrent later edits require their own final aggregate rerun.

Review correction at 13:31 UTC: numeric fields now explicitly reject CFBoolean before integer
conversion. Present-but-invalid height rejects the format; absent height remains zero. Three
new tests cover boolean itags/heights, fractional values and string numerics. The complete
FlowCore Linux suite then passed 92 tests with zero failures (12 manifest-extractor tests).
