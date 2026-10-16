# Exercise 016 — Drop Every N'th Element From a List

## Provenance

- **Authoritative source:** `ocaml/ocaml.org` at commit `7b4c04b90b5433050bcecb25772880bc48bae4d0`
- **Path:** `data/exercises/016_drop_elements.md`
- **Source title:** *Drop Every N'th Element From a List*
- **Quarantine:** the upstream level-2 `## Solution` section was removed in memory before the retained source was written or inspected. This artifact uses only front matter, the statement, and the official example.

## Stated task

> Drop every N'th element from a list.

The entry point is called `drop`, with the list first and the period second, as shown by the source's OCaml toplevel example.

```ocaml
# drop ["a"; "b"; "c"; "d"; "e"; "f"; "g"; "h"; "i"; "j"] 3;;
- : string list = ["a"; "b"; "d"; "e"; "g"; "h"; "j"]
```

## Full semantic requirement used by this benchmark

For a **positive** period `n`, number the input positions from **1** at the head. Return exactly the subsequence of input elements whose positions are not positive multiples of `n`:

\[
  \operatorname{drop}(xs,n) = [\,xs_i \mid 1 \le i \le |xs| \land i \bmod n \ne 0\,].
\]

The output must preserve the order of retained elements and preserve each retained occurrence; it is not merely a set of values or a list of a prescribed length. Hence `n = 1` returns `[]`; an empty input returns `[]`; and `n > length xs` returns `xs` unchanged.

## Scope boundary

The authoritative source supplies no behavior for `n <= 0`. The independent test suite exercises only positive `n`; the reusable backend must not silently claim a failure/option/result convention for non-positive periods from this source alone.

There is no randomness, I/O, mutable state, stream/coinductive behavior, string-specific behavior, float behavior, or unsupported theorem claim in the required operation.
