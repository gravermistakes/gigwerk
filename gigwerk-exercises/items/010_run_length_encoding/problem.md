# Exercise 010 — Run-Length Encoding

## Provenance

- **Authoritative source:** [`ocaml/ocaml.org` at commit `7b4c04b90b5433050bcecb25772880bc48bae4d0`](https://github.com/ocaml/ocaml.org/blob/7b4c04b90b5433050bcecb25772880bc48bae4d0/data/exercises/010_run_length_encoding.md)
- **Path:** `data/exercises/010_run_length_encoding.md`
- **Retrieval:** read-only GitHub API through the preconfigured `gh` client.
- **Quarantine:** exactly one `## Solution` section was mechanically removed before the source was inspected. This artifact derives only from the front matter, statement, and official example that remained.

## Statement

Perform run-length encoding on a list.

The required entry point is:

```ocaml
val encode : 'a list -> (int * 'a) list
```

The output is the left-to-right sequence of **maximal, non-empty contiguous runs** in the input. Each output pair contains the run's positive length and its repeated element. Equal elements that occur in separate regions of the input remain separate output runs.

## Official example

```ocaml
# encode ["a"; "a"; "a"; "a"; "b"; "c"; "c"; "a"; "a"; "d"; "e"; "e"; "e"; "e"];;
- : (int * string) list =
[(4, "a"); (1, "b"); (2, "c"); (2, "a"); (1, "d"); (4, "e")]
```

## Contract interpretation

For every finite input list:

1. `[]` encodes to `[]`.
2. Each output pair `(n, x)` represents exactly one maximal adjacent run of `x`, with `n > 0`.
3. Output runs have the same left-to-right order as the represented input runs.
4. Concatenating `n` copies of each pair's element reconstructs the input exactly, including ordering and multiplicity.
5. Adjacent output pairs have distinct representative values; the same value may occur in distinct non-adjacent pairs.

The task is pure and deterministic. It has no errors, options, mutation, effects, randomness, strings-only restriction, floating-point behavior, or infinite/coinductive-stream requirement. The polymorphic OCaml interface relies on OCaml equality for run boundary comparison.
