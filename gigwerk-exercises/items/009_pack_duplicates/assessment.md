# Assessment — 009 Pack Consecutive Duplicates

## Status

| Field | Value |
|---|---|
| Contract status | **ready** |
| Specification strength | **full** |
| Synthesis status | **timeout** |
| Actual synthesis elapsed time | **60.050696477 seconds** across two attempts |
| External entry point | `Generated.pack : 'a list -> 'a list list` |

## Source provenance and quarantine

The authoritative source is [`ocaml/ocaml.org`](https://github.com/ocaml/ocaml.org), commit `7b4c04b90b5433050bcecb25772880bc48bae4d0`, path `data/exercises/009_pack_duplicates.md`. It was acquired through the read-only GitHub Contents API.

Exactly one `## Solution` section was found and removed in memory before source inspection. No solution body was retained, used, or reproduced. The SHA-256 of the retained front matter, statement, and official example is:

```text
5ceaafc7c4fe0c919c4fab7a691679e8995087630c02ce680c1bdbb9efa3e56f
```

## Full semantic contract

The required result is the canonical left-to-right partition into **maximal, non-empty contiguous runs of polymorphically equal values**.

- Flattening the output produces exactly the input sequence, preserving both ordering and multiplicity.
- Every group is non-empty and uniform.
- Adjacent groups have distinct representatives. Equal values in non-adjacent runs are intentionally retained as separate groups.
- Empty input produces empty output.
- The operation is pure and deterministic; no randomness, effects, mutable state, failure/option branch, special string or float theory, or infinite stream behavior is present.

`contract.sq` uses `Runs a`, an explicitly documented representation-isomorphic logical carrier for the required OCaml `a list list`. It makes empty groups structurally impossible and states flattening, uniformity, and adjacent-run maximality exactly. The parent backend must mechanically lower `RNil`/`RCons x tail rest` to `[]`/`(x :: tail) :: rest` at its typed OCaml boundary.

## Synthesis record

Only two reasoned attempts were made, each externally bounded as required.

1. **Attempt 1** — exit code **1**, **0.022185825 s**. The first direct `List (List a)` measure encoding was rejected by Synquid's requirement that a measure's final datatype argument retain exactly the measured datatype's declared type parameters. The exact output is retained in `synthesis_attempt_1.out`; stderr was empty.
2. **Attempt 2** — exit code **124**, **60.028510652 s**. After changing to the exact, isomorphic `Runs a` representation, `synquid --resolve` accepted the final contract with exit code **0**. The synthesis run produced no candidate before `timeout 60s` terminated it. `synthesis.out` is empty and `synthesis.err` records `proot` termination by signal 15.

No `--partial`, `Nonterminating`, disabled consistency/termination setting, export-file workaround, manually written candidate, or library delegation was used. Therefore there is **no synthesized candidate** to compile or test.

## Independent OCaml tests

`test_generated.ml` opens `Generated` and calls only `pack`; it contains an isolated test oracle that is not input to Synquid. It covers:

- the official string example;
- empty, singleton, all-equal, all-distinct, and separated-equal edge cases;
- exhaustive inputs over `{0; 1; 2}` of lengths 0 through 5;
- flattening/order/multiplicity, non-empty uniform group, and adjacent-boundary invariants;
- a deliberately named **NEGATIVE CONTROL** expectation asserting `[1; 2; 1]` remains `[[1]; [2]; [1]]`.

The test harness was compiled with OCaml `4.14.1` against an explicitly labelled test-only incorrect stub outside this directory (`pack _ = []`). Its process exited **2** with the expected semantic failure:

```text
FAIL [NEGATIVE CONTROL: separated equal values are not coalesced]: semantic assertion failed
```

This is red-phase evidence that the test detects incorrect semantics, not evidence of an implementation. The stub itself is excluded from the deliverable directory.

## Required capabilities and handoff

The contract relies on algebraic datatypes, recursive user-defined measures over final datatype arguments, refinement equality, structural recursion/termination checking, and the documented mechanical lowering of `Runs a` to nested OCaml lists. The pinned runtime supports resolving the final contract but did not synthesize within the mandated limit.

A later Synquid output would be only a **candidate**. It must be mechanically lowered by the typed OCaml backend and pass `test_generated.ml` before it can be considered semantically validated.
