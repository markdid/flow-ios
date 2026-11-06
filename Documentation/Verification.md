# Portable-core verification

Verified 2026-11-06 on Debian 13 x86_64 using the official Swift 6.0.3 Ubuntu 24.04
binary distribution. Package tools version: 5.9; Swift language mode: 5.

- Debug build and XCTest suite: **69 tests passed, zero failures**.
- Release build and XCTest suite: **69 tests passed, zero failures**.
- All 15 FlowCore source files compiled; all 12 test classes ran in each configuration.
- The trailing Swift Testing message reports zero tests because this package uses XCTest;
  it does not replace the XCTest total above.

Logs are preserved in [VerificationLogs/swift-debug.log](VerificationLogs/swift-debug.log)
and [VerificationLogs/swift-release.log](VerificationLogs/swift-release.log).

## Fixes found by execution

1. Two synthetic search fixture dictionaries lacked a closing bracket. Both now compile.
2. The RSS parser accepted a truncated XML document on Linux because FoundationXML can
   return success with `parserError` populated. Parsing now requires no parser error.
   The malformed-feed regression test passes in both configurations and includes its
   input in assertion failures.

## Reproduce

With Swift installed, from the project root:

```sh
swift test --package-path FlowCore
swift test -c release --package-path FlowCore
```

The verified cloud installation was downloaded over HTTPS from:
https://download.swift.org/swift-6.0.3-release/ubuntu2404/swift-6.0.3-RELEASE/swift-6.0.3-RELEASE-ubuntu24.04.tar.gz

In this restricted cloud environment, build and cache files were directed to writable
scratch directories rather than the read-only home directory. From this project root:

```sh
SWIFT=/tmp/flow-swift/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/swift
mkdir -p /tmp/flow-swift-cache/modules /tmp/flow-swift-config /tmp/flow-swift-security
export CLANG_MODULE_CACHE_PATH=/tmp/flow-swift-cache/modules
for configuration in debug release; do
  "$SWIFT" test -c "$configuration" --package-path FlowCore \
    --scratch-path /tmp/flow-core-build \
    --cache-path /tmp/flow-swift-cache \
    --config-path /tmp/flow-swift-config \
    --security-path /tmp/flow-swift-security
done
```

The toolchain and scratch directories are temporary cloud files, not part of this source
bundle. No toolchain was installed on the user's computer.

## Not verified

These are portable, synthetic/local tests. They do not establish service compatibility,
full feature parity or readiness for daily use. No live YouTube request or extraction test
was run. SwiftUI/App code and Experimental/FlowSignatureSolver are outside FlowCore's
package target and were not compiled. XcodeGen project generation, Apple SDK compilation,
simulator/device UI, native/embedded playback, background lifecycle, file import/export UI,
signing, installation and performance remain unverified. No IPA has been produced.

## SponsorBlock integration test pass, 2026-11-06 13:29 UTC

Official Swift 6.0.3 Linux: full FlowCore suite passed 89 tests in debug and release, zero failures. This includes five SponsorBlock fixtures and concurrently added portable components. The first release attempt was interrupted by a source edit; both configurations were rerun successfully after that edit. SwiftUI/AVFoundation and live API behavior remain unverified.

## SponsorBlock duration review, 2026-11-06 13:32 UTC

An isolated snapshot of FlowCore passed 98 tests in both debug and release with official Swift 6.0.3. All current FlowCore source/test hashes matched the snapshot at completion. Eight SponsorBlock tests include duration-aware manual/automatic validation and deferred unknown-duration skipping. SwiftUI/AVPlayer integration remains unverified.

## Download transaction milestone, 2026-11-06 13:46 UTC

Official Swift 6.0.3 Linux passed 116 tests in debug and release on an isolated final snapshot, including 11 download policy/storage/recovery tests. The current FlowCore files matched that snapshot at completion. No live downloads, redirect-delegate runtime tests, AVFoundation media validation, or iOS UI tests were performed.

## Remote playlist milestone, 2026-11-06

