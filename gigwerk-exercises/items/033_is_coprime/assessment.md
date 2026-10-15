# Assessment — Exercise 033

## Status

| Field | Value |
|---|---|
| Contract status | **requires_features** |
| Specification strength | **full** |
| Synthesis status | **not attempted** |
| Actual synthesis elapsed time | **0 seconds** |

## Required behavior

`Generated.coprime : int -> int -> bool` must decide, for `a > 0` and `b > 0`, whether the mathematical greatest common divisor of `a` and `b` is exactly `1`.

The requirement is an **if-and-only-if relation over the complete positive-input domain**. The two official examples are retained in `test_generated.ml`, but they are not the entire contract.

The upstream source does not define zero or negative-input behavior. Those values are intentionally excluded from both the semantic obligations and tests rather than receiving an invented exception, option, or Boolean convention.

## Why no `contract.sq` was emitted

The supplied pinned Synquid source was inspected before deciding syntax or attempting synthesis:

- `src/Synquid/Logic.hs` lists integer `*`, `+`, `-`, comparisons, and Boolean/set operators. It does **not** define integer division or remainder.
- `src/Synquid/Tokens.hs` exposes no `div` or `mod` refinement token.
- The logic has universal formulas internally, but the exposed formula grammar has no existential-quantifier syntax.

An exact definition of `gcd(a,b) = 1` needs a sound way to state the absence of any positive common divisor other than `1`, or a verified built-in GCD relation. An opaque `gcd` component would not establish that relationship; it would merely rename the missing semantics. A bounded collection of concrete cases would also be an unsound weakening.

Accordingly, this item requires either:

1. a checked built-in predicate such as `gcd_eq_one a b`, linked to integer semantics; or
2. integer divisibility in refinements plus the quantified reasoning needed to characterize common divisors (or an equivalently verified GCD primitive).

No `contract.sq` is present by design. No solver was invoked, so there are no `synthesis.out` or `synthesis.err` artifacts and the elapsed time is `0`.

## Tests retained independently of synthesis

`test_generated.ml` uses only the OCaml standard library, opens `Generated`, and includes:

- both official examples;
- unit boundaries;
- representative coprime and non-coprime cases;
- an exhaustive `1..64 × 1..64` positive grid checked against a test-only Euclidean oracle; and
- a symmetry check.

The oracle is isolated in the test file, is not a Synquid input, and is not an implementation artifact for the actor.

`negative_control_generated.ml` is explicitly and deliberately wrong: it reports `true` for all pairs. It exists solely to demonstrate that the independent test suite rejects an incorrect candidate. The observed compilation/run evidence is recorded in `negative_control_result.md`.

## Provenance and quarantine

See `problem.md` for the pinned repository, commit, blob, source URL, and redaction procedure. The single upstream `Solution` section was removed before inspection; no body from it appears in this item.
