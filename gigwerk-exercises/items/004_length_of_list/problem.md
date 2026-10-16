---
id: "004"
title: "Length of a List"
source_repository: "ocaml/ocaml.org"
source_commit: "7b4c04b90b5433050bcecb25772880bc48bae4d0"
source_path: "data/exercises/004_length_of_list.md"
source_content_sha: "70816f08b0b11eb69004dd14688ba8a00c3fdcb8"
solution_handling: "The upstream ## Solution section was quarantined and not read, used, or reproduced."
---

## Statement

Find the number of elements of a list.

OCaml's standard library provides `List.length`, but this exercise requires a reimplementation. A tail-recursive implementation is described upstream as a bonus, rather than as a required semantic condition.

## Required OCaml interface

```ocaml
val length : 'a list -> int
```

For every finite input list, `length xs` returns its structural cardinality: `0` for `[]`, and one more than the cardinality of the tail for every `head :: tail`. Each occurrence counts, so duplicates count separately. The function is polymorphic in the element type and does not inspect element values. No error/option behavior is specified for finite lists.

## Official examples

```ocaml
# length ["a"; "b"; "c"];;
- : int = 3
# length [];;
- : int = 0
```

## Provenance and scope

The sole authoritative source is [`ocaml/ocaml.org` at commit `7b4c04b90b5433050bcecb25772880bc48bae4d0`](https://github.com/ocaml/ocaml.org/blob/7b4c04b90b5433050bcecb25772880bc48bae4d0/data/exercises/004_length_of_list.md). Its front matter identifies the title as **Length of a List**, slug `4`, difficulty `beginner`, and tag `list`.

This benchmark specifies finite, strict OCaml lists only. It has no requirements involving randomness, effects, mutable state, floats, string-specific processing, coinduction, or infinite streams. The output integer alone has no ordering-preservation obligation; multiplicity matters only because every list cell must be counted.
