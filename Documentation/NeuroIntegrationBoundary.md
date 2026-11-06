# FlowNeuro integration boundary

The package includes a Swift translation of Flow Android Client's vector math and a
NeuroBatchScorer that prepares one taste vector and scores explicitly supplied candidates.
Input order and duplicates are preserved. Scores are not relabeled as probabilities or clamped
into a percentage: upstream migration aliases can produce topic-similarity values above one.

This component is deliberately NOT wired into the user feed. The current app has no faithfully
ported tokenizer/topic resources, learned profile persistence, watch-learning policy, candidate
discovery or full upstream scoring/reranking. Inferring topics from words or displaying invented
recommendations would not be FlowNeuro parity. Search and subscription uploads retain their
source order/date order rather than silently applying incomplete recommendation logic.

Next integration: port content-vector production and profile storage, then upstream evidence
learning and complete ranking policy, and run upstream-style regression benchmarks before
using those outputs to order a real feed. Batch/scalar equivalence tests pass in the Linux Swift 6.0.3 package suite
(see Verification.md). No performance claim is made.
