# Read-only comparison of the failed player request

Compared the captured single-video request in `LIVE_PLAYBACK_PROBE.md`, current Swift
`PlaybackSource.swift:76–97`, and checked Flow Android upstream commit
`3f3e2a6101fe511003f8b694876fe8c6ece89c66`. No further live request or source modification
was made for this comparison. The observed refusal remains unexplained, not circumvented.

## What already matches

The Swift request and captured request use WEB / client ID 1 / version **2.20260710.06.00**.
These exactly match [YouTubeClient.WEB](https://github.com/Flow-Tube/Flow/blob/3f3e2a6101fe511003f8b694876fe8c6ece89c66/app/src/main/java/io/github/aedev/flow/innertube/models/YouTubeClient.kt#L109-L118).
The main-site player URL, POST method, JSON content type, prettyPrint=false, video ID and
en/US locale also match the equivalent main-site request. Upstream's extraction locale is
explicitly US/en in `YouTubeLocale.EXTRACTION`.

There is **no evidence of a transcription error in the client version**, and this comparison
does not justify inventing a newer one. The fact that both checkouts contain the same static
version does not establish that YouTube still accepts it for this request.

## Concrete differences from ordinary upstream request construction

[InnerTube.ytClient](https://github.com/Flow-Tube/Flow/blob/3f3e2a6101fe511003f8b694876fe8c6ece89c66/app/src/main/java/io/github/aedev/flow/innertube/InnerTube.kt#L242-L273)
adds X-Goog-Api-Format-Version: 1, X-Origin: https://www.youtube.com, Referer:
https://www.youtube.com/, a client-specific User-Agent, and X-Goog-Visitor-Id when available.
The Swift request only sets Origin plus client name/version and content type. Origin and
X-Origin are distinct header names; matching one does not supply the other. Curl used its own
default User-Agent, and the Swift client likewise does not explicitly set upstream's WEB agent.
Upstream's WEB agent is the Firefox/140 Windows string defined at YouTubeClient.kt:91.

The upstream HTTP client's defaultRequest also adds Accept: application/json,
Accept-Language: en-US,en;q=0.9 and Cache-Control: no-cache (InnerTube.kt:211–217).
These are not explicitly set in the Swift client. Transport defaults may differ further;
this review did not capture Apple's actual network request.

[YouTubeClient.toContext](https://github.com/Flow-Tube/Flow/blob/3f3e2a6101fe511003f8b694876fe8c6ece89c66/app/src/main/java/io/github/aedev/flow/innertube/models/YouTubeClient.kt#L62-L87)
adds WEB's originalUrl=https://www.youtube.com, platform=DESKTOP and utcOffsetMinutes=0.
It includes session visitorData when available. None appears in the captured Swift body.
For WEB specifically, upstream does **not** repeat User-Agent inside context.client:
sendUserAgentInContext defaults false (MWEB is the documented exception).

[Context.kt](https://github.com/Flow-Tube/Flow/blob/3f3e2a6101fe511003f8b694876fe8c6ece89c66/app/src/main/java/io/github/aedev/flow/innertube/models/Context.kt)
also defines context.request={internalExperimentFlags:[],useSsl:true} and
context.user={lockedSafetyMode:false}. [PlayerBody.kt](https://github.com/Flow-Tube/Flow/blob/3f3e2a6101fe511003f8b694876fe8c6ece89c66/app/src/main/java/io/github/aedev/flow/innertube/models/body/PlayerBody.kt)
defaults contentCheckOk and racyCheckOk to true. Upstream JSON has encodeDefaults=true,
explicitNulls=false (InnerTube.kt:134–135), so these non-null defaults are serialized. Swift
omits them. These are factual differences, **not a recommendation to assert safety/age consent
or disable safety mode**. Do not copy them as a response to an access/content refusal.

WEB's loginSupported defaults false, so generic player(setLogin=true) still does not attach
account cookies/authorization for this client. The absence of credentials in our anonymous
probe is therefore not, by itself, an upstream WEB header mismatch.

## Most important distinction: upstream does not rely on this minimal WEB POST

The upstream direct fast path leads with VISIONOS. Its web/SABR list is MWEB then WEB
([extractor lines 65–102](https://github.com/Flow-Tube/Flow/blob/3f3e2a6101fe511003f8b694876fe8c6ece89c66/app/src/main/java/io/github/aedev/flow/player/stream/InnerTubeVideoStreamExtractor.kt#L65-L102)).
This is architectural evidence only; no alternate identity was tried or is proposed here.

For the actual WEB/MWEB SABR path, [extractor lines 680–710](https://github.com/Flow-Tube/Flow/blob/3f3e2a6101fe511003f8b694876fe8c6ece89c66/app/src/main/java/io/github/aedev/flow/player/stream/InnerTubeVideoStreamExtractor.kt#L680-L710)
requires WebPoTokenSession visitor data and a successfully minted, session-bound token. It
returns without requesting a player if either is unavailable. It then obtains a signature
timestamp and passes visitorData, the player-request PO token, CPN and optional reload token to
[InnerTube.playerWeb](https://github.com/Flow-Tube/Flow/blob/3f3e2a6101fe511003f8b694876fe8c6ece89c66/app/src/main/java/io/github/aedev/flow/innertube/InnerTube.kt#L542-L600).

That body can include serviceIntegrityDimensions.poToken and playbackContext containing
signatureTimestamp, watch-page referer, vis=0, splay=false, lactMilliseconds=-1 and
html5Preference=HTML5_PREF_WANTS, plus an optional existing reload context. The Swift request
has none of this session or playback state. Subsequent upstream media delivery uses SABR,
which the Swift player does not implement.

A nuance matters: in **generic** `InnerTube.player(client=WEB)` the timestamp is only added if
client.useSignatureTimestamp is true, whereas WEB leaves that flag at its false default. Thus
“our generic WEB request forgot a timestamp that upstream always sends” would be incorrect.
The richer **playerWeb/SABR** path adds it independently when available. Treat the two paths
separately, rather than mixing individual headers/body fields from different client modes.

## What is justified next

1. It is justified to document that the present Swift client is a minimal experimental request,
   not upstream-equivalent WEB playback. A successful HTTP response cannot imply extraction.
2. For future offline development, factor a deterministic request builder and fixture-test the
   intended anonymous WEB header/context shape. Non-consent metadata/header omissions above
   are concrete parity gaps. This does not prove that adding them would fix the refusal.
3. Preserve refusal handling; do not automatically retry this denied video using a different
   client, safety flag, invented token/timestamp, relay or changed identity. No such retry ran.
4. Visitor data, signature timestamps and tokens must retain their actual session/player
   provenance. Do not mix the search visitor cache with an attested playback session by guess.
5. Do not claim the one-word “reload” subreason proves a missing field, stale client version or
   specific enforcement mechanism. The captured response does not identify its cause.

No source correction was applied in this read-only task. No minimal patch is established as a
working playback fix; the supported-source parser and missing SABR/attestation/JS engine remain
separate limitations even if future properly authorized request construction yields status OK.
