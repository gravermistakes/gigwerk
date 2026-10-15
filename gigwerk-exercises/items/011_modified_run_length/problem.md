# Exercise 011 — Modified Run-Length Encoding

## Provenance and quarantine

- **Authoritative source:** [`ocaml/ocaml.org`](https://github.com/ocaml/ocaml.org), commit [`7b4c04b90b5433050bcecb25772880bc48bae4d0`](https://github.com/ocaml/ocaml.org/commit/7b4c04b90b5433050bcecb25772880bc48bae4d0)
- **Path:** `data/exercises/011_modified_run_length.md`
- **GitHub blob:** `9091f9b111afc81a8968b4a5e54470b047efa9eb`
- **Retrieval:** read-only `gh api` GitHub Contents request.
- **Solution quarantine:** the sole `## Solution` range was removed from its heading through the next level-two heading or EOF *before* the source was inspected. No solution body was read or used.

## Required OCaml interface

```ocaml
type 'a rle =
  | One of 'a
  | Many of int * 'a

val encode : 'a list -> 'a rle list
```

## Semantics

Transform the input into its **maximal consecutive runs**, in original left-to-right order.

- A run with exactly one element becomes `One element`.
- A run with two or more adjacent equal elements becomes `Many (count, element)`.
- Equal values in separate runs must remain separate; only adjacency determines a run.
- Every input occurrence is represented by exactly one output run count, so output order and multiplicity are significant.
- Empty input yields `[]`.

The interface has no option/result/failure case, mutation, effects, randomness, stream/coinductive behavior, string-specific behavior, or floating-point requirement. Because no comparator is part of the stated interface, equality is the ordinary equality needed to identify adjacent elements.

## Official example

```ocaml
encode ["a"; "a"; "a"; "a"; "b"; "c"; "c"; "a"; "a"; "d"; "e"; "e"; "e"; "e"]
= [ Many (4, "a"); One "b"; Many (2, "c"); Many (2, "a"); One "d";
    Many (4, "e") ]
```

## Benchmark boundary

This item supplies a formal contract and independent tests only. It deliberately contains **no OCaml implementation** and no copied published solution. A future backend may mechanically lower a synthesized candidate and must still run the independent OCaml tests before treating it as fulfilled.
