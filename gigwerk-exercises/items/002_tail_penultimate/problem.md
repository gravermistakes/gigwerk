# 002_tail_penultimate — Last Two Elements of a List

## Provenance

- **Authoritative repository:** [`ocaml/ocaml.org`](https://github.com/ocaml/ocaml.org)
- **Pinned commit:** `7b4c04b90b5433050bcecb25772880bc48bae4d0`
- **Authoritative path:** `data/exercises/002_tail_penultimate.md`
- **Retrieval:** GitHub Contents API through preconfigured read-only `gh api`.
- **Solution quarantine:** exactly one `## Solution` heading was detected and its entire section was removed before inspection. This file is derived only from the remaining front matter, statement, and examples.

## Statement

Find the last two (**last and penultimate**) elements of a list.

## OCaml interface

```ocaml
val last_two : 'a list -> ('a * 'a) option
```

## Required semantics

For every finite input list `xs`:

- If `xs` has fewer than two elements, `last_two xs = None`.
- If `xs = prefix @ [penultimate; last]`, `last_two xs = Some (penultimate, last)`.
- The tuple order is **penultimate first, last second**.
- Elements are returned unchanged. Equality, ordering, hashing, mutation, effects, randomness, strings, floats, and any particular element theory are not required by this polymorphic interface.
- The operation is pure and deterministic; it neither raises a specified exercise-level error nor mutates the list.

The list traversal is finite and ordinary; no coinductive or infinite-stream behavior is specified.

## Official examples

```ocaml
# last_two ["a"; "b"; "c"; "d"];;
- : (string * string) option = Some ("c", "d")

# last_two ["a"];;
- : (string * string) option = None
```

## Deliberate exclusions

This benchmark does not permit replacing the specified tuple with an unordered set, reversing the tuple, deduplicating values, or weakening the behavior to a length-only property.
