# Assessment — Exercise 010: Run-Length Encoding

## Status

| Field | Value |
|---|---|
| Contract status | **requires_features** |
| Specification strength | **full** |
| Synthesis status | **rejected** — no candidate emitted |
| Attempts | 2 (the allowed maximum) |
| Total synthesis wall time | **4.396 seconds** |

## Source discipline

The authoritative file was retrieved read-only from
[`ocaml/ocaml.org` commit `7b4c04b90b5433050bcecb25772880bc48bae4d0`](https://github.com/ocaml/ocaml.org/blob/7b4c04b90b5433050bcecb25772880bc48bae4d0/data/exercises/010_run_length_encoding.md), path `data/exercises/010_run_length_encoding.md`.

Exactly one `## Solution` section was mechanically removed before inspection. `problem.md` derives only from the retained front matter, statement, and official example. No published solution body is present in deliverables.

## Exact semantic contract

`Generated.encode` must have this exact OCaml interface:

```ocaml
'a list -> (int * 'a) list
```

For a finite input list, output is the left-to-right sequence of **maximal, non-empty contiguous equality runs**. Every count is positive. Expanding the pairs reconstructs the input exactly, including **order and multiplicity**. Adjacent output representatives differ, while a value that reoccurs after a distinct run remains a separate output pair.

The Synquid contract is full-strength rather than set/length-only:

- A `Run` structurally represents a positive count as a leader plus zero or more equal tail values.
- `Runs` is refined so neighbouring representatives differ.
- `flat` is an ordered structural expansion measure, not an element set.
- The target refinement requires `flat output == input`.

A typed backend must mechanically lower `Run`/`Runs` to `(int * 'a) list`; that lowering is not implemented in this item.

## Synthesis evidence

The prescribed runtime command was used via `proot`, with an external 60-second limit on each attempt. The runtime and shared source were not modified.

1. **Attempt 1** — exit `1`, `0.026 s`. Resolution rejected the first formulation because canonicality quantified over `Run a`, which this runtime parsed as a predicate-argument application: `Datatype Run expected 0 predicate arguments and got 1`. The contract was repaired narrowly to quantify canonicality over the representative `a`; semantics did not weaken.
2. **Attempt 2** — exit `1`, `4.370 s`. The runtime reached `encode` but tried to synthesize the declared polymorphic equality component and failed:

   ```text
   Cannot match shape 'Bool'
   with shape '_'
   when checking eq
   ```

No candidate was emitted. The pinned runtime needs a **trusted polymorphic decidable-equality primitive** (or a backend-installed equivalent) to synthesize the exact polymorphic exercise. The intended generic declaration is:

```text
eq :: x:a -> y:a -> {Bool | _v == (x == y)}
```

This is a supporting primitive, not the final algorithm. No further attempt was made because the item is limited to two reasoned runs.

## Independent test evidence

`test_generated.ml` is standard-library-only OCaml, opens `Generated`, and contains no target implementation. It checks the official example; empty, singleton, long-run, alternating, non-adjacent-repeat, and signed/zero boundary cases; and all lists over `[-1; 0; 1]` through length 5 against a test-only oracle. It also includes a deliberately incorrect negative-control expectation.

The test harness was compiled against an explicitly labelled `failwith "unsynthesized"` negative-control stub. It exited `1` at the official-example assertion with `Failure("unsynthesized")`, as expected. This confirms the harness is red against a missing implementation; it does **not** certify a candidate or an OCaml implementation.

## Retained artifacts

| Artifact | Purpose |
|---|---|
| `problem.md` | Solution-free statement and provenance |
| `interface.json` | Exact entrypoint/type declarations and trusted-boundary metadata |
| `contract.sq` | Full ordered/multiplicity-preserving Synquid candidate contract; target is a hole |
| `test_generated.ml` | Independent OCaml semantic suite |
| `synthesis.out`, `synthesis.err` | Final attempt stdout/stderr |
| `synthesis.attempt1.out`, `synthesis.attempt1.err` | First attempt stdout/stderr |
| `assessment.json` | Machine-readable result and evidence |

No final OCaml implementation was authored, translated, compiled, or claimed fulfilled.
