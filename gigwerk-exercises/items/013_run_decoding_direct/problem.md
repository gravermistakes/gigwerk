# Exercise 013 — Run-Length Encoding of a List (Direct Solution)

## Provenance

- **Authoritative repository:** `ocaml/ocaml.org`
- **Pinned commit:** `7b4c04b90b5433050bcecb25772880bc48bae4d0`
- **Path:** `data/exercises/013_run_decoding_direct.md`
- **Blob SHA:** `e583d790c1a318d7d26e8e7a89bbc477419543e4`
- **Extraction:** the unique `## Solution` section was mechanically removed from its heading through the following level-2 heading or EOF before this artifact was inspected. No solution body was read or used.

## Source statement (solution-free)

```ocaml
type 'a rle =
  | One of 'a
  | Many of int * 'a
```

Implement the so-called run-length encoding data compression method directly. Do not explicitly create the sublists containing duplicates; instead count them. As in modified run-length encoding, simplify a singleton run `(1, X)` to `One X`.

Official example:

```ocaml
encode ["a"; "a"; "a"; "a"; "b"; "c"; "c"; "a"; "a"; "d"; "e"; "e"; "e"; "e"]
= [Many (4, "a"); One "b"; Many (2, "c"); Many (2, "a"); One "d"; Many (4, "e")]
```

## Benchmark requirement made explicit

The entrypoint is `encode : 'a list -> 'a rle list` (the name is present in the official example; its type follows from the declared `rle` type and the example).

For a finite input list, partition the list **left to right** into its unique maximal nonempty consecutive runs under the language equality used by the implementation. Emit exactly one output node for each run, in the same order:

- A run containing exactly one value `x` becomes `One x`.
- A run containing `n >= 2` copies of `x` becomes `Many (n, x)`.

Consequences that are contractual rather than merely examples:

1. `[]` encodes to `[]`.
2. Output order is input run order. Equal values separated by another value are separate runs and must never be merged.
3. Every output node represents a positive run length; `Many` is used only for a count of at least two.
4. Adjacent output nodes have distinct representative values, so the output is canonical/maximally compressed.
5. Expanding `One x` to `[x]` and `Many (n, x)` to `n` consecutive copies of `x`, then concatenating in output order, reconstructs the exact input sequence, including ordering and multiplicity.
6. “Directly” is an implementation constraint: do not first materialize a list of duplicate sublists. It does not weaken any observable semantic obligation above.

## Scope and language-boundary notes

- The source has no randomness, effects, mutation, I/O, coinductive/infinite-stream, string-processing, or floating-point arithmetic requirement. `encode` is deterministic and pure over ordinary finite OCaml lists.
- The source is polymorphic. No string-specific behavior is required; strings in the official example are ordinary values.
- Equality behavior is not independently spelled out by the source. A mechanical OCaml lowering must use the chosen equality primitive consistently to determine *consecutive equality*. With `Stdlib.( = )`, floating-point `nan` does not equal itself, and values containing functions can raise when comparison is attempted. The stated interface cannot add an equality typeclass or seed without changing it.
- The source does not define behavior for non-terminating equality, cyclic values manufactured outside normal typed-list construction, or equality exceptions. Such language-level cases must be recorded by a backend rather than silently changing the signature.
