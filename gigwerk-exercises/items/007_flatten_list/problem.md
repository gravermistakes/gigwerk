---
id: "007_flatten_list"
title: "Flatten a List"
source:
  repository: "ocaml/ocaml.org"
  commit: "7b4c04b90b5433050bcecb25772880bc48bae4d0"
  path: "data/exercises/007_flatten_list.md"
  blob_sha: "173ddf34fe7465bdbad4991e3a727f0563723cd0"
provenance_note: "Fetched read-only via GitHub API. The upstream ## Solution section was removed before inspection; this document uses only front matter, Statement, and official example."
---

# Flatten a List

## OCaml interface

```ocaml
type 'a node =
  | One of 'a
  | Many of 'a node list

val flatten : 'a node list -> 'a list
```

## Requirement

Flatten a nested list structure represented by `'a node` values.

The output is the **depth-first, left-to-right sequence of leaf values**: visit
input nodes from left to right; a `One x` contributes exactly `x`; a `Many xs`
contributes the flattening of `xs` at that same position. `Many []` contributes
no values. Consequently, both ordering and repeated occurrences are observable
and must be preserved. The operation is pure and total for finite, ordinary
OCaml lists; it has no failure/option case, mutation, effects, randomness,
strings-specific behavior, floats-specific behavior, or infinite/coinductive
stream requirement.

## Official example

```ocaml
flatten
  [ One "a";
    Many [One "b"; Many [One "c"; One "d"]; One "e"] ]
= ["a"; "b"; "c"; "d"; "e"]
```

## Contract boundary

The benchmark accepts all finite values of `'a node list` and returns the leaf
sequence described above. There are no preconditions beyond ordinary finite
input and no exceptional result case. The required output relation is stronger
than set equality or output length: it distinguishes `[One 1; One 2]` from
`[One 2; One 1]` and distinguishes repeated leaves from a deduplicated result.

## Quarantine record

The source extraction found exactly one level-2 `Solution` heading and removed
that section through the next level-2 heading/EOF before this problem statement
was read or authored. No upstream solution body is included here or in any
benchmark input.
