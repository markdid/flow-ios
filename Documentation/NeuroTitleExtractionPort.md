# FlowNeuro title candidate extraction

Adapted from Flow Android Client, https://github.com/Flow-Tube/Flow,
commit `3f3e2a6101fe511003f8b694876fe8c6ece89c66`, Copyright (C) 2025–2026
Flow | A-EDev. Code remains GPL-3.0-only. The copied upstream English Snowball
stop list also retains its BSD-3-Clause notice in NeuroStopWordsLicense.txt.

## Implemented source

NeuroTitleChunks.swift and NeuroChunkLexicon.swift port a bounded subset of
NeuroText, NeuroKeySpec and NeuroChunker:

- Compatibility Unicode normalization, small-cap folding, apostrophe normalization,
  Turkish dotted-I handling, Unicode hyphens and dropped emoji joiners.
- All upstream KEEP_WHOLE names, contractions, elision prefixes and expression variants.
- Expression joining before stop-word filtering, preserving names such as “call of duty”.
- Possessive removal, hyphen shaping, technical-name suffixes and punctuation boundaries.
- English Snowball stop boundaries, caller-provided alternative stop sets, years and numbers.
- Number model pairs, format detection, standalone candidate exclusions and adjacent
  two/three-word candidate runs with the upstream 40 UTF-16-unit limit.

The API returns candidates, not production FlowNeuro topic keys or a content vector.
No UI, persistent watch data, networking or profile learning is added by these files.
Title extraction rejects inputs over 16,384 UTF-16 units to bound allocation/work.
Model pairs also pass the final 40-UTF-16-unit key limit. Upstream's intermediate chunker
may emit oversized model pairs; this API exposes candidates directly, so it filters them
before returning, just as it filters standalone and run candidates. Boundary tests include
supplementary letters and oversized numeric suffixes.

## Important remaining parity gaps

This is not the 3,090-line upstream NeuroTokenizer. No lemma map, Snowball stemming,
language detection/profile-dependent stop selection, title-vs-description/tag weighting,
domain disambiguation, document frequencies, phrase promotion or content-vector feature
inference is implemented here. Candidate words retain their unstemmed forms. Callers
must not store them as spec-3 synced brain keys or equate them to final Android keys.

Chinese/Japanese/Thai/Lao/Khmer/Burmese dictionary segmentation, Hant-to-Hans conversion,
and merged Han candidates require additional implementation. Extraction conservatively
rejects affected Unicode blocks with dictionarySegmentationRequired instead of treating
whole unspaced titles as single topics. The block guard also rejects related punctuation
and compatibility characters in those blocks. Unicode scalar/category details can differ
from Java's UTF-16 character iteration; supplementary-script parity is unverified.

The default stop set is only upstream resources/neuro/stop/en.txt, not all additional
filters in NeuroTokenizer. Spaced-language callers may supply another stop set, but this
is not automatic multilingual language selection or a stemming implementation.

## Verification

Six XCTest methods cover 13 upstream golden cases whose expected keys require no
stemming, plus stop/punctuation boundaries, model pairs, years, NEVER_ALONE behavior,
technical names, unsupported scripts, input limits and candidate-length limits.
They deliberately do not relabel modified unstemmed expectations as upstream goldens.

The complete then-current FlowCore suite compiled and passed on Swift 6.0.3 Linux:
104 tests, zero failures, on 2026-11-06. This is portable core testing, not iOS/device
validation, complete upstream corpus parity, or validation of learned recommendations.

A later model-pair boundary fix passed all seven title-chunker test methods in an isolated
portable package. The concurrent full-suite rerun was blocked by an unrelated compile
error in DownloadStoreTests.swift (missing `try`); the earlier 104-test result predates
this final boundary fix.
