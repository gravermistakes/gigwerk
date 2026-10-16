# Exercise 025 — Generate a Random Permutation of the Elements of a List

## Provenance

- **Authoritative repository:** `ocaml/ocaml.org`
- **Pinned commit:** `7b4c04b90b5433050bcecb25772880bc48bae4d0`
- **Authoritative path:** `data/exercises/025_generate_permutations.md`
- **Blob SHA:** `5103b3d0bce1c43fd5c3e66a0e65c4aedb1c60cf`
- **Source title:** *Generate a Random Permutation of the Elements of a List*
- **Slug / difficulty / tags:** `25` / `beginner` / `list`

The upstream `## Solution` section was mechanically removed before this statement was inspected. No solution body was used.

## Statement (solution-free)

> Generate a random permutation of the elements of a list.

Official interactive example:

```ocaml
# permutation ["a"; "b"; "c"; "d"; "e"; "f"];;
- : string list = ["c"; "d"; "f"; "e"; "b"; "a"]
```

The displayed result is an example random outcome, **not** a required fixed order.

## Benchmark entry point

```ocaml
val permutation : 'a list -> 'a list
```

The source invokes `permutation` at `string list`; it does not print a separate type declaration. This polymorphic signature is the standard generalization of that invocation and is recorded explicitly in `interface.json`.

## Required behavior

For every input list `xs`, `permutation xs` must return a list `ys` such that:

1. `ys` contains every occurrence from `xs` exactly once and contains no other occurrence. This is **multiset** equality, so duplicates are significant.
2. Consequently, `List.length ys = List.length xs`.
3. The selection of an ordering is random, as stated upstream. The entry point remains unary: no seed, RNG state, or replacement deterministic parameter may be added.

No probability distribution (for example, uniformity) is stated by the authoritative non-solution source, so this benchmark does **not** assume one. The source also specifies no exception, option, mutation, string-specific, float-specific, or infinite-stream behavior.

## Contract boundary

The exercise cannot honestly be lowered to the supplied pure Synquid subset: a sound contract needs both occurrence-sensitive multiset preservation for arbitrary element values and a randomized/effectful result. See `assessment.md` for the feature gap. No `contract.sq` is supplied, because a length-and-set-only refinement would accept duplicate-dropping or duplicate-inventing outputs and would not express randomness.
