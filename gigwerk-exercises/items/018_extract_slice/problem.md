# Extract a Slice From a List

## Provenance

- **Authoritative source:** [`ocaml/ocaml.org` at commit `7b4c04b90b5433050bcecb25772880bc48bae4d0`](https://github.com/ocaml/ocaml.org/blob/7b4c04b90b5433050bcecb25772880bc48bae4d0/data/exercises/018_extract_slice.md)
- **Source path:** `data/exercises/018_extract_slice.md`
- **Upstream metadata:** slug `18`; difficulty `intermediate`; tag `list`
- **Acquisition:** GitHub Contents API through preconfigured `gh`; blob SHA `1757877ec5ce861504b1fec49d29c3526111097e`.
- **Solution quarantine:** exactly one `## Solution` section was found and removed before this statement was inspected. It extended to EOF (1,213 bytes). No body from that section was read or reproduced. The retained, solution-free source SHA-256 was `11ba5837d5d719d2181c96733aaf608f81ce46c45de38fec3c5f18fb29d2df7a`.

## Statement

Given two indices `i` and `k`, return the list containing the elements between the `i`th and `k`th elements of the original list, **including both limits**. Elements are numbered from **0**, matching the `List` module convention.

## Required OCaml interface

```ocaml
val slice : 'a list -> int -> int -> 'a list
```

The formal benchmark domain is `0 <= i <= k < List.length xs`. The upstream statement gives no behavior for empty input, negative indices, `i > k`, or indices outside the list; this item deliberately does not invent exception, option, or clamping behavior outside that domain.

## Official example

```ocaml
# slice ["a"; "b"; "c"; "d"; "e"; "f"; "g"; "h"; "i"; "j"] 2 6;;
- : string list = ["c"; "d"; "e"; "f"; "g"]
```

## Semantic requirements

- Return exactly the contiguous interval of original positions `i` through `k`.
- Preserve **left-to-right traversal order**.
- Preserve **multiplicity**: equal values at different positions remain separate occurrences.
- The inclusive output length is `k - i + 1` on the valid domain.
- This is pure, finite, polymorphic list processing; it requires no randomness, effects, mutation, strings, floats, coinduction, or infinite streams.
