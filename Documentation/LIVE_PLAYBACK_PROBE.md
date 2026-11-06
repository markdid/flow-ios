# One-video read-only playback probe

Prepared 2026-11-06. This is a failed extraction attempt, not evidence of native playback.

## Request and scope

Selected the widely public, ordinary video **Me at the zoo**, ID `jNQXAC9IVRw`:
https://www.youtube.com/watch?v=jNQXAC9IVRw

Made one anonymous read-only player request over HTTPS using curl, reproducing the explicit
URL, HTTP method, headers and JSON body in the current `PlaybackClient.resolve` source:

- POST `https://www.youtube.com/youtubei/v1/player?prettyPrint=false`
- Content-Type: application/json
- Origin: https://www.youtube.com
- X-YouTube-Client-Name: 1
- X-YouTube-Client-Version: 2.20260710.06.00
- JSON videoId: jNQXAC9IVRw
- JSON context.client: clientName WEB, clientVersion 2.20260710.06.00, hl en, gl US
- 25-second timeout, no cookies, credentials or authorization headers supplied.

This was an HTTP reproduction, not a URLSession end-to-end run: curl's transport/default
headers differ from Apple's URLSession. The actual Swift response parsers were compiled and
run separately against the received response. The environment's configured proxy was used
without changing network configuration or bypassing restrictions.

## Observed response

- HTTP 200, content type application/json; charset=UTF-8; 9,493 response bytes.
- Response Date header: Fri, 06 Nov 2026 19:09:06 GMT.
- videoDetails identifies jNQXAC9IVRw, title “Me at the zoo”.
- playabilityStatus.status: **UNPLAYABLE**.
- playabilityStatus.reason: **Video unavailable**.
- Error-screen subreason: **The page needs to be reloaded.**
- No streamingData, formats or adaptiveFormats were returned.

HTTP success does not mean playback was permitted or that extraction worked. The response
is a service refusal for this request. No second client identity, age-check flow, token machinery,
JavaScript solver, relay or alternate access path was attempted. Network probing stopped here.
The precise cause is unknown; this result alone does not establish whether the static client
version, missing context, request transport, service changes or another factor caused refusal.

## Actual parser verification

Compiled the current `VideoReference.swift`, `PlaybackSource.swift`, `StreamURLResolver.swift`
and `PlaybackManifestExtractor.swift` with Swift 6.0.3 on Linux, then fed the received JSON to:

- `PlaybackResponseParser.parse`: throws `PlaybackError.unavailable("Video unavailable")`.
- `PlaybackManifestExtractor.extract`: throws the same refusal.

No supported source resolved. No stream URL or media bytes were fetched. No JavaScript or
third-party solver was executed, and no AVPlayer, Apple SDK, simulator or device was involved.
This confirms refusal handling for one real response, not successful extraction or playback.
Raw response tracking/visitor fields are not reproduced in this report or stored as fixtures.
