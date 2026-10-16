# Assessment — Exercise 025

## Status

| Field | Value |
|---|---|
| Contract status | `requires_features` |
| Synthesis status | `not_attempted` |
| Specification strength | `full` (explicit requirements); no executable Synquid contract is emitted |
| Actual Synquid elapsed time | `0` seconds |

## Semantics retained

The benchmark requires `permutation : 'a list -> 'a list` to produce a **random** ordering of its input occurrences. The result must preserve length and the exact occurrence multiset. In particular, duplicates must be retained at their original multiplicity; element-set equality is insufficient. The official six-string invocation is included in the tests, but its displayed random order is not an equality oracle.

The authoritative statement does not impose uniformity or any other probability distribution, a deterministic canonical order, error behavior, mutation, string/float special cases, or infinite-input behavior. None is silently added.

## Why no `contract.sq` was emitted

Inspection of the supplied Synquid source confirmed syntax for pure algebraic data, termination measures, refinements, and synthesis holes, but no supported random/effect construct was found. More importantly, the ordinary list refinements visible in that runtime use length and element-set-style measures. Those are not enough to encode occurrence-sensitive multiset equality: a contract that specifies only equal length and equal element set admits, for example, input `[1; 1; 2]` and output `[1; 2; 2]`.

Calling Synquid on such a weakened contract would therefore be unsound for this exercise and violates the instruction not to call full contracts that omit exact multiplicity or randomized behavior. No attempt was made.

## Minimal required backend features

1. **An occurrence-sensitive list multiset/bag refinement** (or an equivalent recursively defined relation) polymorphic in element type, sufficient to assert `bag result = bag input`.
2. **An effectful probabilistic/random primitive** usable by the synthesizer, with a semantics that chooses an occurrence from a finite nonempty list. A pure fixed-order synthesizer cannot establish the stated random behavior.
3. **A way to track/verify effect semantics separately from extensional output testing.** The current tests verify every individual outcome is a permutation; they cannot prove distributional randomness from a finite run, and the upstream source does not state a distribution to test.

## Test design

`test_generated.ml` opens `Generated` and has no final implementation. It checks exact occurrence preservation by independently removing one matching occurrence at a time; it includes empty, singleton, repeated-value, official-example-input, and exhaustive binary-list inputs through length four. The deliberately incorrect negative control asserts that `[1; 1; 2]` and `[1; 2; 2]` are **not** permutations.

The tests are intentionally semantic rather than order-based because randomness makes a particular output order invalid as an oracle.

## Provenance guard

`problem.md` cites the exact repository, commit, path, and blob SHA. The upstream `## Solution` section was section-delimited and removed before source inspection. No published solution text is reproduced in this item.
