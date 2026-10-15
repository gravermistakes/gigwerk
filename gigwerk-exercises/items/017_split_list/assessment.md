# Assessment — Exercise 017

## Verdict

| Field | Status |
|---|---|
| Contract status | **ambiguous** |
| Specification strength | **partial** |
| Synthesis status | **rejected** |
| Actual synthesis time | **5.264 seconds** (the second, syntactically valid attempt) |
| Candidate emitted | **No** |

The authoritative statement fully determines the ordinary **nonnegative length** behavior. It does not say what an OCaml implementation must do when its `int` length is negative. The contract makes `n >= 0` an explicit precondition instead of silently inventing a result or exception. Therefore the source-wide OCaml domain is not fully specified, while the stated domain is specified exactly.

## Exact nonnegative-domain contract

For `split xs n`, with `n >= 0`, the contract requires:

1. `prefix @ suffix = xs` **as a sequence**. This preserves order and duplicate multiplicity, not merely set membership or total length.
2. `List.length prefix = min(n, List.length xs)`.
3. Thus an oversized request saturates to `(xs, [])`.

`contract.sq` encodes reconstruction with a trusted **logical** structural `append` measure. It has no executable helper implementation and the target remains the synthesis hole `split = ??`.

## Synquid evidence

The configured pinned runtime was invoked through the required `proot` command and no shared runtime/source files were changed.

| Attempt | Exit | Elapsed | Outcome |
|---|---:|---:|---|
| 1 | 1 | 0.021 s | Rejected before synthesis by a multiline-signature parse error. `stderr` was empty. |
| 2 | 1 | 5.264 s | The exact corrected contract parsed/resolved, then was rejected: `Cannot find sufficiently strong refinements` while synthesizing. `stderr` was empty. |

The retained `synthesis.out`, `synthesis.err`, and `synthesis.status` are the raw artifacts from attempt 2. This is **not** a candidate result and does not prove an OCaml implementation.

## Independent tests

`test_generated.ml` is standard-library-only, opens `Generated`, and contains no target implementation. It includes the two official examples, five edges, duplicate/order checks, 510 small exhaustive cases, and a deliberately forbidden scrambled-output control.

Before any target implementation, the test compiled against an explicitly labelled scratch `failwith "unsynthesized"` stub and exited nonzero as expected. A separate deliberately incorrect scratch-only stub was then compiled and linked in an isolated scratch directory (`0/0/0`), and its run exited `1` with `FAIL official: first part length 3: semantic assertion failed`. Neither stub is an output artifact or a candidate.

## Required backend capability

A backend needs to lower `List`, `Pair`, nonnegative integer refinements, and the logical append/reconstruction relation, then validate any lowered candidate against the independent OCaml suite. The current Synquid search failure points to insufficient inductive refinement discovery for this exact pair-valued relation, not permission to weaken it to set or length equality.

## Provenance and quarantine

- Source: `ocaml/ocaml.org`, commit `7b4c04b90b5433050bcecb25772880bc48bae4d0`
- Path: `data/exercises/017_split_list.md`
- Retrieval: read-only `gh api`
- The source `## Solution` section was stripped in-memory before inspection and was never read or reproduced.
