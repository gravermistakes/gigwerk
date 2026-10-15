---
id: "020"
title: "Remove the K'th Element From a List"
source:
  repository: "ocaml/ocaml.org"
  commit: "7b4c04b90b5433050bcecb25772880bc48bae4d0"
  path: "data/exercises/020_remove_nth_element.md"
  retrieval: "GitHub API (gh), read-only"
  solution_quarantine: "The one `## Solution` section was removed before inspection; it was neither read nor used."
---

# Remove the K'th Element From a List

Create a function that removes the K'th element from a list. The list is **0-based**: the first element is numbered `0`, the second `1`, and so on.

## OCaml interface

```ocaml
val remove_at : int -> 'a list -> 'a list
```

## Authoritative example

```ocaml
# remove_at 1 ["a"; "b"; "c"; "d"];;
- : string list = ["a"; "c"; "d"]
```

## Contract interpretation

For an input list `xs` and an index `n` satisfying `0 <= n < List.length xs`, the result has every input element in its original order except the element at zero-based position `n`. Thus duplicates other than the selected occurrence remain, and multiplicity is reduced by exactly one.

The authoritative statement defines zero-based positions but does **not** prescribe behavior for negative or out-of-range indices. This benchmark therefore makes valid-index use an explicit precondition rather than inventing an exception, option, or no-op behavior.

## Exclusions

The function is pure and finite-list-only. It has no randomness, effects, mutable state, strings/floats-specific rules, or stream/coinductive requirements.
