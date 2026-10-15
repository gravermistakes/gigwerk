# 001_tail — Tail of a List

## Provenance and solution quarantine

- **Authoritative repository:** `ocaml/ocaml.org`
- **Pinned commit:** [`7b4c04b90b5433050bcecb25772880bc48bae4d0`](https://github.com/ocaml/ocaml.org/blob/7b4c04b90b5433050bcecb25772880bc48bae4d0/data/exercises/001_tail.md)
- **Pinned path:** `data/exercises/001_tail.md`
- **Retrieved Git blob:** `108c6ce689ab7df3b71c2f725c3664fb147bfc9a`

The source was retrieved through the preconfigured read-only `gh api` Git-blob API. A section was defined as a `##` heading through the next `##` heading or EOF. Exactly one `## Solution` heading was found, and that entire byte range was removed before the source was inspected. This artifact contains only the resulting front matter and non-solution statement.

## Source front matter

- **Title:** Tail of a List
- **Slug:** `"1"`
- **Difficulty:** beginner
- **Tags:** `list`
- **Description:** Write a function that returns the last element of a list.
- **Tutorials:** `lists`

## Statement

Write a function `last : 'a list -> 'a option` that returns the last element of a list.

## Official examples

```ocaml
# last ["a" ; "b" ; "c" ; "d"];;
- : string option = Some "d"
# last [];;
- : 'a option = None
```

## Exact behavioral requirement

For every finite OCaml list `xs`:

- if `xs = []`, `last xs = None`;
- if `xs = [x1; ...; xn]` with `n > 0`, `last xs = Some xn`.

The selected value is the **element at the final position**, not merely a member of the list. Thus element ordering and repeated values matter. The function is polymorphic, deterministic, pure, and total over finite lists. It raises no failure and performs no mutation, I/O, random sampling, string-specific processing, floating-point processing, or infinite/coinductive-stream operation.
