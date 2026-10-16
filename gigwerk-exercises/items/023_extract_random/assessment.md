# Assessment — 023 Extract Random

## Status

| Field | Value |
|---|---|
| Contract status | **requires_features** |
| Specification strength | **partial** |
| Synthesis status | **not attempted** |
| Actual synthesis elapsed time | **0 seconds** |
| `contract.sq` | Not emitted |

## Why no Synquid contract was attempted

The pinned Synquid corpus confirms support for pure refinement types, algebraic lists, termination measures, and set-valued measures. For example, the local `List-Delete.sq` can state a set relation. That is insufficient here.

The exercise explicitly requires the effectful OCaml action `Random.init 0` at the start of every entrypoint invocation. A conforming implementation also needs bounded PRNG draws, and its observable output order depends on the number and placement of those draws. This runtime has no declared state/PRNG component or effect/probabilistic semantics that faithfully capture those facts. Treating `Random` as an unconstrained trusted primitive would make an alleged proof of the official exact output unsound.

A pure approximation such as `len result = n` plus `elems result ⊆ elems xs` is deliberately rejected. It loses occurrence multiplicity, selection ordering, seed initialization, and the official result `["e"; "c"; "g"]`. It would therefore be a weak contract, not a contract for this exercise.

## Minimal features needed

1. **Stateful PRNG effect:** an exact specification of OCaml `Random.init 0` and bounded `Random.int`, including fresh per-call state.
2. **Probabilistic/effect semantics:** enough to specify randomized extraction rather than only an extensional pure result relation.
3. **Sequence/multiset refinements:** to retain output order and repeated-value occurrence counts, not merely element sets.
4. **More authoritative specification:** explicit invalid-count behavior and a full seeded draw/order definition if exhaustive exact-output equivalence is a target.

## Source-level semantic obligations retained

For the documented valid-input domain, the benchmark retains these obligations:

- `rand_select : 'a list -> int -> 'a list`.
- A result contains exactly the requested number of extracted occurrences.
- It cannot use a value more often than the source contains it.
- It initializes `Random` with `0` at the start of **each call** in reproducible mode.
- It matches the official documented call exactly:

  ```ocaml
  rand_select ["a"; "b"; "c"; "d"; "e"; "f"; "g"; "h"] 3
  = ["e"; "c"; "g"]
  ```

The source leaves negative counts, counts above the list length, and the general seeded-draw schedule unspecified. This component does not silently select an exception, option, clamping, or replacement policy.

## Tests and negative control

`test_generated.ml` is independent OCaml oracle code. It opens `Generated` and contains no selection algorithm or PRNG code. It checks the official example exactly; per-call reproducibility; zero, singleton, duplicate-containing, partial, and full valid samples; result length; and multiplicity preservation.

`negative_control_generated.ml` is intentionally wrong and labeled as such. It always returns `[]`. Compiling it with the independent test file must fail the official-example semantic assertion. This demonstrates that the test suite is capable of rejecting a simple wrong implementation; it is not a synthesized or candidate implementation.

No claim is made that finite tests establish a theorem about random behavior. Any later Synquid output is only a **candidate** until it is mechanically lowered and passes the OCaml semantic suite.
