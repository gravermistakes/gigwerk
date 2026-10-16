# Assessment — 003 N'th Element of a List

## Status

| Field | Value |
|---|---|
| Contract status | **ambiguous** |
| Specification strength | **partial** |
| Synthesis status | **rejected** |
| Entrypoint | `at` |
| OCaml interface | `int -> 'a list -> 'a option` |
| Synthesis elapsed time | **1.408959966 seconds** across two attempts |

## Source basis and quarantine

The only exercise source used was `ocaml/ocaml.org` commit `7b4c04b90b5433050bcecb25772880bc48bae4d0`, `data/exercises/003_nth_element.md` (blob `fe19b460d9abaa3b2e27b48444f3d7cf35bcdb9b`). It was obtained through read-only `gh api`.

Before any source content was displayed, the `## Solution` H2 section was excised through the following H2 heading or EOF. No solution body was read, used, or reproduced.

## Required behavior captured

For each **nonnegative** zero-based index `i`:

1. If `i < length xs`, `at i xs` returns `Some` containing exactly the element at positional offset `i`.
2. If `i >= length xs`, it returns `None`, not an exception.
3. The operation is polymorphic; it selects a position, so list order and duplicate occurrences are preserved.

The source supplies no behavior for a negative `int`. The public type accepts `int`, but the examples and statement do not define `at (-1) xs`. Rather than adding a non-authoritative requirement, this item marks that behavior **source-unspecified**. `contract.sq` and `test_generated.ml` intentionally leave it unconstrained/unasserted. This is why the specification is partial and the contract status is ambiguous.

## Contract

`contract.sq` has an unsynthesized `at = ??` hole only. It models positional lookup through:

- an indexed abstract refinement on finite lists;
- a refined option-like `Maybe` datatype;
- `len` and `isJust` measures;
- trusted, generic arithmetic components `zero`, `dec`, and `eq`.

Those primitives are explicitly declared and are **not** the target algorithm. No `List.nth`, `List.length`, list traversal helper, or manual OCaml lookup implementation is present.

## Synthesis evidence

The pinned runtime was invoked as required through `proot`, with `--output=Plain --print-stats`, an external 60-second limit, no `--partial`, and no `Nonterminating` setting.

| Attempt | Time | Exit | Result |
|---|---:|---:|---|
| 1 | 0.020727741 s | 1 | Resolution error: `_v` was used where the abstract-predicate value placeholder is out of scope. See `synthesis_attempt1.out`; stderr is retained in `synthesis_attempt1.err`. |
| 2 | 1.388232225 s | 1 | Rejected: `Cannot find sufficiently strong refinements` on the zero-index branch. The then-current component environment had no integer-equality primitive. See `synthesis.out`; stderr is retained in `synthesis.err`. |

After attempt 2, the generic `eq` declaration was added to the contract. No third attempt was made because this task permits **at most two** reasoned attempts. Consequently there is no synthesized candidate and no claim of backend/OCaml success.

## Tests

`test_generated.ml` is standard-library-only OCaml, opens `Generated`, and keeps a small independent positional oracle outside Synquid inputs. It covers:

- both official examples;
- head, final valid element, empty list, and index just past the end;
- positional behavior with duplicate values;
- a polymorphic tuple payload;
- a small exhaustive matrix of finite integer lists and nonnegative in-/out-of-range positions;
- a deliberately incorrect, labelled **NEGATIVE CONTROL** (`index 2` must not choose the second element) to catch an off-by-one contract.

A deliberately wrong, explicitly labelled test-only stub returning `None` was compiled outside the deliverable directory with this harness. Compilation exited `0`; execution exited `2` with:

```text
Failure("official: index 2: expected Some <value>, got None")
```

That is evidence that the harness detects a semantic defect. It is **not** evidence that an implementation passes.

## Boundary

No final OCaml implementation was authored or copied. A future Synquid output is only a candidate until the parent backend mechanically lowers it and it passes `test_generated.ml` plus any required backend checks.
