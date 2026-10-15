# Assessment — Exercise 013

## Status

| Field | Value |
|---|---|
| Contract status | **ready** — full declarative contract written; corrected version was not run because the two-attempt budget was exhausted |
| Contract strength | **full** |
| Synquid status | **runtime error** — no candidate was produced |
| Actual Synquid elapsed time | **0.043 seconds** over two bounded attempts |
| Entrypoint | `encode : 'a list -> 'a rle list` |

## Full contract design

`contract.sq` does **not** use the bundled weak size/set run-length contract. It declares a contract-only `RList` representation for a canonical list of `RLE` nodes, then specifies:

> `decodes rs xs` holds exactly when consuming `rs` expands one run cell at a time to the exact finite source sequence `xs`, in left-to-right order.

The `RList` constructor refinement forbids a tail starting with the representative value of its predecessor. `Many` is restricted to counts at least two. Together, those declarations require all of the following, rather than merely set or length equality:

1. finite input is partitioned into maximal nonempty consecutive equality-runs;
2. run order and multiplicity are preserved exactly;
3. singleton runs use `One`, and only counts `n >= 2` use `Many (n, x)`;
4. separated equal values are not merged; and
5. output is canonical — no `Many` with a count below two and no equal adjacent run representatives.

`RList` is a **contract IR only**. Mechanical lowering must map `RNil` to `[]` and `RCons` to normal list cons, yielding the exact public result type `'a rle list` recorded in `interface.json`.

The sole generic trusted component is `eq`, a polymorphic adjacent-equality primitive that must be supplied/modelled by the future backend and lowered consistently with its OCaml equality semantics. It is neither the exercise algorithm nor an implementation helper. The only target body in `contract.sq` is `encode = ??`.

## Synthesis evidence

The prescribed pinned command was used under `/usr/bin/timeout 60s`; no check was disabled and neither `--partial` nor `Nonterminating` was used.

| Attempt | Exit | Elapsed | Result |
|---|---:|---:|---|
| 1 | 1 | 0.021 s | Frontend parse error caused by unsupported nested constructor patterns in `rcount`. The contract was adjusted by splitting the count observations. |
| 2 | 1 | 0.022 s | Frontend resolution error in the generic empty case of `rhead` (`One 0` cannot inhabit `RLE a`). The contract was adjusted to use `rheadcount`. |

The second correction was **not run**: the authorized budget is at most two attempts. Consequently, there is no synthesized candidate, no compiled generated module, and no claim that the corrected file is accepted by the frontend. `synthesis.out`/`synthesis.err` preserve attempt 2; `synthesis_attempt1.out`/`synthesis_attempt1.err` preserve attempt 1.

## Tests

`test_generated.ml` is a standard-library-only OCaml test program that opens `Generated`. It contains no target implementation. Its independent reference oracle is isolated in the test file and is not a synthesis input.

Coverage includes the official example, empty and boundary cases, separated equal values, canonicality and round-trip properties, and exhaustive checks of all **364** lists over `{0; 1; 2}` with length at most five. The file includes a labelled negative control that rejects the incorrect behavior of merging separated runs.

### Red-phase evidence

The test compiled with **OCaml 4.14.1** against an explicitly labelled deliberately-wrong `Generated.encode` stub outside this item directory:

```text
compile exit: 0
runtime exit: 1
FAIL singleton is One: semantic result differs from expectation
```

This establishes that the independent suite rejects known-wrong semantics. It is not a successful test run of a synthesized candidate.

## Scope caveats

The official statement declares the `rle` type and calls `encode` but does not separately state an `encode` type annotation; the interface artifact records the uniquely inferred conventional signature. The source also does not formalize equality exceptions. A lowering using `Stdlib.( = )` inherits its behavior (for example, `nan <> nan`, and functional values can raise when compared) without changing the public signature.

No randomness, effects, mutable state, I/O, infinite streams, string operations, or float arithmetic are part of the problem. Strings and floats are ordinary polymorphic values, subject only to the selected equality primitive.
