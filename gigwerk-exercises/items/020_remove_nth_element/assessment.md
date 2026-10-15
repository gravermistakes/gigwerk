# Assessment — Exercise 020

## Status

| Field | Value |
|---|---|
| Contract status | **requires_features** |
| Specification strength | **full** for the valid-index domain stated by the exercise |
| Synthesis status | **runtime_error** |
| Actual synthesis time | **0.045 seconds** across two attempts |
| Candidate produced | **No** |

## Semantics captured

`remove_at` has OCaml interface:

```ocaml
val remove_at : int -> 'a list -> 'a list
```

For `0 <= n < length xs`, the result removes exactly zero-based position `n`. The abstract-refinement postcondition in `contract.sq` states the positional mapping directly: output position `j` retains input `j` before `n` and input `j + 1` from `n` onward. This is stronger than length or set equality: it preserves order and duplicate multiplicity.

The source statement supplies no behavior for a negative or out-of-range index. Such invocations are therefore excluded by a valid-index precondition; no exception, option, or no-op behavior was invented.

## Synthesis record

The prescribed runtime command was used twice, each externally bounded by `timeout 60s`, with `--output=Plain --print-stats`. Neither attempt reached synthesis:

1. **0.026 s, exit 1** — parser rejected the initial multiline function signature at `contract.sq:29:16`.
2. **0.019 s, exit 1** — after reducing the signature to the one-line shape used by checked local Synquid examples, the runtime rejected the second named dependent argument at `contract.sq:27:52`.

`synthesis.out`, `synthesis.err`, and `synthesis.meta` retain the final actual command result. No `--partial`, nontermination mode, disabled checking, manual implementation, or translated candidate was used.

The contract needs a Synquid frontend/parser setup that accepts its polymorphic index-refined dependent function type and conditional abstract-refinement predicate. The source-level relation is intentionally retained for a later compatible backend; the absence of a candidate is not mislabelled as fulfillment.

## Test evidence

`test_generated.ml` uses only the OCaml standard library and opens `Generated`; it includes the official example, boundary positions, duplicate/order examples, and exhaustive valid lists of lengths 1–4 over `{0,1,2}`. Its local reference oracle is test-only and isolated from the contract/synthesis input.

A test-only deliberately incorrect no-op `Generated.remove_at` stub was compiled with these tests. Running it exited **2** with:

```text
Failure("remove_at: official example: index 1")
```

This shows the independent semantic suite rejects a no-op implementation. The file also contains an explicitly labelled, deliberately wrong negative-control expectation that is intentionally excluded from normal execution: a conforming implementation must not preserve the element at index 1.

## Provenance and quarantine

Authoritative input: `ocaml/ocaml.org`, commit `7b4c04b90b5433050bcecb25772880bc48bae4d0`, `data/exercises/020_remove_nth_element.md`, retrieved read-only through `gh api`. Exactly one `## Solution` section was removed programmatically before inspection; it was not used in any delivered artifact.
