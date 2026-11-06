# FlowNeuro format and category preferences

Source: Flow Android Client, https://github.com/Flow-Tube/Flow, commit
`3f3e2a6101fe511003f8b694876fe8c6ece89c66`. Copyright (C) 2025–2026
Flow | A-EDev. GPL-3.0-only; see ../LICENSE.

`NeuroPreferences.swift` ports the complete pure `NeuroFormats.kt` and
`NeuroCategories.kt` preference operations, without Android storage dependencies:

- All 21 format IDs and their upstream multilingual surfaces.
- Exact folded-word format lookup and canonical search terms.
- Positive format learning, unrelated-format fade and low-weight pruning.
- Maximum format affinity score contribution (0.04).
- YouTube category name normalization, stable IDs and theme classification.
- Category signal counting and aging after 400 signals.
- Category mismatch factors, 20-signal warmup, familiarity threshold and specificity.
- Topic-cluster category voting weighted by overlap and confidence, requiring 60% majority.

Format affinity and category counts use different scales. All public numeric operations
sanitize imported dictionaries: nonfinite or negative affinities/counts are discarded,
format affinity is capped at 1 and category counts at 400 (the per-category maximum
reachable through the learner). Even empty-format learning sanitizes input. Category
counts are not normalized to 0...1. Cluster topic weights ignore nonfinite values and
clamp finite values to 0...1. These defensive changes preserve valid learner behavior
and prevent corrupt imported data from producing nonfinite or unbounded scores.
Channel confidence is clamped to 0...1, and nonfinite confidence becomes zero, a defensive
difference from upstream. Tied category votes use deterministic lexicographic ordering;
a tie between leaders cannot pass the 60% threshold.

This does not implement a tokenizer: input surfaces must already be folded and segmented.
It does not infer a category from a video title. The caller must obtain microformat
category metadata or a separately learned channel category. It does not persist preferences,
record playback events, or modify any UI. Full recommendation ranking, acquisition,
negative feedback, discovery, MusicBrain and brain persistence remain separate work.

Synthetic tests cover every format surface, repeated/empty learning, fade/pruning, maximum
rather than summed format scores, category normalization, aging thresholds, warmup,
familiarity, confidence, default-category specificity and weighted-majority voting.

## Verification

On 2026-11-06, Swift 6.0.3 for Linux compiled FlowCore and passed the complete then-current
XCTest suite: 79 tests, zero failures, including six new preference tests and nine vector
math tests. All compiler/module/SwiftPM caches were placed under /tmp. This supersedes
older notes saying vector tests were unexecuted. It is not an iOS build, device test,
live YouTube extraction test or full FlowNeuro behavioral parity test.

After numeric-boundary hardening, the then-current complete FlowCore suite passed again:
98 tests, zero failures on Swift 6.0.3 Linux. Nine preference tests now include corrupt
format affinity, oversized/nonfinite category counts and invalid cluster profile weights.
