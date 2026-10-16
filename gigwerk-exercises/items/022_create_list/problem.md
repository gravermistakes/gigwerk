# 022 — Create a List Containing All Integers Within a Given Range

## Provenance

- **Authoritative source:** [`ocaml/ocaml.org`](https://github.com/ocaml/ocaml.org), commit `7b4c04b90b5433050bcecb25772880bc48bae4d0`
- **Path:** `data/exercises/022_create_list.md`
- **Retrieval:** read-only GitHub `gh api` blob request.
- **Solution quarantine:** before inspection, the exact Markdown section beginning at `## Solution` was removed through the next level-2 heading (or EOF). This artifact uses only the remaining front matter and statement.

## Source statement

> If first argument is greater than second, produce a list in decreasing order.
>
> ```ocaml
> # range 4 9;;
> - : int list = [4; 5; 6; 7; 8; 9]
> ```

## Required interface

```ocaml
val range : int -> int -> int list
```

## Complete contract interpretation

For all mathematical-integer inputs `first` and `last`, `range first last` is the **inclusive** sequence between its endpoints:

- if `first <= last`, it is `[first; first + 1; ...; last]` in strictly increasing order;
- if `first > last`, it is `[first; first - 1; ...; last]` in strictly decreasing order;
- therefore `range n n = [n]`.

The output must preserve this exact order and all values: no omitted intermediate integer, duplicate, extra integer, reversal, sorting-only behavior, or set-only approximation is permitted. The list is finite. The operation is pure and deterministic; it does not use randomness, mutable state, I/O, strings, floats, options, exceptions as normal results, or infinite/coinductive streams.

### Scope note

The formal Synquid contract uses mathematical `Int`. Standard OCaml `int` is bounded, so inputs whose inclusive range cannot be represented/materialized are outside the practical execution envelope; this benchmark does not introduce a nonstandard overflow or resource-failure behavior.
