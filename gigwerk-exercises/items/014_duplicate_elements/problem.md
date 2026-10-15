# Duplicate the Elements of a List

**Benchmark ID:** `014_duplicate_elements`  
**Difficulty:** beginner  
**Tags:** list

## Authoritative provenance

- Repository: [`ocaml/ocaml.org`](https://github.com/ocaml/ocaml.org)
- Pinned commit: `7b4c04b90b5433050bcecb25772880bc48bae4d0`
- Source path: `data/exercises/014_duplicate_elements.md`
- Retrieval: GitHub Contents API, read-only
- Quarantine: the source's complete `## Solution` section was mechanically removed before this statement was inspected. No solution body was used.

## Statement

Duplicate the elements of a list.

## Official example

```ocaml
# duplicate ["a"; "b"; "c"; "c"; "d"];;
- : string list = ["a"; "a"; "b"; "b"; "c"; "c"; "c"; "c"; "d"; "d"]
```

## Exact semantic contract

For every finite OCaml list `[x1; x2; ...; xn]`, `duplicate` returns the finite list `[x1; x1; x2; x2; ...; xn; xn]`.

This requires all of the following:

1. **Order preservation:** source elements occur in their original left-to-right order.
2. **Adjacent duplication:** each occurrence is emitted twice, adjacent to itself.
3. **Multiplicity preservation:** separate equal input occurrences remain separate pairs; equality is neither required nor used by the operation.
4. **Polymorphism:** elements are opaque values of any type; no comparison, mutation, effects, randomness, strings, or floats are required.
5. **Empty-list behavior:** `duplicate [] = []`.

The contract concerns ordinary finite OCaml lists. It does not assert behavior for coinductive/infinite streams, mutable structures, effects, or random inputs.
