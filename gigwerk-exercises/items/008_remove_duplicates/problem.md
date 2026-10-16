---
id: "008_remove_duplicates"
title: "Eliminate Duplicates"
source:
  repository: "ocaml/ocaml.org"
  commit: "7b4c04b90b5433050bcecb25772880bc48bae4d0"
  path: "data/exercises/008_remove_duplicates.md"
  retrieval: "GitHub API via gh (read-only)"
  solution_quarantine: "The upstream ## Solution section was removed from its heading through the next ## heading/EOF before inspection."
---

## Statement

Eliminate consecutive duplicates of list elements.

## Official example

```ocaml
# compress ["a"; "a"; "a"; "a"; "b"; "c"; "c"; "a"; "a"; "d"; "e"; "e"; "e"; "e"];;
- : string list = ["a"; "b"; "c"; "a"; "d"; "e"]
```

## Benchmark contract clarification

The entry point is `compress : 'a list -> 'a list`. Equality is the ordinary OCaml polymorphic structural equality used to decide whether two **adjacent** elements belong to the same run. The output contains exactly the first element of every maximal non-empty contiguous run of equal input elements, in the original left-to-right order. It does **not** globally deduplicate: equal values separated by a different value remain separated in the output.

This task is pure and deterministic. It has no options or failure-result interface, mutable state, effects, randomness, indexing convention, coinductive/infinite-stream requirement, string-specific behavior, or float-specific arithmetic. For floats, ordinary OCaml `(=)` governs run boundaries (notably, `nan = nan` is false; `0.0 = -0.0` is true). As with OCaml `(=)`, applying the function to values that cannot be structurally compared (for example function values) may raise `Invalid_argument`; this source exercise does not define a separate behavior for that boundary.
