# Reverse a List

## Provenance

- **Authoritative source:** [`ocaml/ocaml.org`, commit `7b4c04b90b5433050bcecb25772880bc48bae4d0`, `data/exercises/005_reverse_list.md`](https://github.com/ocaml/ocaml.org/blob/7b4c04b90b5433050bcecb25772880bc48bae4d0/data/exercises/005_reverse_list.md)
- **Front matter:** title `Reverse a List`; slug `5`; difficulty `beginner`; tags `list`.
- The source was retrieved read-only through `gh api`. Its exact `## Solution` section was removed before inspection. The quarantined section was neither read nor used. Extraction found an exact `## Solution` heading and the following `##` heading, so removal was unambiguous.

## Statement

> Reverse a list.

The OCaml standard library has `List.rev`, but this exercise requires a reimplementation rather than using that library function.

## Required OCaml interface

```ocaml
val rev : 'a list -> 'a list
```

## Full semantic contract

For every finite input list `[x1; x2; ...; xn]`, `rev` returns `[xn; ...; x2; x1]`.

This is **sequence equality**, not merely equality of length, membership, or sets of elements:

- the output has exactly the input occurrences (including duplicates),
- their order is exactly reversed,
- `rev [] = []`, and
- the contract is parametric in the element type; values are rearranged but neither compared nor transformed.

## Official example

```ocaml
# rev ["a"; "b"; "c"];;
- : string list = ["c"; "b"; "a"]
```

## Boundaries

- Inputs and outputs are finite immutable OCaml lists.
- There is no failure/option result, mutation, I/O, randomness, string-specific, float-specific, or infinite/coinductive-stream behavior in this interface.
- `List.rev` is not an admitted target-side primitive. Any synthesis candidate must construct the behavior from the declared datatype constructors and synthesized helpers.
