# Assessment — 008 Remove Duplicates

## Final status

- **Contract status:** requires_features
- **Specification strength:** full
- **Synquid status:** runtime_error — no candidate emitted
- **Total measured synthesis elapsed time:** **0.901 seconds**
- **Allowed external limit:** 60 seconds per attempt; two attempts used

## Exact requirement

`compress : 'a list -> 'a list` returns the first element of every maximal contiguous run under ordinary OCaml polymorphic equality `(=)`. It preserves run order and retains values that recur after a distinct intervening value.

The contract is intentionally stronger than the pinned runtime's nearby `List-Compress.sq` sample, which constrains only element sets and adjacent-distinctness. Sets discard both order and multiplicity; they would admit invalid output such as swapping run representatives or globally deduplicating a later run.

`contract.sq` instead defines a datatype-valued logical measure `runCompress` and requires output equality with that exact sequence. `compress` is a synthesis hole. `eq` is separately declared as a trusted primitive/component intended to lower mechanically to OCaml `(=)`; it is not an implementation of the exercise.

## Synthesis evidence

The prescribed pinned runtime was invoked through `proot`, without `--partial`, `Nonterminating`, disabled checks, or any handwritten candidate.

| Run | Contract form | Exit | Measured seconds | Outcome |
|---|---|---:|---:|---|
| Resolve-only check | Exact `runCompress` relation | 0 | n/a | Contract resolves successfully. |
| Attempt 1 | External declared `eq`, `compress = ??` | 1 | 0.831 | Runtime tried to synthesize `eq` and failed its shape check before a `compress` candidate existed. |
| Attempt 2 | `eq = ??`, `compress = ??` | 1 | 0.070 | Generic equality synthesis failed its own shape check; no target candidate existed. |

The minimal missing feature is **trusted/external generic component injection**: the runtime must be able to make a declared polymorphic equality operation callable by generated code while treating it as an already trusted primitive, rather than turning its declaration into a synthesis goal. The exact logical relation itself is supported, so this is not a weakened-contract issue.

## Required semantics covered by tests

1. Official string example.
2. Empty, singleton, one-run, alternating, and multi-run boundary cases.
3. Exhaustive integer words over `{0,1,2}` of lengths `0..6` (**1,093 inputs**), checked against an independent oracle isolated in `test_generated.ml`.
4. Float equality boundary: two `nan` values do not collapse under OCaml `(=)`, whereas `0.0` and `-0.0` share a run.
5. Function equality boundary: comparison raises `Invalid_argument`, as OCaml `(=)` does.
6. An explicit **NEGATIVE CONTROL** rejects the deliberately incorrect global-dedup expectation `[1;2]` for `[1;1;2;2;1;1]`.

The independent test compiles against the deliberately wrong, explicitly labelled negative-control stub and then fails on the official-example semantic assertion. That only validates harness wiring; it does **not** validate a synthesized or final implementation.

## Candidate policy

No Synquid candidate was produced. If a future backend supports the missing component facility and emits a candidate, it remains only a candidate until mechanical OCaml lowering compiles and `test_generated.ml` passes.
