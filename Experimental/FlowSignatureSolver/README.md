# Dormant signature solver experiment

**Not enabled, not integrated, and not a working playback claim.**
Linux pre-execution gates compile and pass; the Apple JavaScriptCore branch remains uncompiled
and untested.
This separate Swift package is absent from the application's `project.yml` and FlowCore's
package dependencies. Nothing in the app references it. Do not wire it into production playback.

The source adapts the batch protocol of YouTubeKit's MIT-licensed SignatureSolver, with its
pinned AST helper/parser/generator resources. There is no fetching, relay, login/cookie access,
age-gate bypass, automatic script execution, downloading or stream selection. No FreeTube code
is included. Surrounding port code remains GPL-3.0-only; third-party notices remain intact.

## Gates and constraints

- Initialization defaults to `enabled: false`.
- Explicit enabling is insufficient: a caller must separately supply SHA-256 digests of exact,
  independently reviewed player fixtures. No fixture or approved digest ships with this package.
  Never automatically approve a just-downloaded script by computing and adding its digest.
- Maximum 32 approved digests, 8 MB player input, 64 combined challenges, 16 KiB per challenge.
- Bundled JS resource hashes are verified before evaluation. Each is below 500 KB.
- Fresh JavaScriptCore VM per call; actor-serialized evaluation; no native capabilities exposed.
- Cancellation checks before evaluation stages and after solving. These do not interrupt JS.
- Fail explicitly on resource failures, JavaScript exceptions, malformed response shape,
  missing/extra response entries, unexpected/missing result keys, empty/oversized/control-character
  outputs, unchanged n outputs and known error prefixes. Raw exception/challenge text is not logged.
- Result JSON is checked against a 2 MB bound after evaluation. Outputs are not URLs and need
  separate strict stream-URL validation before any future use.

## Unresolved security and runtime limits

**There is no enforceable JavaScript execution deadline or heap cap in this adapter.**
Input/output checks bound data accepted at the boundary, not work or allocations during execution.
The helper parses and rewrites the player and then uses JavaScript `Function` to execute generated
code. An approved fixture can still contain a bug, infinite loop or excessive allocation. Cancelling
an awaiting Task does not stop synchronous JS and a hung call occupies this actor. A fresh VM
limits state sharing but is not process isolation or a resource sandbox.

Accordingly this is a dormant, allowlisted research fixture adapter, not safe support for arbitrary
remote scripts. No approved fixtures are bundled. Before anyone enables evaluation, independently
review the exact fixture and execution risk. Before live-player use, implement and validate real
execution containment, resource budgets, hostile-fixture handling and Apple-runtime compatibility.
The EJS helper's minimal environment assumptions can fail on future players; there is no fake
success or identity-transform fallback. This package cannot solve PO tokens, SABR, DASH assembly,
DRM, access restrictions or every player version.

## Verification status

Six XCTest cases cover only gates before JS evaluation and do not execute third-party JavaScript.
All six passed on Linux with Swift 6.0.3 on 2026-11-06. The Linux build excludes the
JavaScriptCore/CryptoKit branch. No claim is made about compilation of that Apple branch,
Apple resource loading, EJS correctness, live extraction or device playback.
Resource SHA-256 values were checked locally using Python's standard library without executing JS.
No third-party JavaScript was executed. The separately installed Swift toolchain was used
to compile and run only the Linux gates.
