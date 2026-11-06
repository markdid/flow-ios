# FlowNeuro feature weighting and vector assembly

Adapted from Flow Android Client, https://github.com/Flow-Tube/Flow, commit
`3f3e2a6101fe511003f8b694876fe8c6ece89c66`, Copyright (C) 2025–2026
Flow | A-EDev. GPL-3.0-only; see ../LICENSE.

NeuroContentFeatures.swift ports calculateIdfWeight and the final normalization/scalar
feature stage of NeuroTokenizer.extractFeatures:

- Upstream channel/title/phrase/description base weights (0.6/0.5/1.2/0.2).
- 30-document IDF warmup and normalized log-IDF with a 0.15 floor.
- L2 normalization for already extracted and weighted topics.
- Logarithmic duration score with live/unknown defaults and a two-hour ceiling.
- All upstream high/low pacing cues and the Shorts fallback, including substring matching.
- UTF-16 title/word length complexity and the three-timestamp chapter heuristic.
- Assembly into the existing NeuroContentVector, including live and format fields.

Intentional robustness changes: nonfinite/negative topic/base weights are ignored;
oversized topic keys are filtered; L2 normalization scales first to avoid overflow for
very large finite imported weights; invalid duration values use the upstream unknown
or live default. Timestamp matching stops after the third match since only that threshold
matters. These operations do not modify storage or perform network requests.

The input is deliberately named weightedTopics. This is not a full title-to-vector
extractor: callers must still implement stem/lemma keys, channel branding removal,
domain disambiguation, description/tag extraction and weighting, noise removal and
channel topic priors. The source weights are exposed for those implementations, not
silently applied to raw title strings. The pacing heuristics are upstream English
substring rules, not a claim of language-neutral inference. Timestamp matching is a
heuristic, not confirmation that a valid chapter list exists.

Six test methods cover IDF warmup/floors, corrupt inputs, stable normalization, duration,
pacing, complexity/timestamps/UTF-16 lengths and vector field propagation.

Verification: on 2026-11-06 Swift 6.0.3 Linux compiled the complete then-current FlowCore
package and all 137 XCTest cases passed, including six new feature cases. This is not
an iOS build, device validation or full Android behavioral parity result.