An isolated snapshot passed all **131 tests in debug and release** with official Linux Swift 6.0.3, including eight new offline playlist tests. SHA-256 comparison confirmed current FlowCore matched the tested snapshot at completion. Snapshot: /tmp/flow-playlist-reviewed-chtvkpxn/FlowCore (temporary engineering evidence only). Tests cover renderer/request boundaries, malformed/unsupported/empty distinction and primary-vs-secondary container isolation. SwiftUI open/reset/cancellation changes were inspected but cannot be compiled or runtime tested here. No live YouTube requests were made.

## Read-only comments milestone, 2026-11-06

All **148 portable tests pass in debug and release** with official Linux Swift 6.0.3, including eleven new comments tests. Current FlowCore SHA-256 hashes and file names exactly match the isolated tested snapshot `/tmp/flow-comments-_o69446z/FlowCore`. Coverage includes seed scoping, header fallback, modern/legacy/reply shapes, sorts, malformed/empty/unsupported data, request fields, blank pins, parse-time token bounds and partial results. App lifecycle and live API/media tests are still missing; no iOS compile/runtime or live compatibility claim follows from these results.

## Watch details milestone, 2026-11-06

All **164 portable tests pass in debug and release** using official Linux Swift 6.0.3, including ten watch-details tests. Current FlowCore hashes and file names exactly match isolated tested snapshot `/tmp/flow-watch-details-u0sd_lcj/FlowCore`. Review fixes include strict raw video IDs in the shared search parser and skipping malformed leading channel infocards. Tests cover server-formatted/plain metadata, scoped structured panels, related containers and bounded/partial/malformed handling. No live network calls were made. Apple build, UI lifecycle and actual stream extraction remain outstanding.

## Playback-priority source milestone, 2026-11-06

All **188 portable tests pass in debug and release** using official Linux Swift 6.0.3. Current FlowCore hashes and file names exactly match isolated tested snapshot `/tmp/flow-playback-reviewed-bq765lf2/FlowCore`. Included: five official embed request tests, four native intent/replay policy tests, main-document navigation confinement, and preserved prior-feature tests. All App Swift files also passed `swiftc -frontend -parse`; this checks syntax only and does NOT resolve Apple frameworks, typecheck UI bindings or build an iOS app.

Normal video links now point to the official embed in source, with the actual bundle identifier, manual play, visible below-player diagnostics and Open on YouTube fallback. Native is explicit experimental. Same-identity embed retry is limited to explicit transient network failures. Main-frame document changes outside the current embed are blocked and diagnosed separately from existing-player state; subframes/media are untouched. Native source restoration is conservative and requires fresh Play after restoring position.

No new live player, stream or embed request was made. Prior native probe remained UNPLAYABLE; this milestone does not establish working playback. Actual identity propagation, YouTube consent/link behavior, video/audio start, fullscreen and cleanup, retries/cancellations, AVKit seek/pause/replay ordering, Apple compilation/signing and device/simulator verification all remain outstanding. Secondary feature expansion was paused when playback became the priority; earlier local-import edits were preserved and included in the portable regression run.


## First successful Apple build, 2026-11-06

Source commit `8ec150106c0af8bb46a791b49936d28bac87ae62` passed
[GitHub Actions run 42296567191](https://github.com/markdid/flow-ios/actions/runs/42296567191)
on standard `macos-15`, using Xcode 16.4 and iOS Simulator SDK 18.5.

- FlowCore: 188 XCTest tests passed in debug and 188 in release, zero failures.
- Dormant FlowSignatureSolver: Apple branch compiled; six pre-execution gate tests passed.
  These tests do not execute third-party or player JavaScript.
- XcodeGen project generation passed.
- Unsigned Debug iOS Simulator build passed for arm64 and x86_64.

The first run failed because FlowCore omitted a macOS deployment target and SwiftPM
selected an older default incompatible with async APIs. Declaring macOS 12 fixed host
testing without changing the iOS 16 deployment target.

No simulator app launch, UI test, live YouTube playback, real device, signing,
installation, performance or battery check was performed. No IPA or downloadable
app artifact was produced. Earlier notes are historical; this supersedes their
Apple compilation status, not their runtime caveats.
