---
id: "019_rotate_list"
title: "Rotate a List N Places to the Left"
source_repository: "ocaml/ocaml.org"
source_commit: "7b4c04b90b5433050bcecb25772880bc48bae4d0"
source_path: "data/exercises/019_rotate_list.md"
source_retrieval: "GitHub API via gh (read-only)"
solution_handling: "The level-2 `## Solution` section was removed before source inspection; its bytes were not read or used."
---

# Rotate a List N Places to the Left

## Authoritative statement

> Rotate a list N places to the left.

Official OCaml interaction:

```ocaml
# rotate ["a"; "b"; "c"; "d"; "e"; "f"; "g"; "h"] 3;;
- : string list = ["d"; "e"; "f"; "g"; "h"; "a"; "b"; "c"]
```

## Interface evidenced by the source

```ocaml
val rotate : 'a list -> int -> 'a list
```

The source's curried call order is **list first, rotation count second**.

## Semantics that are directly evidenced

For the displayed eight-element input and `n = 3`, preserve every element and
its multiplicity, move the first three elements to the end, and preserve the
order within each portion:

```text
[a; b; c; d; e; f; g; h] -> [d; e; f; g; h; a; b; c]
```

## Ambiguities that block a full benchmark contract

The statement and its single example do **not** specify behavior for:

1. negative `n`;
2. `n > List.length xs`;
3. empty input combined with arbitrary `n`;
4. whether counts normalize modulo the input length or instead have a
   precondition.

Accordingly, this item does not silently adopt a convention for those cases.
The generated tests exercise only the unambiguous finite domain
`0 <= n <= List.length xs`, except that they additionally require an empty
input to return `[]` because no rotation can introduce an element.

## Non-goals and execution constraints

- The operation is pure and deterministic; no randomness, effects, mutable
  state, strings-as-algorithmic-data, floats, coinduction, or infinite streams
  are required by the authoritative source.
- No implementation is present in this deliverable.
- `test_generated.ml` is independent of synthesis input and opens `Generated`.
- A full order- and multiplicity-sensitive contract is not supplied to Synquid:
  the pinned runtime's ordinary list measures exposed here express length and
  element sets, but not the required ordered sequence relation.
