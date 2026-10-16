# 017 — Split a List Into Two Parts; The Length of the First Part Is Given

## Provenance

- **Repository:** [`ocaml/ocaml.org`](https://github.com/ocaml/ocaml.org)
- **Pinned commit:** `7b4c04b90b5433050bcecb25772880bc48bae4d0`
- **Authoritative path:** `data/exercises/017_split_list.md`
- **Retrieval:** read-only GitHub API via `gh api`.
- **Solution quarantine:** the source’s `## Solution` section was removed in-memory before this statement was read. It was not used or reproduced.

## Statement

Split a list into two parts; the length of the first part is given. If the requested first-part length is longer than the whole list, the first part is the whole list and the second part is empty.

## Official examples

```ocaml
# split ["a"; "b"; "c"; "d"; "e"; "f"; "g"; "h"; "i"; "j"] 3;;
- : string list * string list =
(["a"; "b"; "c"], ["d"; "e"; "f"; "g"; "h"; "i"; "j"])

# split ["a"; "b"; "c"; "d"] 5;;
- : string list * string list = (["a"; "b"; "c"; "d"], [])
```

## Explicit semantic reading used by the contract

For an input list `xs` and a **nonnegative** requested length `n`, return `(prefix, suffix)` such that:

1. `prefix` followed by `suffix` is exactly `xs`; therefore order and duplicate multiplicity are preserved.
2. `length prefix = min(n, length xs)`.
3. Consequently, `suffix` is the remaining contiguous suffix and is empty when `n >= length xs`.

> The statement does not specify a result, exception, or other behavior for a negative OCaml `int`. The Synquid contract therefore has the explicit precondition `n >= 0`; this unresolved interface-domain detail is reported in the assessment rather than invented.

## Non-goals

- No randomness, effects, mutation, strings-as-implementation, floats, streams, options, or exceptions are specified.
- No executable solution or published solution body is contained in this item.
