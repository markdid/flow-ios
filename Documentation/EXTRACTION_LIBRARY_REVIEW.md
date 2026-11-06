# Native extraction library review

Read-only source review on 2026-11-06. No dependencies installed, third-party code executed,
player scripts fetched, account used, or live playback tested. No extraction code integrated.
Scope is ordinary, permitted, non-age-restricted streams; no age-gate bypass or remote relay.

## Recommendation

The isolated **alexeichhorn/YouTubeKit SignatureSolver** is a credible next research target.
It already uses JavaScriptCore with AST preprocessing, avoiding the need to port Android's
entire WebView approach. This corrects the earlier feasibility review's incomplete picture:
iOS-compatible solver implementations exist, but their safety and current-player correctness
have not been established for this app. Do not integrate either whole application unchanged.

The solver can conceptually feed the existing StreamURLResolver's signature/n closures.
It must remain independent of account, age-restriction, remote-relay and download logic.
Keep the existing playability refusal and embedded fallback, and do not retry a refused
restricted video through another client identity.

## YouTubeKit: reviewed revision

Repository: https://github.com/alexeichhorn/YouTubeKit
Commit: `7f75a2299dc329c0b7855afb25d47663a02855cb`

- [LICENSE](https://github.com/alexeichhorn/YouTubeKit/blob/7f75a2299dc329c0b7855afb25d47663a02855cb/LICENSE):
  MIT, copyright 2022 Alexander Eichhorn. Preserve its copyright and permission notice if reused.
- [Package.swift](https://github.com/alexeichhorn/YouTubeKit/blob/7f75a2299dc329c0b7855afb25d47663a02855cb/Package.swift):
  Swift tools 5.9, no external Swift package dependencies, processed JS resources.
- [SignatureSolver.swift](https://github.com/alexeichhorn/YouTubeKit/blob/7f75a2299dc329c0b7855afb25d47663a02855cb/Sources/YouTubeKit/SignatureSolver.swift):
  local JSVirtualMachine/JSContext, minimal environment stubs, Meriyah parser, Astring generator,
  generated EJS helper, and batch signature/n challenges encoded as JSON. The class is internal,
  so a normal package dependency cannot expose just the solver without a reviewed fork/adaptation.
- [Extraction.swift](https://github.com/alexeichhorn/YouTubeKit/blob/7f75a2299dc329c0b7855afb25d47663a02855cb/Sources/YouTubeKit/Extraction.swift):
  active `applySignature` uses SignatureSolver, not the older regex `Cipher.swift` implementation.
- [yt_ejs_helper.js](https://github.com/alexeichhorn/YouTubeKit/blob/7f75a2299dc329c0b7855afb25d47663a02855cb/Sources/YouTubeKit/Resources/yt_ejs_helper.js):
  explicitly marked Unlicense and generated from yt-dlp/ejs. It parses/reworks the player AST,
  regenerates code and executes `Function('_result', code)(resultObj)`. It is not just a pure
  static string-operation interpreter. Multiple candidate outputs must agree or it throws.
- The bundled Meriyah identifies itself as 6.1.4. Its current upstream [license is ISC](https://github.com/meriyah/meriyah/blob/main/LICENSE.md).
  Astring's current upstream [license is MIT](https://github.com/davidbonnet/astring/blob/main/LICENSE).
  Exact bundled-artifact provenance and matching notices must be pinned before vendoring;
  the inspected JS bundles do not carry those full notices. MIT/ISC/Unlicense generally permit
  inclusion in a GPL-3.0 project with required notices retained; do not relabel third-party files.

### Security and integration limits

The isolated solver exposes no native file/network bridge in the inspected code, and it has
no need for credentials. JSON input passing is preferable to interpolating challenge strings
into JavaScript source. However:

- Neither script size, AST depth, output size, execution time nor memory is bounded there.
  A Task timeout around synchronous JavaScript evaluation does not terminate that evaluation.
- Setup `evaluateScript` calls do not check their return values. The exception handler logs
  exceptions; robust fail-closed setup must explicitly capture/throw errors after every step.
- Response matching uses `zip`; missing/extra responses and exact input-to-output coverage need
  explicit checks. Validate nonempty, plausible outputs and reject unchanged/error n values.
- Serialize use, avoid main-thread evaluation, and bind caches to exact script content/version.
  The current extraction creates a new solver repeatedly. Performance matters on iOS.
- Minimal browser stubs only cover known script assumptions. They are not a full DOM.
- Fetching must use our strict origin/redirect/size policy; do not inherit arbitrary URL loading.

The full [YouTube.swift](https://github.com/alexeichhorn/YouTubeKit/blob/7f75a2299dc329c0b7855afb25d47663a02855cb/Sources/YouTubeKit/YouTube.swift)
contains a `bypassAgeGate()` fallback and verified-age query parameters. These are outside this
integration scope. The optional remote mode is also excluded: the
[README](https://github.com/alexeichhorn/YouTubeKit/blob/7f75a2299dc329c0b7855afb25d47663a02855cb/README.md)
says its server directs requests through the user's device and receives full responses.
Local iOS mode is the documented default, so the relay is optional, not mandatory.

### Reliability evidence, not proof of current success

- [SignatureTests.swift](https://github.com/alexeichhorn/YouTubeKit/blob/7f75a2299dc329c0b7855afb25d47663a02855cb/Tests/YouTubeKitTests/SignatureTests.swift)
  contains expected-output cases for many player versions, but downloads the scripts at test
  time. None of these tests ran here, and passing historic players would not certify current ones.
- Open [issue #116](https://github.com/alexeichhorn/YouTubeKit/issues/116) reports 20–60 second extraction.
  Open [PR #137](https://github.com/alexeichhorn/YouTubeKit/pull/137) proposes cache/serialization changes.
  These are reporter claims and proposed changes, not measurements of this app.
- Open [PR #151](https://github.com/alexeichhorn/YouTubeKit/pull/151) addresses Unicode metadata parsing.
- Separate video/audio assembly remains another component; open
  [PR #143](https://github.com/alexeichhorn/YouTubeKit/pull/143) proposes automatic combination.
- The README labels the library a work in progress and warns of region variability. It also
  documents a stream availability delay; callers should honor that rather than force early fetches.

## leshkodev/freetube: reviewed revision

Repository: https://github.com/leshkodev/freetube (not the unrelated desktop FreeTube project)
Commit: `8fc6d3b7be9571e3ffcb179de3d1de2dfe7012e7`

- [LICENSE](https://github.com/leshkodev/freetube/blob/8fc6d3b7be9571e3ffcb179de3d1de2dfe7012e7/LICENSE)
  is MIT, copyright 2026 Leshko. Its [README](https://github.com/leshkodev/freetube/blob/8fc6d3b7be9571e3ffcb179de3d1de2dfe7012e7/README.md)
  separately says personal/educational use, sideload/TestFlight, no public App Store submission,
  and no public redistribution intended. Do not treat GitHub's MIT badge as resolving that
  inconsistent presentation. Personal-use scope matches its stated intent, but clarify terms
  before redistributing copied material. No FreeTube implementation was copied in this review.
- Its API package is **b5i/YouTubeKit**, not alexeichhorn/YouTubeKit. The two must not be confused.
- [PythonJSBridge.swift](https://github.com/leshkodev/freetube/blob/8fc6d3b7be9571e3ffcb179de3d1de2dfe7012e7/FreeTube/FreeTube/Core/JavaScript/PythonJSBridge.swift)
  uses PythonKit/PythonSupport, monkey-patches yt-dlp's Deno-runtime discovery and subprocess
  interface, and bridges generated EJS input to JavaScriptCore. This is not a standalone Swift
  extraction library. Its fake-process kill is a no-op; timeout does not contain JS execution.
- [JSEvaluator.swift](https://github.com/leshkodev/freetube/blob/8fc6d3b7be9571e3ffcb179de3d1de2dfe7012e7/FreeTube/FreeTube/Core/JavaScript/JSEvaluator.swift)
  creates a fresh context and captures JS exceptions, but evaluates synchronously without
  resource limits and coerces arbitrary result values to strings.
- [EJSResources.swift](https://github.com/leshkodev/freetube/blob/8fc6d3b7be9571e3ffcb179de3d1de2dfe7012e7/FreeTube/FreeTube/Core/JavaScript/EJSResources.swift)
  pins bundled yt-dlp-ejs 0.8.0 and explicitly requires matching major/minor solver versions when
  yt-dlp changes. A full dependency/license audit would also cover Python, yt-dlp and bundled JS;
  the app's MIT file does not replace those dependency licenses.
- Its code is marked iOS 17+, versus this port's iOS 16 target. Broader integration adds Python,
  ffmpeg, login-cookie handling and downloading. Those are unnecessary to an isolated solver.

### Concrete default-branch defect

The reviewed bridge's typed single-`PythonObject` callback accesses `args[0]`. Open,
unmerged [PR #1](https://github.com/leshkodev/freetube/pull/1) explains that this overload receives
the Python argument itself, so a string is reduced to its first character. It reports solver
JSON errors and downstream 403s, and proposes passing the full argument instead. Open
[PR #9](https://github.com/leshkodev/freetube/pull/9) also addresses this. The default-branch source
still has the implicated indexing. We have verified source and PR state, not independently
reproduced their runtime claims. Do not copy the bridge assuming its README means it works.

## Next decision

Prefer a small, version-pinned adaptation of YouTubeKit's isolated AST solver, with original
licenses/resources preserved, over importing either entire playback pipeline. Before enabling
it: complete bundled-resource provenance, implement and validate genuine execution containment,
strict exception/result handling, bounded input/output and cache isolation, then run Apple-runtime
fixture tests and ordinary permitted-stream integration tests. Neither library establishes PO-token,
SABR or modern-player parity for this port. Existing playback remains unchanged and experimental.
