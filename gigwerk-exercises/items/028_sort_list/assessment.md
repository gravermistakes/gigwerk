# Assessment — 028_sort_list

## Status

| Field | Value |
|---|---|
| Contract status | **requires_features** |
| Specification strength | **full** requirement description and independent tests |
| Synthesis status | **not_attempted** |
| Actual synthesis elapsed seconds | **0** |
| `contract.sq` | Intentionally absent |
| `synthesis.out` / `synthesis.err` | Absent because no attempt was sound to make |

## Why no Synquid contract was run

The pinned Synquid source was inspected for current list/refinement syntax. Its list examples expose measures such as scalar length and extensional `Set` of elements. A `Set` cannot retain duplicate inner lists. For this exercise, duplicate preservation is essential: `[[]; []]` must not become `[[]]`, and two equal nonempty inner lists must remain two values.

`frequency_sort` additionally needs the number of outer-list members with a particular **derived** key (`List.length inner`), evaluated from the original input. A length measure or an extensional set cannot express that occurrence count. A valid full contract must relate the input and output with a nested-list **multiset/permutation** relation and quantify/count membership by length, then constrain adjacent output keys. The available supported measures/theories do not provide that relation.

Writing a contract that only equated outer length, total inner lengths, or element sets would admit implementations that drop, duplicate, merge, or alter inner lists. It would be a deliberately weak contract and is prohibited for this benchmark. Therefore no `contract.sq` was created and Synquid was not invoked.

## Minimal feature set needed

1. **Bags/multisets (or an equivalent inductive permutation predicate)** over complete nested-list values, preserving multiplicity.
2. **Derived-key occurrence counting**: count outer elements whose `inner_length` equals a supplied natural number.
3. A refinement/inductive relation connecting the output's key sequence to input-derived counts, while leaving equal-key tie order unconstrained.
4. Synthesis support for those definitions without treating either target algorithm as trusted.

## Semantic interpretation

- `length_sort` returns an outer-list permutation with nondecreasing inner-list lengths.
- `frequency_sort` returns an outer-list permutation with nondecreasing frequencies of each inner-list length in the **input**.
- The source gives no tie-break rule. In particular, tests do not require stability or reproduce an implementation-specific ordering within equal-key blocks.
- Inputs are finite polymorphic OCaml nested lists. No exception, option, seed, mutation, randomness, float, string-specific, effectful, or infinite-stream semantics are introduced.

## Test artifact

`test_generated.ml` opens `Generated`, uses only the OCaml standard library, and contains:

- the official concrete examples;
- direct checks for nested-list multiplicity preservation and required key monotonicity;
- empty/repeated-list edge cases;
- 341 exhaustive small outer-list cases;
- a deliberate drop-all **negative control** that the same semantic assertion must reject.

The tests are an independent oracle only. They are not synthesis inputs and do not provide a final implementation.

### Negative-control verification evidence

A temporary explicitly invalid `Generated` module whose two entry points both return `[]` was compiled with `ocamlc 4.14.1` against this test file. Running it exited **2** with the expected assertion:

> `official length_sort candidate: output is not a multiplicity-preserving permutation of the input`

The temporary invalid module and executable were removed afterward; they are not deliverables and are not an implementation candidate.

## Candidate caveat

No candidate exists. Even if future tooling synthesizes a term satisfying an enriched logical contract, it remains only a candidate until a typed OCaml lowering is compiled and this semantic test suite is run successfully.
