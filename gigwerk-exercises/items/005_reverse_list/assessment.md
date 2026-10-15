# Assessment — 005 Reverse a List

## Status

| Field | Value |
|---|---|
| Contract status | **ready** |
| Specification strength | **full** |
| Synthesis status | **rejected** — no candidate emitted |
| Aggregate synthesis time | **2.296 seconds** across two externally limited attempts |
| OCaml candidate tested | No; none was emitted |

## Contract strength

`contract.sq` defines `reverseSpec` as a logical, algebraic-datatype-valued measure. The required result refinement is exact equality to that measure. It therefore specifies the entire output sequence:

- `[]` reverses to `[]`;
- input order is reversed exactly;
- duplicates are retained at their reversed positions; and
- the function is polymorphic, with no operation on element values.

This is intentionally stronger than the common but inadequate combination of equal length and equal element set. It does not admit reordering, deduplication, identity, or a permutation other than reversal.

The only executable definitions in the contract are `??` synthesis holes (`snoc` and `rev`). The logical measures are not target implementation components. No `List.rev`, `List.append`, `List.length`, or preimplemented helper is trusted.

## Synthesis evidence

Pinned runtime: Synquid `v0.4, 2016-08-11`, invoked through the requested `proot` rootfs command with `--output=Plain --print-stats` and a 60-second external timeout per attempt.

| Attempt | Exact specification variant | Exit | Elapsed | Result |
|---|---|---:|---:|---|
| 1 | `cat` plus `reverseSpec` | 1 | 0.966 s | Rejected during exploration of the `append` goal |
| 2 | `snocSpec` plus `reverseSpec` | 1 | 1.330 s | Rejected during exploration of the `snoc` goal |

Both variants retained exact sequence semantics. The final retained `contract.sq` is attempt 2. The runtime printed the entry goal, then exited on a type-shape mismatch while exploring a speculative `match Cons Nil ...` term. Captured stdout, stderr, exit code, command, and time are in `synthesis.out`, `synthesis.err`, and `synthesis.meta`; attempt-one counterparts are also retained.

No timeout occurred, and no candidate was produced. No partial mode, nontermination mode, disabled check, or manual translation was used.

## Independent OCaml tests

`test_generated.ml` opens `Generated` and requires only:

```ocaml
val rev : 'a list -> 'a list
```

It includes the official string example, empty and singleton cases, duplicate-sensitive exact-order cases, exhaustive values from `{-1, 0, 1}` through length five, an involution property sweep, and a polymorphism check using function identity.

It also contains the explicit **NEGATIVE CONTROL** that rejects identity behavior for `[1; 2; 3]`. Before synthesis, the suite was compiled against a separately labelled `failwith "unsynthesized"` stub. It exited `1` with the expected eight semantic assertion failures, establishing that the harness fails rather than silently accepting a missing entrypoint. This stub is not part of the deliverable implementation surface.

> A future Synquid output is only a candidate. It must still be mechanically lowered to OCaml and pass `test_generated.ml` before any claim of fulfillment.

## Scope and caveats

The upstream source was fetched read-only from the pinned commit. Its exact `## Solution` section was removed before source inspection; no solution body was read, used, or reproduced. The upstream statement is concise, so the full sequence/multiplicity semantics are stated explicitly here rather than weakened to set or length behavior.

This item has no options, failure behavior, mutation, effects, randomness, floats, strings-specific rule, or infinite/coinductive-stream requirement. It is a finite immutable list transformation only. No Android build is asserted.
