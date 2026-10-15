# 032 — Determine the Greatest Common Divisor of Two Positive Integer Numbers

## Provenance and solution quarantine

- **Authoritative source:** `ocaml/ocaml.org`, commit [`7b4c04b90b5433050bcecb25772880bc48bae4d0`](https://github.com/ocaml/ocaml.org/blob/7b4c04b90b5433050bcecb25772880bc48bae4d0/data/exercises/032_gcd.md), file `data/exercises/032_gcd.md`.
- **Acquisition:** read-only `gh api` at that exact commit.
- **Quarantine procedure:** the fetched Markdown was mechanically split at the one exact level-2 heading `## Solution`; that heading and all content through the next level-2 heading (or EOF) were discarded before inspection. The retained source had exactly one such heading and contains only front matter, the statement, and official examples. No solution body was read or used.
- **Front matter:** slug `32`; difficulty `intermediate`; tag `arithmetic`; description “Find the greatest common divisor of two positive integers using Euclid's algorithm.”

## Solution-free authoritative statement

> Determine the greatest common divisor of two positive integer numbers.
>
> Use Euclid's algorithm.

Official examples:

```ocaml
# gcd 13 27;;
- : int = 1
# gcd 20536 7826;;
- : int = 2
```

## Required OCaml boundary

```ocaml
val gcd : int -> int -> int
```

The exercise statement restricts both arguments to **positive integer numbers**. It states no behavior for zero or negative inputs; therefore this benchmark imposes no exception, option, or return-value requirement outside `a > 0 && b > 0`.

## Full semantic obligations on the stated domain

For all OCaml integers `a > 0` and `b > 0`, `d = gcd a b` must satisfy all of the following:

1. **Positivity:** `d > 0`.
2. **Common divisor:** `a mod d = 0` and `b mod d = 0`.
3. **Greatestness:** for every positive integer `c`, if `c` divides both `a` and `b`, then `c <= d`.
4. **Euclidean algorithm requirement:** the implementation must use Euclid's reduction: with `a, b > 0`, repeatedly replace `(a, b)` by `(b, a mod b)` until the second component is zero, then return the first component. This is an algorithm requirement from the source, not merely a sample-output requirement.
5. **No extra observable behavior is required:** the entrypoint is pure in the expected OCaml boundary; the statement specifies no mutation, I/O, randomness, strings, floats, options, exceptions, list ordering, coinductive values, or infinite streams.

Consequences such as symmetry (`gcd a b = gcd b a`) are tested as derived properties. They do not weaken the required greatest-common-divisor relation.

## Contract feasibility note

The pinned Synquid runtime can parse integer `+`, `-`, and `*` refinements and comparisons, but its formula grammar/builtin operator list has no integer remainder or division operation and no user-level quantifier syntax. An exact, unbounded GCD contract needs both (a) divisibility/remainder and (b) a universal greatestness condition, or an equally sound inductive predicate/measure for that relation. Therefore no `contract.sq` is supplied: inventing an uninterpreted `gcd`/`divides` predicate would be a vacuous, weaker contract rather than a valid formalization.
