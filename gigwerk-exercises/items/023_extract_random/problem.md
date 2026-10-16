# 023 — Extract a Given Number of Randomly Selected Elements From a List

## Provenance

- **Authoritative repository:** [`ocaml/ocaml.org`](https://github.com/ocaml/ocaml.org)
- **Pinned revision:** `7b4c04b90b5433050bcecb25772880bc48bae4d0`
- **Pinned path:** `data/exercises/023_extract_random.md`
- **Retrieval:** read-only `gh api` at the pinned revision on 2026-10-14.
- **Solution quarantine:** exactly one `## Solution` heading was found. Its section (from that heading to EOF) was removed before inspection. No solution body was read or used.

## Source metadata

| Field | Value |
|---|---|
| Title | Extract a Given Number of Randomly Selected Elements From a List |
| Slug | `23` |
| Difficulty | intermediate |
| Tags | `list` |
| Description | Randomly select N elements from a list. |

## Statement (solution-free)

> The selected items shall be returned in a list. We use the `Random` module and initialise it with `Random.init 0` at the start of the function for reproducibility and validate the solution. To make the function truly random, however, one should remove the call to `Random.init 0`.

## Official example

```ocaml
# rand_select ["a"; "b"; "c"; "d"; "e"; "f"; "g"; "h"] 3;;
- : string list = ["e"; "c"; "g"]
```

## Contract boundary and open points

The benchmark entrypoint is inferred from the official REPL example as:

```ocaml
val rand_select : 'a list -> int -> 'a list
```

For documented, valid requests (`0 <= n <= List.length xs`), the exercise is an extraction/sample operation: the output has `n` occurrences and cannot contain any value more often than it occurs in `xs`. The official example also fixes one exact seeded output and output order.

The non-solution source **does not state** behavior for `n < 0` or `n > List.length xs`. It likewise does not define the general algorithm/random-draw schedule that would determine every seeded output beyond the one official example. These omissions are preserved as ambiguity; this item does not invent exception, option, clamping, or duplicate-selection behavior for those domains.

The requested behavior is effectful: each invocation initializes OCaml's global `Random` state with `Random.init 0`, then performs random selection. Removing initialization intentionally changes the contract to depend on ambient PRNG state and become genuinely random.

## Synthesis scope

No executable solution is included. A full Synquid contract is not emitted because this runtime does not provide a sound model for the required `Random` initialization/draw effects and their exact OCaml behavior. See `assessment.md`.
