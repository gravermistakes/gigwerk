---
id: "009_pack_duplicates"
title: "Pack Consecutive Duplicates"
upstream_repository: "ocaml/ocaml.org"
upstream_commit: "7b4c04b90b5433050bcecb25772880bc48bae4d0"
upstream_path: "data/exercises/009_pack_duplicates.md"
upstream_slug: "9"
upstream_difficulty: "intermediate"
upstream_tags: ["list"]
---

# Pack Consecutive Duplicates

## Provenance and source quarantine

This item was derived only from the front matter, **Statement**, and official REPL example in the pinned upstream file above, obtained through the read-only GitHub Contents API. Its `## Solution` section was located as exactly one level-2 section and discarded in memory before the retained source was inspected. No solution body is reproduced or used here.

Retained non-solution source SHA-256: `5ceaafc7c4fe0c919c4fab7a691679e8995087630c02ce680c1bdbb9efa3e56f`.

## Upstream statement

> Pack consecutive duplicates of list elements into sublists.

The upstream official example is:

```ocaml
pack ["a"; "a"; "a"; "a"; "b"; "c"; "c"; "a"; "a"; "d"; "d"; "e"; "e"; "e"; "e"]
= [["a"; "a"; "a"; "a"]; ["b"]; ["c"; "c"]; ["a"; "a"]; ["d"; "d"]; ["e"; "e"; "e"; "e"]]
```

## Required behavior

`pack` partitions its input into its **maximal, non-empty contiguous runs of equal values**, in left-to-right input order.

For every input list `xs`, the returned list of lists `groups` must satisfy all of the following:

1. **Exact sequence preservation:** concatenating `groups` returns exactly `xs`, preserving order and every occurrence.
2. **Uniform non-empty groups:** every group has at least one value and all values in that group are equal.
3. **Maximality:** representative values of adjacent groups differ. Thus equal values separated by another value are not coalesced.
4. **Empty case:** `pack [] = []`.

These three invariants give a canonical result, not merely a list with the same length or set of values.

## Scope

The upstream statement gives an example at `string` values but no explicit type annotation. This benchmark uses OCaml's principal polymorphic interface for the stated list operation, with ordinary polymorphic equality as the only required primitive. It is pure and deterministic: no randomness, effects, mutable state, strings as a special theory, floats, option/failure behavior, or infinite/coinductive streams are involved.
