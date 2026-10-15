# Assessment: Exercise 015 — Replicate Elements

## Authoritative scope

The statement was retrieved from `ocaml/ocaml.org`, commit
`7b4c04b90b5433050bcecb25772880bc48bae4d0`, at
`data/exercises/015_replicate_elements.md`. Its one `## Solution` section was
removed before statement inspection. The official example is retained in
[`problem.md`](problem.md).

## Required OCaml boundary

```ocaml
val replicate : 'a list -> int -> 'a list
```

The list precedes the count, as shown by the official call
`replicate ["a"; "b"; "c"] 3`.

## Explicit semantic requirement

For a finite input list `[x1; x2; ...; xm]` and a **positive** count `n`, the
output must be the left-to-right concatenation of `n` consecutive copies of
`x1`, then `n` consecutive copies of `x2`, through `xm`:

```text
[x1; ...; x1; x2; ...; x2; ...; xm; ...; xm]
```

There are exactly `n` occurrences in each displayed group. Thus the operation
preserves source order and positional multiplicity: two equal source values are
still replicated as two separate groups. An empty input produces an empty
output for every tested positive count. Count one is identity.

The authoritative statement supplies a positive example only and says nothing
about counts of zero or less. This item therefore **does not invent** a return
value, exception, or precondition-violation behavior for those integers. No
effect, randomness, mutable state, infinite-stream, float-specific, or
string-specific behavior is stated; the polymorphic interface governs values.

## Synquid contract decision

**Status: requires_features. No `contract.sq` was emitted and no synthesis was
attempted.**

The pinned Synquid runtime's refinement logic has integer, datatype, and set
sorts (`src/Synquid/Logic.hs`), and the local `List-Replicate.sq` example
specifies only output length. A length/set specification cannot establish this
exercise's required ordering or duplicate multiplicity. Invoking such a weak
contract would be unsound: a program that reorders values, deduplicates them,
or repeats the entire list could satisfy it while failing the exercise.

An exact contract needs at least one of:

1. a sequence-valued refinement theory with concatenation and `repeat(n, x)`;
2. a multiplicity-aware, ordered relational measure spanning input list, count,
   and output list; or
3. an inductive relational predicate such as `ReplicatesEach(input, count,
   output)` usable in a synthesis postcondition.

The inspected runtime exposes neither a sequence/bag sort nor a user-declarable
multi-argument inductive relation in its refinement language. Its unary `len`
and set-valued `elems` measures are insufficient. The target algorithm and any
helpers therefore remain absent rather than being replaced with a weaker
contract or a hand-written solution.

## Independent tests

[`test_generated.ml`](test_generated.ml) opens `Generated` and supplies only a
test oracle. It covers the official example, empty input, identity at one,
duplicate preservation, and exhaustive inputs over `[0; 1]` through length
three for counts one through four. It contains a deliberately wrong
whole-list-repetition expectation as a negative control: `[1; 2; 1; 2]` must
not be accepted for `replicate [1; 2] 2`.

A scratch-only deliberately incorrect `Generated.replicate` negative-control
stub that returns `input @ input` when the count is two was compiled with these
independent tests. The executable failed with the expected semantic assertion
`official example: elements, grouping, or order differs` (exit code 2). The
stub is not a deliverable or candidate.

## Claim boundary

There is no synthesized candidate, no generated OCaml implementation, and no
claim that an OCaml backend build or test suite has passed. `elapsed_seconds`
for synthesis is `0`.
