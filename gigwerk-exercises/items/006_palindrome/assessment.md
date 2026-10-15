# Assessment — 006 Palindrome

## Status

| Field | Value |
|---|---|
| Contract status | **requires_features** |
| Specification strength | **full** |
| Synquid status | **rejected** — no candidate produced |
| Actual synthesis time | **2.12270021 seconds** across two bounded attempts |
| Public entry point | `is_palindrome : 'a list -> bool` |

## Exact semantic obligation

For every **finite** input list `xs`, return `true` exactly when `xs` is equal, as an ordered sequence with all duplicates preserved, to its reversal. Return `false` otherwise.

This rules out set equality, length-only checks, an always-true result, and any comparison that ignores positions or duplicate counts. There is no source-specified option/failure result, mutation, effect, randomness, index convention, or infinite-stream behavior.

The source provides a polymorphic OCaml interface and no custom equality parameter. The stated backend interpretation is ordinary OCaml structural equality. Thus strings are ordinary element values; floats are permitted by the type but no float theory is modeled. In particular, OCaml's normal `nan` and functional-value equality caveats remain language-level caveats rather than silently altered requirements.

## Provenance and solution quarantine

- **Repository:** `ocaml/ocaml.org`
- **Pinned commit:** `7b4c04b90b5433050bcecb25772880bc48bae4d0`
- **Source:** `data/exercises/006_palindrome.md`

The file was fetched through the read-only GitHub API. Its single exact `## Solution` section was removed through the following `##` heading or EOF **before inspection**. No solution body appears in, or informed, these artifacts.

## Contract

`contract.sq` models exact `appendModel` and `reverseModel` as recursive **list-valued** measures. The final refinement is:

```text
is_palindrome xs = true  iff  xs == reverseModel xs
```

All `append`, `reverse`, and `is_palindrome` bodies are `??` synthesis holes. The only declared component is generic equality (`eq`), explicitly marked as a trusted supporting primitive, not the exercise algorithm.

## Synthesis evidence

Both invocations used the pinned runtime and command form requested, each externally limited to 60 seconds.

| Attempt | Exit | Elapsed | Outcome |
|---|---:|---:|---|
| 1 | 1 | 1.043009104 s | Rejected: `eq` was selected during `append` search and Synquid reported `Cannot match shape 'Bool' with shape '_'`. |
| 2 | 1 | 1.079691106 s | Rejected: a component-order/minimization revision gave the same error. |

The runtime itself parsed a list-valued measure probe successfully. The blocker is instead a synthesis-safe way to provide polymorphic equality for the exact Boolean result without the runtime attempting that Boolean component in incompatible list-valued helper goals.

> **Minimal missing feature:** a synthesis-safe polymorphic equality component (or exact finite-list-equality primitive) whose use is scoped to compatible Boolean goals and whose later lowering is verified against OCaml `(=)`.

`synthesis.out` and `synthesis.err` retain the final attempted run. The two attempts' exit codes and durations are recorded in `assessment.json`.

## Independent tests

`test_generated.ml` opens `Generated` and contains no final implementation. It includes the two official examples, edge cases, positional and multiplicity checks, ordinary string/float cases, and an exhaustive oracle comparison for all ternary integer lists of lengths 0–6 (**1,093 lists**).

A separately located, explicitly labelled **test-only negative-control stub** was compiled with these tests. It implements the known-wrong behavior `fun _ -> true`; compilation exited 0, and execution exited 2 at the named assertion:

```text
negative-control: not always true: expected false but got true
```

This confirms the tests reject that semantic defect. It does **not** establish any candidate as correct.

## Backend next step

Do not treat this item as synthesized. Add the missing scoped equality capability, synthesize a candidate without disabling checks or using partial/nonterminating mode, mechanically lower it to OCaml, then compile and run `test_generated.ml` before claiming fulfillment.
