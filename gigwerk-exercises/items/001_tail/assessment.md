# Assessment — 001_tail

## Status

| Field | Value |
|---|---|
| Contract status | **ready** |
| Specification strength | **full** |
| Synthesis status | **rejected** |
| Actual synthesis elapsed time | **0.043696105 seconds** across two attempts |
| Candidate / OCaml implementation | **None produced** |

`last` has the exact OCaml interface:

```ocaml
val last : 'a list -> 'a option
```

## Full semantic contract

The input list uses an abstract positional refinement `p i x`: `x` is the value at zero-based index `i`. The contract requires:

- `Nothing` exactly when `len xs = 0`;
- otherwise `Just v` with `p (len xs - 1) v`.

This is an **order- and duplicate-sensitive** contract: it identifies the value at the final list position, not an arbitrary member or a value from an element set. `contract.sq` contains only datatype/measure declarations and the target hole `last = ??`; no algorithm body or library delegation was supplied.

## Trusted support only

The contract relies on finite-list and option-like constructors, Synquid abstract refinements, a terminating `len` measure, an `isNothing` Boolean measure, and integer refinement arithmetic. It does **not** require randomness, effects, mutation, I/O, string or float operations, or infinite/coinductive streams.

## Bounded synthesis record

The pinned runtime was invoked through the required `proot` command with a 60-second external limit; the `--partial`, `Nonterminating`, and check-disabling options were not used.

| Attempt | Exit | Elapsed | Result |
|---|---:|---:|---|
| 1 | 1 | 0.020063692 s | Resolution error: `x` was not in scope in the `Just` refinement. |
| 2 | 1 | 0.023632413 s | Resolution error: `true` was not in scope in `isNothing`. |

Both processes wrote an empty stderr stream. `synthesis.out` and `synthesis.err` retain attempt 2’s actual captured streams. After attempt 2, `true` and `false` were declared with their standard refined Boolean types, matching the runtime’s local `List-Null.sq` convention. The contract was **not run a third time**, because the benchmark permits at most two attempts.

Therefore no synthesis candidate exists and no OCaml semantic-test success is claimed.

## Test evidence

`test_generated.ml` opens `Generated` and contains:

- both official examples;
- empty, singleton, two-element, repeated-value, signed-value, and longer-list cases;
- exhaustive lists through length 5 over `[-1; 0; 1]` against a test-only oracle;
- a negative control that rejects a first-element result for `[10; 20; 30]`.

The independent test compiled against an explicitly labelled `failwith "unsynthesized"` negative-control stub and failed as required. This validates that a missing implementation is rejected; it is not evidence for a candidate.

## Provenance

The source was fetched read-only from `ocaml/ocaml.org` at commit `7b4c04b90b5433050bcecb25772880bc48bae4d0`, path `data/exercises/001_tail.md`, Git blob `108c6ce689ab7df3b71c2f725c3664fb147bfc9a`. Exactly one `## Solution` section was mechanically removed before statement inspection.
