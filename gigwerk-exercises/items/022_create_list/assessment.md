# Assessment — benchmark 022

## Contract status

**Pending local Synquid validation and one bounded synthesis attempt.** The proposed contract is intended to be **full**: `exactRange` recursively requires the exact inclusive sequence, including direction, every intermediate value, ordering, and multiplicity. It is deliberately stronger than a set- or length-only contract.

## Expressibility rationale

The pinned Synquid source contains non-solution examples of structural list measures, multi-argument measures, Boolean measures, arithmetic refinements, and trusted component declarations. The contract uses those facilities only:

- a structural `List` datatype and terminating `len` measure;
- a Boolean, multi-argument `exactRange` measure whose recursive call consumes the list tail;
- linear integer arithmetic and comparisons;
- hole-only target `range = ??` plus generic arithmetic/comparison components.

No final OCaml implementation is authored here. A Synquid output, if any, remains only a candidate until the parent lowers it and the independent OCaml test suite succeeds.

## Semantic obligations

1. Exact public interface: `range : int -> int -> int list`.
2. Inclusive endpoints and a singleton result at equal endpoints.
3. Ascending unit-step order when `first <= last`.
4. Descending unit-step order when `first > last`.
5. Exact sequence semantics: no omissions, extras, duplicate values, reordering, sorting-only behavior, or set/length weakening.
6. Finite, pure, deterministic result; no mutable state, effects, randomness, strings, floats, options, normal-result exceptions, or infinite streams.
7. Standard OCaml `int` overflow/resource limits are not assigned new behavior by this source exercise.

## Test design

`test_generated.ml` opens only `Generated`; it contains an isolated reference oracle and checks the official example, endpoint equality, ascending/descending adjacency, negative/cross-zero cases, exhaustive pairs in `[-6, 6]`, and an explicit deliberately wrong **NEGATIVE CONTROL** expectation that a conforming implementation must reject.
