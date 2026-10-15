# Assessment — Exercise 016

## Status

| Field | Value |
|---|---|
| Contract status | **requires_features** |
| Requirement strength | **full** (preserved explicitly; not weakened) |
| Synthesis status | **rejected** |
| Actual synthesis time | **0.047 seconds** across two attempts |
| Candidate | **None** |

## Full obligation

For every positive `n`, the result is the input list after removing exactly the elements at 1-based positions `n`, `2n`, `3n`, and so on. The retained occurrences must appear in the original order and with their original multiplicity. A length-only or set-of-elements refinement is therefore insufficient.

The upstream statement has no stated convention for `n <= 0`. This item treats positive `n` as the input domain and makes no ungrounded claim about invalid-input behavior.

## Why the pinned Synquid runtime cannot carry this full contract

A list-valued logical measure can express exact ordered output values in the pinned runtime; a no-body probe resolved successfully. The periodic deletion relation, however, needs recursive logical state: a countdown `remaining` that decreases for retained elements and resets to `n` after a deletion.

The pinned resolver rejects a recursive measure call when one of its non-structural arguments changes. The corrected full-contract attempt therefore stopped at:

```text
Constant arguments to measure dropNth must not change in recursive call dropNth n n xs
```

A first attempt also established that this runtime does not accept a refinement type alias such as `Pos` in a measure sort. That issue is syntactic, not the core blocker. The core missing feature is **a recursive refinement measure/relation with a varying accumulator**, or an equivalent index-aware sequence relation. Without it, any submitted Synquid contract would have to weaken exact periodic ordered deletion, which this benchmark must not do.

## Bounded attempt record

| Attempt | External limit | Exit | Elapsed | Outcome |
|---|---:|---:|---:|---|
| 1 | 60 s | 1 | 0.024 s | Rejected: `Pos` alias unsupported as measure sort |
| 2 | 60 s | 1 | 0.023 s | Rejected: recursive measure constants cannot vary |

`contract_attempt_2_rejected.sq` preserves the second failed declarative specification for diagnostics only. It is **not** a supportable contract and contains no implementation body other than the required synthesis hole.

## Tests and negative control

`test_generated.ml` opens `Generated` and uses only the OCaml standard library. It covers the official example, empty input, `n = 1`, `n` larger than length, exact and multiple boundaries, duplicates, plus a small exhaustive valid-domain oracle sweep.

`Generated.ml` is explicitly a test-only `failwith "unsynthesized"` negative-control stub, not a solution. Compiling the test against it succeeded; execution exited `1` and reported the expected named semantic failure for the official example.

No final OCaml implementation, manually translated candidate, Android build, or fulfillment claim is present in this item.
