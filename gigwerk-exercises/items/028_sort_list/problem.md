# 028 — Sorting a List of Lists According to Length of Sublists

## Provenance and quarantine

- **Authoritative source:** `ocaml/ocaml.org`, commit [`7b4c04b90b5433050bcecb25772880bc48bae4d0`](https://github.com/ocaml/ocaml.org/blob/7b4c04b90b5433050bcecb25772880bc48bae4d0/data/exercises/028_sort_list.md)
- **Path:** `data/exercises/028_sort_list.md`
- **Retrieved through:** read-only `gh api` at the pinned commit.
- **Quarantine procedure:** the source was decoded, then the level-two solution section was removed through the next level-two heading/EOF *before* this item was inspected. In that source revision, the removed range was lines 9–51. No text or code from that section is used in this item.

## Source metadata

| Field | Value |
|---|---|
| Title | Sorting a List of Lists According to Length of Sublists |
| Slug | `28` |
| Difficulty | intermediate |
| Tags | `list` |
| Source description | Sort a list of lists based on the frequency of sublist lengths in ascending order, with lists of less frequent lengths coming first. |

## Statement (solution-free)

The input is a list whose elements are themselves lists.

1. `length_sort` sorts the outer list according to the lengths of its inner lists. The statement describes both short-to-long and the converse; its official example invokes the ascending form.
2. `frequency_sort` sorts the outer list according to the **frequency of each inner-list length**. In the default ascending direction, inner lists whose length occurs less often in the input appear before inner lists whose length occurs more often.

## Required interface

```ocaml
val length_sort : 'a list list -> 'a list list
val frequency_sort : 'a list list -> 'a list list
```

The official source demonstrates both names on `string list list`. The polymorphic element type follows from the operation: only inner-list structure/length is inspected; elements must be returned unchanged.

## Semantic obligations

For either entry point and every finite `input`:

1. The result is an outer-list **permutation** of `input`: each complete inner list occurs with exactly the same multiplicity. Consequently, the function neither creates, drops, nor changes elements inside an inner list.
2. `length_sort input` has nondecreasing inner-list lengths.
3. `frequency_sort input` has nondecreasing keys `count_input (List.length inner)`, where the count is taken over the original input, not a progressively modified result.
4. Empty outer lists and empty inner lists are valid. Repeated equal inner lists and repeated equal lengths must remain repeated.
5. The exercise describes no errors, options, mutation, effects, randomness, floats, strings-as-data behavior, or infinite/coinductive inputs. It is a pure operation on finite lists.

### Tie behavior

The non-solution statement specifies ascending keys but no tie-breaker for equal lengths (`length_sort`) or equal frequencies (`frequency_sort`). Therefore it does **not** require stability or a canonical order within an equal-key block. The displayed examples are valid illustrations, not evidence for an unstated total tie order. Tests validate permutation plus nondecreasing required key, so they do not incorrectly reject another valid equal-key permutation.

## Official examples

```ocaml
# length_sort [["a"; "b"; "c"]; ["d"; "e"]; ["f"; "g"; "h"]; ["d"; "e"];
             ["i"; "j"; "k"; "l"]; ["m"; "n"]; ["o"]];;
- : string list list =
[["o"]; ["d"; "e"]; ["d"; "e"]; ["m"; "n"]; ["a"; "b"; "c"]; ["f"; "g"; "h"];
 ["i"; "j"; "k"; "l"]]

# frequency_sort [["a"; "b"; "c"]; ["d"; "e"]; ["f"; "g"; "h"]; ["d"; "e"];
                ["i"; "j"; "k"; "l"]; ["m"; "n"]; ["o"]];;
- : string list list =
[["i"; "j"; "k"; "l"]; ["o"]; ["a"; "b"; "c"]; ["f"; "g"; "h"]; ["d"; "e"];
 ["d"; "e"]; ["m"; "n"]]
```

The supplied test artifact embeds these concrete inputs and displayed outputs as semantic illustrations, then separately checks each candidate result against the stated relation.
