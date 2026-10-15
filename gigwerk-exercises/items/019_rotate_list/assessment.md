# Assessment — 019 Rotate a List N Places to the Left

## Status

| Field | Value |
|---|---|
| Contract status | **ambiguous** |
| Specification strength | **partial** |
| Synthesis status | **not attempted** |
| Actual synthesis elapsed time | **0 seconds** |
| Entrypoint | `rotate : 'a list -> int -> 'a list` |

## Provenance and solution quarantine

The sole authoritative source was retrieved read-only through the GitHub API:

- Repository: `ocaml/ocaml.org`
- Commit: `7b4c04b90b5433050bcecb25772880bc48bae4d0`
- Path: `data/exercises/019_rotate_list.md`

A section beginning at the exact level-2 heading `## Solution` was removed
before any source content was displayed or inspected. Its bodies were not
used. `problem.md` contains only the sanitized front matter, statement, and
official example.

## Exact evidenced interface

```ocaml
val rotate : 'a list -> int -> 'a list
```

The argument order is list, then integer count, as shown in the official call:

```ocaml
rotate ["a"; "b"; "c"; "d"; "e"; "f"; "g"; "h"] 3
```

## Semantic obligations retained

Within the source-evidenced, unambiguous finite domain `0 <= n <= length xs`,
`rotate xs n` must equal the suffix beginning at index `n` followed by the
prefix ending immediately before `n`. It must preserve order and every
occurrence—duplicates cannot be collapsed or reordered.

The official example therefore requires:

```ocaml
rotate ["a"; "b"; "c"; "d"; "e"; "f"; "g"; "h"] 3
= ["d"; "e"; "f"; "g"; "h"; "a"; "b"; "c"]
```

For `[]`, the result is necessarily `[]`; reordering an empty input cannot
produce elements.

## Why this is not a full contract

The non-solution source does not state what to do when:

1. `n < 0`;
2. `n > length xs`; or
3. a count requires a decision about modulo normalization versus a
   precondition/error behavior.

No behavior was invented for those inputs. Therefore the benchmark cannot
honestly be labelled `full` from the permitted source alone.

The inspected pinned Synquid examples expose `len` and `elems : List a -> Set
a` measures. Those can prove output length and membership/set equality, but
cannot express the required **ordered sequence with multiplicity** relation:
sets erase duplicates and ordering. The task explicitly forbids executing a
contract that is weak in this way. A proper future Synquid contract needs an
order- and multiplicity-sensitive sequence relation, plus an authoritative
resolution of out-of-range count semantics.

No `contract.sq` was written and no synthesis command was run; hence no
candidate is implied.

## Independent tests

`test_generated.ml` is standard-library-only, opens `Generated`, and contains
no `rotate` implementation. Its test-only oracle is not a synthesis input.
Coverage includes:

- the official string example;
- zero and full-cycle rotations;
- duplicate preservation;
- empty input;
- every binary list of lengths 0–4, for every `n` from 0 through its length.

A deliberately wrong identity stub was compiled only in the scratch directory
and run against this suite. It exited `1` with the expected semantic failure:

```text
rotate_list tests: FAIL: official example: rotate left by 3
```

The retained command/result record is `negative_control_verification.txt`.
This verifies the suite rejects at least that incorrect behavior; it does not
validate any future candidate.

## Constraints and caveats

- No final OCaml implementation was authored or manually lowered.
- No candidate has been compiled as `Generated` and passed the suite.
- The operation has no stated requirement for randomness, effects, mutable
  state, floats, strings as a special theory, coinduction, or infinite streams.
- The artifacts are OCaml-source-oriented and phone-readable, but no Android
  build was attempted or claimed.
