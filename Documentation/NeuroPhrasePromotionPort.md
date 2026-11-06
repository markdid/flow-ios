# FlowNeuro phrase promotion

Source: Flow Android Client, https://github.com/Flow-Tube/Flow, commit
`3f3e2a6101fe511003f8b694876fe8c6ece89c66`, Copyright (C) 2025–2026
Flow | A-EDev. GPL-3.0-only, see ../LICENSE.

NeuroPhrasePromotion.swift ports NeuroPhrases.kt and the title phrase-selection portion
of NeuroTokenizer.kt. It adds normalized pointwise mutual information (NPMI), the
10-document / 3-occurrence / 0.5-NPMI promotion gates, and merged Han run evidence
against the rarest known character (at least half its frequency).

The selection API consumes extracted title chunks and promotes adjacent runs from
statistical evidence, upstream expression keys, or explicitly supplied tag/catalog/compound
sets. Statistical promotion only applies to two-word runs. Promoted phrases claim word
positions, not globally matching strings: an unclaimed occurrence of the same word in
another chunk survives. NEVER_ALONE words are omitted when not claimed in a phrase.
Document-term extraction returns a set, so repeated terms within one video count once.

Defensive deviations: immutable frequency snapshots discard zero/negative counts and
clamp impossible counts to the number of documents. Unknown/zero joint counts return nil
rather than NaN. Selection filters keys longer than 40 UTF-16 units at its public boundary.
No mutable brain state or network activity is introduced.

## Scope limits

These are phrase decisions, not a finished content-vector extractor or feed ranker.
The caller must supply a deduplicated per-video document-frequency snapshot and maintain
its lifecycle. No persistent corpus ledger, IDF weighting, phrase pruning, stemming,
lemmatization, catalog loading or automatic tag ingestion is implemented. Do not treat
un-stemmed chunk output as Android spec-3 keys or sync it as such.

Merged-run evidence can evaluate already extracted BMP Han candidates, but this does
not add Han segmentation/folding to NeuroTitleChunker. Upstream uses UTF-16 Char iteration;
supplementary Han behavior is not claimed. No Android/iOS language-boundary parity is
claimed for a full production corpus.

Seven test methods cover strong/weak associations, warmup, count thresholds, invalid
snapshots, merged-run evidence, positional claiming, tag/catalog overrides, trigram
restrictions and per-document term deduplication.

## Verification

The then-current complete FlowCore suite compiled and passed on Swift 6.0.3 Linux on
2026-11-06: 123 tests, zero failures, including all seven new phrase-promotion tests.
This also reran the seven title-chunker tests after the model-pair length fix. It is not
an iOS/device test or proof of complete FlowNeuro parity.
