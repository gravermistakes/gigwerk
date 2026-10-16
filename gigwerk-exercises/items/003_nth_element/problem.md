# 003 — N'th Element of a List

## Source and quarantine

- **Authoritative source:** [`ocaml/ocaml.org`](https://github.com/ocaml/ocaml.org), commit `7b4c04b90b5433050bcecb25772880bc48bae4d0`
- **Path:** `data/exercises/003_nth_element.md`
- **Blob SHA:** `fe19b460d9abaa3b2e27b48444f3d7cf35bcdb9b`
- **Retrieval:** read-only `gh api`; the `## Solution` H2 section was removed through the following H2/EOF before the source was displayed or inspected.

## Statement

Find the N'th element of a list.

### Official examples

```ocaml
# at 2 ["a"; "b"; "c"; "d"; "e"];;
- : string option = Some "c"
# at 2 ["a"];;
- : string option = None
```

The source remarks that `List.nth` indexes from `0` and raises an exception for an out-of-bounds index; its examples show `List.nth ["a"; "b"; "c"; "d"; "e"] 2` returning `"c"` and `List.nth ["a"] 2` raising `Failure "nth"`.

## Contract interpretation

The observed `at` result type is polymorphic option lookup: `int -> 'a list -> 'a option`.

For **nonnegative** positions, the test and synthesis contract use **zero-based** indexing. A valid position returns `Some` of the element at precisely that position; an index at or beyond the finite list length returns `None`. This preserves order and duplicate occurrence identity: it selects by position rather than membership/value.

The authoritative statement and examples do **not** specify behavior for negative OCaml `int` inputs. That omission is preserved as an explicit ambiguity: `contract.sq` and `test_generated.ml` deliberately do not constrain negative indices rather than inventing a result.

No effects, randomness, mutation, strings-specific behavior, floats, coinduction, or infinite inputs are involved. Lists are finite immutable OCaml lists.

## Scope boundary

This directory contains a contract and independent tests only. It contains **no final OCaml implementation** and makes no claim that a Synquid result has passed OCaml lowering or semantic tests.
