# Assessment — 002_tail_penultimate

## Status

| Field | Value |
|---|---|
| Contract status | **ready** |
| Specification strength | **full** |
| Synthesis status | **rejected** |
| Actual synthesis elapsed time | **0.041 seconds** over two attempts |
| Candidate produced | **No** |
| OCaml backend/lowering validation | **Pending** |

## Exact semantic obligations

1. `last_two` has the exact interface `'a list -> ('a * 'a) option`.
2. A list with length `0` or `1` yields `None`.
3. For a list with length at least `2`, it yields `Some (penultimate, last)`.
4. The ordered pair is **not** interchangeable: penultimate occupies the first component and last the second.
5. Duplicate terminal values remain duplicates; no set conversion or deduplication is allowed.
6. The input prefix does not affect the selected terminal positions.
7. The operation is pure and deterministic. There is no specified exception behavior beyond the `None` result for short lists.

## Contract design

`contract.sq` uses a list refinement parameter `p : Int -> a -> Bool` that records the value at each zero-based position. Its target type requires an optional pair whose components satisfy `p (len xs - 2)` and `p (len xs - 1)`. The `isNothing` measure enforces exactly `None` iff `len xs < 2`. This specifies option behavior, tuple order, and terminal element identities; it is stronger than a set- or length-only contract.

The target declaration remains `last_two = ??`. `len` and `isNothing` are logical requirement measures, not executable helper algorithms. There are no trusted primitives.

## Synthesis record

The runtime was invoked through the prescribed `proot` command with an external 60-second bound on each attempt.

| Attempt | Exit code | Elapsed | Result | Diagnostic |
|---|---:|---:|---|---|
| 1 | 1 | 0.020 s | Rejected | `Unexpected capitalized "Nil"` in a nested measure pattern |
| 2 | 1 | 0.021 s | Rejected | `Unexpected reserved word "match" expecting refinement term` |

Both attempts ended immediately rather than timing out. The outputs in `synthesis.out` and `synthesis.err` are the second attempt; per-attempt details are retained in `synthesis_attempt_1.json` and `synthesis_attempt_2.json`.

After attempt 2, the contract was re-expressed with refinement-indexed data syntax and a shallow structural boolean measure, both checked against pinned **non-solution** Synquid fixtures. It was **not run**: doing so would violate the two-attempt cap. Therefore this contract is available for a subsequent allowed synthesis session, but no parser or synthesis-success claim is made for its final revision.

## Test coverage

`test_generated.ml` opens `Generated` and contains no target implementation. It covers:

- both official examples;
- empty, singleton, two-element, and longer lists;
- tuple direction and terminal ordering;
- repeated terminal values;
- all lists over `{0;1;2}` with lengths `0..6` (1,093 cases);
- an explicit negative-control expectation that a reversed pair must fail a semantic assertion.

`negative_control_stub.ml` is explicitly marked as an intentionally **unsynthesized** `failwith "unsynthesized"` test-only stub. `test_generated.ml` translates that stub signal into a semantic-test failure. It is neither a synthesis result nor a solution.

## Feature assessment

The exact contract needs refinement-indexed lists, user-defined algebraic data, recursive integer measures, arithmetic refinements, and a boolean discriminator measure. These mechanisms are represented in the pinned runtime's non-solution fixtures. No randomness, state, effects, strings, floats, infinite/coinductive stream, or unsupported-element-theory requirement is part of the exercise.
