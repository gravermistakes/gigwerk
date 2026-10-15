# Assessment — `014_duplicate_elements`

## Status

| Field | Value |
|---|---|
| Contract status | **ready** |
| Specification strength | **full** |
| Synthesis status | **rejected** |
| Synthesis attempts | 2 of 2 allowed |
| Aggregate attempted invocation elapsed time | **0.041800 seconds** |
| Entrypoint | `duplicate : 'a list -> 'a list` |

## Exact semantic obligations

For any finite input list `[x1; x2; ...; xn]`, the required result is:

```ocaml
[x1; x1; x2; x2; ...; xn; xn]
```

The contract is intentionally stronger than a set or length condition:

- it preserves **left-to-right occurrence order**;
- it duplicates **each occurrence** as an adjacent pair;
- it preserves pre-existing repeated occurrences as distinct pairs;
- it returns `[]` for `[]`;
- it is polymorphic and does not compare or inspect elements.

## Contract representation

`contract.sq` declares a local parametric `List`, the logical recursive measure
`duplicateSpec`, and `duplicate = ??`. The measure gives the entire output list
shape, so it expresses order and multiplicity exactly. It is logical
specification only; there is no authored target/helper algorithm body and no
trusted algorithmic component.

The final contract was resolve-checked through the pinned runtime:

```text
exit_code=0
elapsed_seconds=0.020532
```

This is a parser/resolver check, **not** synthesis and **not** a claim that an
OCaml implementation has been compiled.

## Synthesis evidence

Each permitted synthesis command was externally limited to 60 seconds. Both
were rejected before search because the initial contract spelling used parser
syntax that the local runtime rejected:

| Attempt | Exit | Elapsed seconds | Result |
|---|---:|---:|---|
| 1 | 1 | 0.020424 | Parse error for named argument syntax. |
| 2 | 1 | 0.021376 | Parse error for `=` in a refinement; local runtime uses `==`. |

The preserved `contract.sq` incorporates both corrections and resolves, but was
not submitted a third time because the task caps synthesis attempts at two.
Direct artifacts for attempt 2 are `synthesis.out`, `synthesis.err`,
`synthesis.status`, and `synthesis.elapsed`; the complete two-attempt log is
`synthesis_attempts.md`.

Therefore there is **no synthesized candidate** and no final implementation in
this deliverable.

## Independent test evidence

`test_generated.ml` is standard-library-only and opens `Generated`. It checks:

1. the official string example;
2. empty and singleton lists;
3. ordering with non-adjacent repeated values;
4. all binary lists through length five against an isolated test-only oracle;
5. a deliberate **NEGATIVE CONTROL** that proves an identity implementation is
   rejected.

The tests were compiled with the explicitly labelled scratch-only negative stub
`let duplicate xs = xs`. Compilation exited `0`; execution exited `1` as
expected, failing at the official example with:

```text
output does not preserve the required ordered sequence
```

This proves the test harness rejects that incorrect behavior; it does not test
or validate a missing synthesized candidate.

## Provenance and exclusions

The source statement came only from `ocaml/ocaml.org` commit
`7b4c04b90b5433050bcecb25772880bc48bae4d0`, path
`data/exercises/014_duplicate_elements.md`, through the read-only GitHub API.
The complete `## Solution` section was mechanically removed before inspection.
No solution body was read, used, or copied.

The benchmark deliberately excludes randomness, effects, mutation, strings or
floats as special theories, and coinductive/infinite streams. It applies to
ordinary finite OCaml lists only.
