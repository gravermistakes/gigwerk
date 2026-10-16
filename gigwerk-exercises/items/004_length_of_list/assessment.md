# Assessment — 004 Length of a List

## Contract status

**Ready** for a bounded Synquid synthesis attempt. `contract.sq` defines a finite inductive `List`, a trusted logical size measure `len`, and the exact refinement:

```text
length :: xs: List a -> {Int | result == len xs}
```

This is a **full-strength** semantic contract for the stated finite-list interface: it constrains each individual result to the structural number of list cells, rather than merely bounding, typing, or comparing results. Duplicates necessarily contribute individual cells. The target algorithm is intentionally left as `??`; no helper algorithm or answer body is supplied.

## Acceptance obligations

1. `Generated.length` has exact OCaml signature `'a list -> int`.
2. For every finite input list, its result is its number of cons cells.
3. The empty list maps to `0`.
4. Every element occurrence, including duplicates, contributes exactly one.
5. Results are nonnegative and independent of element values/type.
6. The provided independent OCaml tests must pass after a future mechanical lowering and compilation. A Synquid result alone is only a candidate, never an OCaml acceptance result.

## Deliberate exclusions

Tail recursion is not asserted because the source labels it a bonus. There are no random, effectful, mutable, infinite/coinductive, string-specific, or floating-point semantics. `List.length` must not be used as a delegated implementation.

## Evidence records

- Source retrieval used the GitHub API at the pinned commit. The exact `## Solution` section was removed through the following `##` heading before statement inspection. No solution body appears in this item.
- `test_generated.ml` includes official examples, edge/polymorphism cases, exhaustive binary lists of structural sizes 0–6, and a deliberately wrong constant-zero negative-control expectation.
- The temporary test-only constant-zero module used to prove a red test is not a candidate implementation and is not a deliverable artifact. It compiled against the independent suite and failed at the official nonempty example with `expected 3, got 0` (exit `2`), confirming the test rejects this wrong behavior.
- **Synthesis status: rejected; no candidate.** Two bounded attempts were made, both below the 60-second external cap (combined elapsed time: `0.103` seconds). Attempt 1 exited `1` at `0.024` seconds because the runtime does not accept the `Nat` alias as a measure sort. The contract was corrected to the exact explicit refinement syntax used in the pinned runtime examples. Attempt 2 exited `1` at `0.079` seconds with an ill-shaped polymorphic match attempt: `Cannot match shape 'a' with shape 'List (A2)'`. This is a runtime rejection, not a proof that the contract is unsatisfiable.
- `synthesis.attempt1.out`/`.err` and the final `synthesis.out`/`.err` preserve actual stdout/stderr. Their corresponding `.meta` records preserve exact command, exit code, and elapsed time. No `Generated` implementation was authored, lowered, compiled, or claimed fulfilled.
