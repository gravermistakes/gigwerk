# Assessment — 007 Flatten a List

## Status

| Field | Value |
|---|---|
| Contract status | **requires_features** |
| Specification strength | **full** (in `problem.md` and independent tests) |
| Synthesis status | **not_attempted** |
| Actual synthesis elapsed time | **0 seconds** |
| Candidate implementation | **None** |

## Exact semantic contract

`flatten : 'a node list -> 'a list` must emit the leaves of the finite nested
node list in **depth-first, left-to-right order**, preserving each occurrence.
`One x` yields exactly `x`; `Many children` contributes the child sequence in
place; `Many []` contributes none. There is no failure result or side effect.

Order and multiplicity are part of the contract, not incidental properties:

- `[One 1; One 2]` must produce `[1; 2]`, not `[2; 1]`.
- Repeated leaves, such as `[One 7; One 7]`, must remain repeated.
- A set-of-elements postcondition would accept a reversed or deduplicated
  result and is therefore unsound for this exercise.

## Synquid expressiveness assessment

The pinned runtime is Synquid **0.4**. Its checked source exposes Boolean,
integer, data/uninterpreted, and extensional `Set` sorts. The local list
examples demonstrate a length-only `concat` specification and a `Set`-based
`append` specification. The source-theory inventory found no ordered-sequence
or multiset/bag sort.

An exact flatten postcondition requires an ordered sequence theory (or an
equivalent inductive relational predicate) that can state recursively:

> leaves(`One x :: rest`) = `[x] ++ leaves(rest)` and
> leaves(`Many children :: rest`) = leaves(children) ++ leaves(rest).

The available `Set` theory loses ordering and duplicate count, and length alone
also loses leaf identities and grouping order. Calling Synquid with either
weaker contract would risk producing a candidate that satisfies the refinement
while violating the benchmark. Per the contract policy, **no `contract.sq` was
emitted and no synthesis was attempted**.

### Minimal required feature

Add either:

1. a polymorphic ordered-sequence refinement sort with concatenation and
   equality, plus a logical `leaves` measure for `node list`; or
2. a solver-supported inductive relational predicate for exact flattening that
   preserves ordered occurrences.

No trusted flatten, concatenation, reverse, or other algorithmic helper should
be used to conceal the target implementation.

## Independent test coverage

`test_generated.ml` opens `Generated` and tests:

1. the upstream official string example;
2. an empty top-level list;
3. nested empty `Many` nodes;
4. nontrivial depth-first, left-to-right order;
5. duplicate preservation;
6. a deliberately explicit **negative-control expectation** showing reversed
   order is semantically distinct; and
7. exhaustive bounded inputs generated to depth 2 and top-level length at most
   2, compared with a test-only reference oracle isolated from synthesis
   inputs.

The test oracle is not an implementation candidate and is not included in any
Synquid input. A deliberately incorrect scratch `Generated` stub is compiled
only to establish that the test suite fails on a semantic assertion; it is not
part of this output directory or a candidate.

**Observed verification:** `ocamlc` compiled the scratch negative-control
module and `test_generated.ml` with exit code 0. Executing the resulting test
binary exited 2 at the official-example semantic assertion, reporting an empty
result instead of the required five-leaf result. This is the expected rejection
of the deliberately incorrect control, not a passing candidate result.

## Provenance and quarantine

Source: `ocaml/ocaml.org`, commit
`7b4c04b90b5433050bcecb25772880bc48bae4d0`,
`data/exercises/007_flatten_list.md`. The file was obtained read-only through
the GitHub API. Exactly one `## Solution` section was removed before inspection.
Only the front matter, statement, and official example informed these artifacts.
