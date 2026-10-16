# Assessment — `012_run_length_decoding`

## Status

| Field | Value |
|---|---|
| Contract status | **requires_features** |
| Formal specification strength | **none** — no weak substitute was accepted |
| Synthesis status | **not_attempted** |
| Actual synthesis elapsed time | **0 seconds** |
| Entrypoint | `decode : 'a rle list -> 'a list` |

`contract.sq`, `synthesis.out`, and `synthesis.err` are intentionally absent: the exact count-indexed part of this contract is not expressible with the available pinned Synquid logic, and running a weaker contract would violate the benchmark rules.

## Why the available Synquid vocabulary is insufficient

The pinned source's nearby run-length example declares `len`/`size` as integer measures and `elems`/`cElems` as `Set a` measures. Those alone are inadequate: they erase the exact sequence required by decoding.

Those observations cannot distinguish ordered lists with the same length and element set. For example, these valid-looking inputs have the same total decoded length and the same set of heads but require different outputs:

```ocaml
[Many (2, "a"); Many (2, "b")]  (* ["a"; "a"; "b"; "b"] *)
[Many (2, "b"); Many (2, "a")]  (* ["b"; "b"; "a"; "a"] *)
```

Thus `length + Set` erases both **traversal order** and, in general, **multiplicity**. It cannot encode this exercise's exact semantics.

A bounded pinned-runtime probe also established a narrower, more precise boundary: Synquid **does** accept a List-valued measure with `Nil`/`Cons` equations, equality with that measure in a refinement, and an ordered concatenation measure. Therefore ordered output lists are not themselves the blocker.

### Minimal required feature

A supportable exact contract needs either:

1. a sound, usable logical primitive or definable measure `repeat(n, x)` that returns the ordered List of exactly `n` copies of `x`; or
2. an equivalent sound inductive relation over an `Int` count, an element, and an ordered output List.

The missing primitive must be available *inside* a measure/refinement equation. The parser/resolver constrains a measure's structural input to a declared datatype; it cannot structurally recurse over the `int` carried by `Many`. A separately typed ordinary helper cannot be called in a logical measure body either: the pinned runtime rejects it as an undefined predicate/measure. A cardinality or set-based approximation is not a full contract.

## Explicit requirement retained for later lowering

For every run-length code in the source statement's valid, generated domain:

- `[]` decodes to `[]`.
- `One x` contributes exactly one `x`.
- `Many (n, x)` contributes exactly `n` adjacent `x` values.
- Contributions are concatenated left-to-right, preserving every occurrence.
- No equality, sorting, deduplication, merging of separated runs, effects, mutation, randomness, or element-type special case is permitted.

The supplied file does not state the count invariant from the referenced prior exercise, or output/failure behavior for manually constructed `Many (0, x)` and negative counts. This benchmark does not invent it.

## Test evidence

`test_generated.ml` is independent of any synthesis input and opens `Generated`. It uses only the OCaml standard library and includes:

- the upstream official example;
- empty input and a singleton `One` segment;
- separated equal runs, to reject reordering/merging;
- exhaustive generated code lists of segment length 0–4 using `One`, `Many (2, _)`, and `Many (3, _)` over two atoms — **1,555** cases total;
- an opt-in deliberately false negative-control expectation, activated only with `RUN_NEGATIVE_CONTROL=1`.

A deliberately incorrect, explicitly labelled scratch stub that always returned the empty list was compiled with the independent test file. Running it exited **2** and failed the intended semantic assertion:

```text
Fatal error: exception Failure("decode test failed: One preserves its single element")
```

This proves the harness rejects at least that semantic defect. It is not evidence that any candidate implementation passes.

## Provenance/quarantine

The source was fetched read-only with GitHub API from `ocaml/ocaml.org` commit `7b4c04b90b5433050bcecb25772880bc48bae4d0`, path `data/exercises/012_run_length_decoding.md`, blob `c3c4488deb5b906ff65a91ef5aea09a915d511ed`. The exact `## Solution` section was removed from the fetched copy before inspection; no solution body entered these artifacts.

## No synthesis claim

No Synquid invocation was made, so no candidate, timeout, compiler result, or OCaml fulfillment claim exists. The parent backend may mechanically lower a later, feature-complete contract and must compile it against `test_generated.ml` before claiming fulfillment.
