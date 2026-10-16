# Assessment — 018 Extract a Slice From a List

## Status

| Field | Value |
|---|---|
| Contract | **ready** |
| Specification strength | **full** |
| Synquid result | **rejected** — no candidate produced |
| Actual synthesis time | **23.617242162 seconds** over two attempts |
| Required unsupported features | None |

## Exact contract

`slice xs i k` is specified only when `0 <= i <= k < len xs`.

The logical measure `segment i k (len xs) xs` examines every original list position. At a current suffix `current`, the original position of its head is `len xs - len current`; that head is retained exactly when it lies in the inclusive interval `[i, k]`. This makes the output an **exact sequence**, not merely a set or a length-constrained list:

- elements at positions `i` and `k` are present;
- order remains left-to-right;
- repeated values are retained once per selected input occurrence;
- output length is `k - i + 1`.

The source provides no invalid-index behavior. The contract and tests intentionally make no claim about it.

## Tests

`test_generated.ml` opens `Generated` and uses only the OCaml standard library. It includes:

1. the official string-list example;
2. first, last, singleton, and whole-list slices;
3. a duplicate-valued case to detect multiplicity loss;
4. exhaustive valid slices of all binary lists through length five;
5. an active **negative control** that expects `[2; 3; 4]` and rejects the reverse-order output `[4; 3; 2]`.

The reference oracle is test-only and isolated from Synquid inputs.

The suite was compiled with OCaml 4.14.1 against a separate, explicitly
labelled test-only wrong `Generated.slice` stub in the job scratch directory.
It exited `2` as required, with the semantic assertion:

```
negative control: reverse-order output must be rejected: expected 2;3;4 but got
```

That stub is not included as a candidate or exercise implementation.

## Synthesis evidence

The required invocation was used via the pinned proot runtime, with a 60-second external limit each time.

| Attempt | Exit | Elapsed | Finding |
|---|---:|---:|---|
| 1 | 1 | 0.020427304 s | The first form tried to vary measure constants recursively, which this Synquid resolver forbids. |
| 2 | 1 | 23.596814858 s | The repaired immutable-constant measure reached synthesis, but search tried `zero` for a required list and terminated without a candidate. |

The final `contract.sq` includes `dec` as an explicitly labelled generic primitive needed by conventional recursive lowering. It was added after the second diagnostic; the two-attempt cap forbids another synthesis run. `synthesis.out` and `synthesis.err` are the captured streams from attempt 2; `synthesis_attempt1.out` retains the first diagnostic. No `--partial`, nontermination option, check disablement, model call, or manually authored final OCaml implementation was used.

A future synthesized candidate remains only a candidate until the parent mechanically lowers it to OCaml and runs `test_generated.ml` successfully.
