# Lotto: Draw N Different Random Numbers From the Set 1..M

## Authoritative provenance

- **Repository:** `ocaml/ocaml.org`
- **Pinned commit:** `7b4c04b90b5433050bcecb25772880bc48bae4d0`
- **Path:** `data/exercises/024_lotto.md`
- **GitHub contents blob SHA:** `d7a5ed9ddbc41c85a6525a392409786e93b57fd6`
- **Source URL:** <https://github.com/ocaml/ocaml.org/blob/7b4c04b90b5433050bcecb25772880bc48bae4d0/data/exercises/024_lotto.md>

The source was obtained through the read-only GitHub Contents API. Before any source content was displayed or inspected, exactly one `## Solution` section was removed from its heading through the next level-2 heading or EOF. This artifact contains no content from that quarantined section.

## Source metadata

| Field | Value |
|---|---|
| Title | Lotto: Draw N Different Random Numbers From the Set 1..M |
| Slug | 24 |
| Difficulty | beginner |
| Tags | list |
| Description | Draw N different random numbers from the set 1..M. |

## Statement

> Draw N different random numbers from the set `1..M`. The selected numbers shall be returned in a list.

## Official example

```ocaml
# lotto_select 6 49;;
- : int list = [20; 28; 45; 16; 24; 38]
```

The displayed numbers are one random result, **not** a deterministic expected output or required ordering.

## Acceptance semantics derived only from the statement and example

The entrypoint is `lotto_select : int -> int -> int list`, with arguments `n` then `m`.

For a stated feasible draw (`0 <= n`, `0 <= m`, and `n <= m`), each invocation must return a list that:

1. has exactly `n` elements;
2. contains only integers in the inclusive interval `1..m`; and
3. contains no integer more than once.

The output order is not specified. No fixed result, canonical traversal order, seed, probability distribution, exception behavior, or behavior for infeasible inputs (`n < 0`, `m < 0`, or `n > m`) is stated by the authoritative non-solution material; this benchmark does not invent any of those requirements.

`random` is semantically material: the original interface has no seed argument and therefore any OCaml implementation that genuinely draws random values must rely on an effectful source such as the ambient `Random` generator. This is retained as a requirement rather than converted into a deterministic seeded API.
