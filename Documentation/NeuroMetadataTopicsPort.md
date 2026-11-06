# FlowNeuro description and tag processing

Adapted from Flow Android Client, https://github.com/Flow-Tube/Flow, commit
`3f3e2a6101fe511003f8b694876fe8c6ece89c66`, Copyright (C) 2025–2026
Flow | A-EDev. GPL-3.0-only; see ../LICENSE.

NeuroMetadataTopics.swift ports the metadata orchestration in NeuroTokenizer:

- Creator tags plus at most five description hashtags, underscore replacement and stable
  deduplication. The upstream no-description behavior retains creator duplicates.
- Description minimum length, minimum surviving line length, sponsor/link/hashtag/shouting
  exclusion, first-five-line and first-15-token limits, repeated-key accumulation and IDF.
- First-15-tag ingestion, length/short-topic exceptions, spam/stop/year filtering.
- Title/description verification, 0.65 versus 0.10 base weights, multiword phrase weights,
  half-weight words when phrases exist, NEVER_ALONE exclusions and IDF weighting.
- Explicit domain resolver invocation with combined tag/title/description context.

NeuroMetadataLexicon.swift retains upstream sponsor patterns, tag spam words and tokenizer
stop-word constants. These are source data, not fetched/user-derived inputs.

## Dependencies and remaining limits

Description processing requires an explicit tokenizer callback. Tag processing requires
explicit chunk and domain resolver callbacks. They are deliberately required, rather than
silently treating identity resolution or unstemmed chunks as complete Android semantics.
Portable tests use the current chunker and an explicit identity resolver where appropriate.
Production still needs upstream-equivalent lemma/stem keys, language-specific tokenization,
Han folding/segmentation and polysemy domain resolution. Thrown segmentation failures
propagate; unsupported text is not silently discarded.

No integrated full-video vector pipeline, corpus persistence or UI hookup is added here.
The description filter preserves upstream heuristic substring checks, which can discard
legitimate prose containing promotional terms. It is not a semantic classifier.
Returned keys are defensively filtered to the 40-UTF-16-unit limit. Unicode-scalar casing
checks improve supplementary-letter handling but are not byte-for-byte JVM Char behavior.

## Verification

Six new XCTest methods cover hashtag limits/order, description exclusions, uncased-script
shouting, token limits/repetition, verified/unverified weights, phrase weights, spam/year
filters, domain context, tag ingestion limits and segmentation error propagation.
The complete then-current FlowCore suite passed on Swift 6.0.3 Linux on 2026-11-06:
154 tests, zero failures. This does not establish iOS/device or full Neuro parity.
