# Portable cipher-envelope and stream URL resolution

Source: `FlowCore/Sources/FlowCore/StreamURLResolver.swift`.

Adapted from Flow Android `player/stream/SignatureCipher.kt` at commit
`3f3e2a6101fe511003f8b694876fe8c6ece89c66`, under GPL-3.0-only.
The signature envelope's form decoding and default signature parameter follow upstream.
The Swift implementation additionally rejects duplicate fields, malformed percent encoding,
unsafe stream destinations, ambiguous target parameters, and unreasonable input lengths.
It replaces existing target parameters instead of appending duplicate signatures.

`StreamURLResolver.resolve` accepts either a direct URL or a signature-cipher envelope,
plus optional throwing signature and n transforms. It preserves unrelated URL query bytes,
form-decodes the envelope exactly once, applies signature then n transformation, and rejects
missing transforms, empty/error results, and an unchanged n result. HTTPS googlevideo URLs
are the only allowed outputs. The module performs no networking or code evaluation.

## What this does not implement

This is the portable URL assembly stage, **not a working YouTube decipher engine**.
There are no built-in signature/n algorithms, player-JS downloads, function discovery,
JavaScript execution, PO-token generation, SABR, or access/login/region restriction handling.
Do not pass identity functions as stand-ins for working transforms. A future engine must
bind transforms to the exact player version, validate results, bound execution, and propagate
failure rather than returning an untransformed URL.

Upstream `utils/cipher/FunctionNameExtractor.kt` has player-specific detection, including
modern dispatcher call sites, string-array obfuscation and known-player fallbacks.
`CipherWebView.kt` supplies Android WebView execution. Those dependencies are not ported.
A generic Swift string reversal is not an adequate replacement for that machinery.

`PlaybackClient` and `PlaybackResponseParser` are intentionally unchanged and continue
rejecting cipher/n streams. This module therefore does not expand working live playback
coverage yet. It is an independently testable building block for subsequent integration,
not a reason to remove the embedded fallback.

## Verification

Eight synthetic XCTest cases are supplied in `StreamURLResolverTests.swift`, covering
form decoding, URL-byte preservation, signature plus n composition, missing transforms,
unsafe URLs, duplicate parameters, invalid transform output, signature replacement, and
error propagation. All eight passed on Linux with Swift 6.0.3 on 2026-11-06.
No live service requests, Apple SDK builds or device tests were performed for this component.
See `PLAYBACK_MANIFEST_EXTRACTION.md` for the separate response-to-source adapter.
