# Exercise 033 — Determine Whether Two Positive Integer Numbers Are Coprime

## Provenance

- **Authoritative repository:** [`ocaml/ocaml.org`](https://github.com/ocaml/ocaml.org)
- **Pinned commit:** `7b4c04b90b5433050bcecb25772880bc48bae4d0`
- **Authoritative path:** `data/exercises/033_is_coprime.md`
- **Git blob:** `6e7f0fbb71a705e10a98fab3201e324b17c2a1a0`
- **GitHub source URL:** <https://github.com/ocaml/ocaml.org/blob/7b4c04b90b5433050bcecb25772880bc48bae4d0/data/exercises/033_is_coprime.md>
- **Retrieval:** read-only GitHub API request. The decoded file contained exactly one level-two `Solution` section; that entire section was removed before this benchmark source was inspected. Its body has not been read, used, or reproduced.

## Authoritative front matter

| Field | Value |
|---|---|
| Title | Determine Whether Two Positive Integer Numbers Are Coprime |
| Slug | `33` |
| Difficulty | beginner |
| Tags | arithmetic |
| Description | Determine if two positive integers are coprime, meaning their greatest common divisor is 1. |

## Statement

Determine whether two **positive integer** numbers are coprime.

Two numbers are coprime exactly when their greatest common divisor equals `1`.

## Required OCaml interface

```ocaml
val coprime : int -> int -> bool
```

### Domain and result contract

For every representable OCaml `int` pair `a`, `b` satisfying `a > 0 && b > 0`:

```text
coprime a b = true  iff  gcd(a, b) = 1
```

The authoritative exercise supplies no behavior for zero or negative inputs. They are **outside the precondition**, and this benchmark intentionally imposes no failure, option, or result convention for them.

No ordering, multiplicity, mutation, effects, randomness, streams, strings, floats, or exceptions are part of this interface. The function is expected to be a deterministic, pure Boolean decision procedure on its positive-input domain.

> The upstream non-solution material references a previously defined GCD helper. It is not copied here as an implementation, is not a trusted benchmark component, and is not synthesized output.

## Official examples

```ocaml
coprime 13 27 = true
not (coprime 20536 7826) = true
```

Equivalently, the second example requires `coprime 20536 7826 = false`.

## Contract strength

This is a **full semantic requirement** over the stated positive-input domain: it is not merely an example-based, bounded, length, or set-membership specification.
