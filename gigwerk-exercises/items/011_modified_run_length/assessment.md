# Assessment — Exercise 011

## Status

| Field | Value |
|---|---|
| Contract status | **ready** (full semantic contract retained; final revision not re-run because the two-attempt cap was reached) |
| Specification strength | **full** |
| Synthesis status | **runtime_error** — no candidate |
| Total synthesis elapsed time | **0.055 seconds** |
| Final implementation | **None authored or claimed** |

## Exact semantic obligation

`encode` must map an input list to the ordered sequence of its **maximal adjacent-equality runs**.  It must use `One x` exactly for a run of length one and `Many (n, x)` exactly for a run of length `n >= 2`.  This preserves order, run boundaries, and multiplicity; for example, `[1; 1; 2; 1; 1]` requires `[Many (2, 1); One 2; Many (2, 1)]`, not a set-equivalent or globally grouped representation.

`contract.sq` encodes that canonical sequence with the recursive logical measure `encoding`. The `RleList` source datatype is a Synquid-only representation mechanically lowered to OCaml `'a rle list`; it is needed because a Synquid measure's final input must have the same type parameters as the datatype it destructs. The public interface remains exactly:

```ocaml
type 'a rle = One of 'a | Many of int * 'a
val encode : 'a list -> 'a rle list
```

## Independent tests

`test_generated.ml` opens `Generated` and checks:

1. the official string example;
2. empty and singleton inputs;
3. one long homogeneous run;
4. separated equal runs and non-adjacent repeated values;
5. runs of lengths two and three; and
6. all `3^0 + … + 3^6 = 1,093` lists over `[0; 1; 2]`, against an isolated OCaml oracle.

It also contains a deliberately incorrect negative-control expectation (`["q"; "q"]` must **not** encode as `[One "q"]`). An explicitly labelled `failwith "unsynthesized"` test-only stub was compiled with the tests and exited `2` with `Failure("unsynthesized")`, so the suite demonstrably rejects an absent implementation. This stub is outside the deliverable directory and is not a candidate.

## Bounded synthesis evidence

The pinned runtime was run through the required `proot` command twice, each with an external 60-second limit:

| Attempt | Exit | Elapsed | Result |
|---|---:|---:|---|
| 1 | 1 | 0.021 s | Resolver rejected `same_head` because it destructed `List (Rle a)` rather than a datatype carrying its own declared parameter list. |
| 2 | 1 | 0.034 s | Resolver reported `inc` undefined in a logical measure. |

The retained `contract.sq` corrects both issues: it uses `RleList a` for RLE sequence measures and uses logical `n + 1` rather than an undeclared executable `inc` component. A third invocation was intentionally not made because the user limited this item to two reasoned synthesis attempts. Thus **no candidate has been obtained**, and the corrected final contract still requires a later bounded runtime validation before it can be considered synthesis-ready in execution.

## Provenance and exclusions

The statement was obtained from `ocaml/ocaml.org` commit `7b4c04b90b5433050bcecb25772880bc48bae4d0`, path `data/exercises/011_modified_run_length.md`. The single `## Solution` section was removed by heading range before source inspection. No published solution body was read, copied, or used.

The stated interface contains no failure/option behavior, randomness, effects, mutation, stream/coinductive requirement, strings-only behavior, or floats-only behavior. No seed, comparator, or additional public entrypoint was introduced.
