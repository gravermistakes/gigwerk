---
title: Palindrome
id: "006_palindrome"
difficulty: beginner
tags: [list]
source:
  repository: ocaml/ocaml.org
  commit: 7b4c04b90b5433050bcecb25772880bc48bae4d0
  path: data/exercises/006_palindrome.md
  solution_handling: "The upstream ## Solution section was removed before this file was inspected or used."
---

# Palindrome

## Statement

Find out whether a list is a palindrome.

> A palindrome is its own reverse.

## Official examples

```ocaml
# is_palindrome ["x"; "a"; "m"; "a"; "x"];;
- : bool = true
# not (is_palindrome ["a"; "b"]);;
- : bool = true
```

## Contract interpretation

The entry point consumes one finite immutable OCaml list and returns `true` exactly when its sequence of elements equals the sequence obtained by reversing that same list. The input is never mutated; no exceptions, options, indices, ordering output, randomness, effects, streams, or mutable state are part of this exercise.

The source statement does not add a custom equality argument. The backend must therefore preserve ordinary OCaml polymorphic structural equality for element comparison. This carries OCaml's usual caveats: functional values cannot be structurally compared, and floating-point `nan` is not equal to itself. The independent tests use ordinary finite integers, strings, and non-NaN floats; they do not turn these language-level caveats into additional source requirements.

## Provenance and quarantine record

Fetched read-only through `gh api` from the pinned commit above. The exact `## Solution` heading was found once; its section (through the next `##` heading or EOF) was discarded before display and before any artifact was authored. No upstream solution body is included or used here.
