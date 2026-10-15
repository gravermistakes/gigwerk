# Myth: type-and-example-directed functional program synthesis

**Research scope.** Exactly one project is covered: the original **MYTH** prototype by Peter-Michael Osera and Steve Zdancewic. This report distinguishes it from Smyth (a later system built on an augmented Myth algorithm), theorem checking, LLM coding, and library wrappers. Evidence was taken from the official paper, the canonical public repository identified by the paper/search trail, and the official Smyth documentation only where it explicitly explains Myth's boundary.

## Identity and canonical sources

- **Project:** Myth (also styled MYTH; repository README: “Myth: ML Synthesizer”)
- **Canonical repository:** [silky/myth](https://github.com/silky/myth) (the repository found for the original prototype; default branch `master`)
- **Official paper:** [Type-and-Example-Directed Program Synthesis](https://www.cis.upenn.edu/~stevez/papers/OZ15.pdf), Peter-Michael Osera and Steve Zdancewic, PLDI 2015 preprint.
- **Official explanatory documentation:** [Smyth documentation, “Smyth vs. Myth”](https://uchicago-pl.github.io/smyth/), used only for its explicit description of the original Myth algorithm and its trace-complete-example requirement.
- **Not the project:** [UChicago-PL/smyth](https://github.com/UChicago-PL/smyth) is a later, different tool. Its documentation says Smyth feeds constraints to an augmented Myth algorithm; it should not be presented as the original Myth repository.

## Executive finding for GigWerk

Myth is genuine **contract-to-code synthesis**, but its contract is a typed functional synthesis goal plus concrete input/output examples—not Prolog, not a general logical contract language, and not a theorem prover that accepts arbitrary properties. It synthesizes a first satisfying program by proof/type-directed search and example-guided pruning, with no model calls. It is an unusually good conceptual match for a **deterministic, model-free actor** if GigWerk can accept a small, pure, algebraic-data functional DSL and a bounded search procedure. It is not an out-of-the-box OCaml actor framework, Android compiler, arbitrary-code synthesizer, or reusable Prolog engine.

The original prototype targets a subset of OCaml syntax, is itself implemented in OCaml, and emits OCaml-like source. Its strongest demonstrated structures are algebraic datatypes, pattern matching, recursion, and higher-order functions. It does not provide a heap/state/effects model; the paper explicitly calls the supported subset “purely functional” and reports missing products, polymorphic types, primitive `int`/`string`, and richer features. Any GigWerk integration therefore needs a contract adapter, input/example compiler, process/API boundary, output parser/validator, resource limits, and a later OCaml-to-Android packaging path.

## Structured facts

| Field | Finding | Evidence / caveat |
|---|---|---|
| **Exact input format** | A source file containing algebraic datatype declarations; optional top-level definitions/auxiliary functions; a typed synthesis goal; and a finite set of input→output examples after `|> { ... }`, with `= ?`. Example: `let list_stutter : list -> list |> { [] => [] \| [0] => [0;0] \| [1;0] => [1;1;0;0] } = ?` | Paper Fig. 1 and repository `tests/pldi-2015-benchmarks/list_stutter.ml`. The paper says inputs include a type signature, needed auxiliary functions, and a synthesis goal. |
| **Contract semantics** | Types constrain well-typed terms; examples are evaluated during enumeration and pruned through refinement trees. Recursive examples must be **trace-complete** in the original system: recursive calls needed to evaluate an asserted call must also have asserted examples. | Paper §4/§5.3; official Smyth docs explicitly define Myth's trace-complete requirement. |
| **Output format** | Generated OCaml-subset expression/function, printed as source. Typical result is a `let` binding containing `let rec`, `match`, constructors, and calls. | Repository README's documented output for `list_stutter`; paper Fig. 1. |
| **Implementation language** | OCaml. | Paper §5: “implemented a prototype tool, MYTH, in OCaml”; repository source is `.ml/.mly/.mll` and README requires OCaml > 4.01.0. |
| **Model calls** | None required, optional, or implied. The algorithm is proof/type-directed enumeration plus an interpreter; no LLM, neural model, SMT service, or remote model is part of the documented prototype. | Paper abstract and algorithm sections; repository source/build metadata. “Model-free” here means no learned/remote model, not that the search is cost-free. |
| **License** | **No explicit SPDX license was found in the canonical repository metadata or top-level tree inspected.** Do not assume MIT/BSD/GPL. The paper has normal publication copyright language. Obtain author permission or confirm licensing before embedding or redistributing. | GitHub API metadata returned no license object; clone had no `LICENSE`/`COPYING` file at the inspected revision. This is a legal/reuse caveat, not a claim that reuse is prohibited. |
| **Maintenance/latest revision evidence** | Repository metadata: 6 commits; latest inspected commit `b631edefb2a27a1d731daa6654517d91ca660b95`, dated `2019-06-30T10:23:12+10:00`, merge “update-to-4.07.1”. Repository was created 2015-06-18. | GitHub repository/API and local shallow clone. This is an old research prototype, not evidence of active maintenance or current compiler compatibility. |
| **Supported structures** | Recursive pure functions; algebraic datatypes; constructors; pattern matching; `let`/`let rec`; functions/lambdas; higher-order functions and higher-order recursive functions; examples cover booleans, naturals, lists, trees, and richer inductive encodings. | Paper abstract, Fig. 1, §5.2, and repository grammar/source/tests. |
| **Recursion** | Supported, with a structural-recursion check and positivity restriction intended to ensure terminating evaluation for generated programs. | Paper §3.4 and §5.2. This is not a blanket proof of termination for arbitrary OCaml or arbitrary external helpers. |
| **ADTs** | Core strength. User declares constructors; synthesis exploits type structure and match refinement. | Paper abstract and benchmark discussion. |
| **State/heap/effects** | Not supported as a first-class target in the documented design. It is purely functional and has no documented references, mutable heap, arrays, I/O, exceptions, or Android/runtime effects model. | Positive evidence is the paper’s “purely functional” scope and its limitations section; absence claims are bounded to inspected docs/source. |
| **Correctness guarantee** | Search returns a term satisfying the supplied typed goal/examples when it returns a result under the implemented semantics; the paper presents a formal calculus and soundness-oriented proof-search development. Benchmarks were manually verified by the authors for all inputs, but Myth is not a general verifier for arbitrary postconditions. | Paper §4–§5.3. Do not advertise full functional correctness from finite examples. |
| **Search/termination limits** | Iterative deepening over match depth, match scrutinee size, and guessed-expression size. Default implementation alternates guess rounds (0.25-second saturation timeout) with match/scrutinee growth. Search can explode; the paper calls some programs difficult or impossible with available resources. | Paper §5.1 and §5.3; `src/synth.ml` defines the standard plan and `src/synml.ml` exposes `-matches` and `-scrutinees`. |
| **Examples-only vs contract synthesis** | Not examples-only induction: the type is an active proof/search constraint and auxiliary typed context is used. But examples remain essential in original Myth; it does not accept arbitrary logical specifications in Prolog or theorem-prover notation. | Paper abstract/introduction and §6 comparison to type-only Djinn and solver/property systems. |
| **Library wrapper status** | Not HSWIP or another language binding: Myth contains a parser, typechecker/evaluator, refinement-tree/search code, and source printer. | Repository file tree: `parser.mly`, `tc.ml`, `eval.ml`, `rtree.ml`, `synth.ml`, `pp.ml`, `synml.ml`. |

## What the paper actually claims

The paper’s abstract says the algorithm synthesizes **recursive functions that process algebraic datatypes**, using proof-theoretic techniques that combine type information and input/output examples, with refinement trees to represent code-shape constraints. It reports more than 40 benchmarks and larger examples.

The paper’s concrete `stutter` example demonstrates real synthesis rather than checking: the input has a type and examples, and the output is a recursive function that duplicates every list element. The benchmark description includes non-recursive functions, recursive functions such as list length, generation of higher-order recursive functions such as list fold/tree map, and use of higher-order functions such as list sum.

The paper also explicitly records important limits:

1. The prototype has **no built-in primitive datatypes** such as `int` or `string`; examples encode naturals and lists as user-defined ADTs.
2. It uses a simple, unoptimized interpreter for its supported OCaml subset.
3. It lacks richer types including **products and polymorphic types**.
4. It relies on top-level definitions in the context and cannot discover helper functions on its own.
5. The original recursive-example requirement is trace-completeness, which makes example authoring harder.
6. The search space can be exponentially large; larger contexts and nested matches can cause runtime explosions.

## Repository/source inspection

The canonical repository README documents:

```text
Requirements: Ocaml > 4.01.0
opam install core
opam install menhir
make
./synml.native tests/pldi-2015-benchmarks/list_stutter.ml
```

The documented output is an OCaml function with a recursive helper and pattern match. Repository layout includes `src/parser.mly`, `src/lexer.mll`, `src/tc.ml`, `src/eval.ml`, `src/rtree.ml`, `src/synth.ml`, `src/pp.ml`, `src/synml.ml`, and test directories `tests/pldi-2015-benchmarks`, `tests/pldi-2015-extended`, and `tests/pldi-2015-contexts`. Test files use `.ml` inputs and `.out` baseline outputs.

The parser grammar inspected in `src/parser.mly` accepts type arrows, user-defined base types, variables, lambdas, `let`/`let rec`, constructors, matches, list syntax, and pattern branches. This supports the output/structure claims above, but does not establish arbitrary OCaml compatibility.

`src/synth.ml` exposes the search plan: saturation of expression guesses, growing match depth, and growing match scrutinee size. `src/synml.ml` exposes controls including `-matches` and `-scrutinees`, and reports first-found synthesis/statistics modes. These are resource/search controls, not correctness proofs or complete search over arbitrary programs.

## Prolog/OCaml and formal-contract fit

### OCaml fit: strong but bounded

OCaml is the natural fit for the existing prototype: it already parses a small ML/OCaml-like language, performs typechecking/evaluation, searches, and emits OCaml-like code. GigWerk could orchestrate it as a deterministic subprocess or wrap its internal OCaml modules, subject to license clearance and modernization. A clean boundary would be:

1. GigWerk receives a typed contract plus examples in a GigWerk schema.
2. An OCaml adapter emits Myth source and trace-complete examples.
3. Myth searches under explicit time/size limits.
4. A parser validates the returned source against the expected output grammar/type.
5. GigWerk records input contract, search plan, output, and failure/timeout as an immutable actor result.

### Prolog fit: conceptually possible, not native

Prolog is **not** Myth’s input language or implementation language. A Prolog contract frontend would have to translate predicates/rules into a finite, typed ADT representation and example set, or replace Myth’s parser/search semantics. That translation is nontrivial for unification, open-world predicates, cuts, negation, arithmetic, nontermination, and relational/multi-directional behavior. The safe conclusion is: **Prolog is a potential external contract notation only after a deliberately restricted compilation to Myth’s typed functional DSL; it is not a drop-in backend.**

### Formal contract fit

Myth provides a typed synthesis goal plus finite observations and proof-search constraints—not arbitrary Hoare logic, temporal logic, dependent types, or Prolog clauses. Its type-directed calculus is a useful formal contract substrate for total-ish pure functions over declared ADTs. For stronger GigWerk contracts, add a post-synthesis checker (for example, a separate property checker or test harness) rather than claiming Myth verifies the property. Keep finite examples and any logical predicate visibly separate in the artifact schema.

## Integration potential and missing glue for GigWerk

**Reusable now:** the deterministic synthesis/search core; typed ADT declarations; pure recursive/higher-order function generation; source emission; documented benchmark corpus; explicit search knobs.

**Missing or requiring engineering:**

- license confirmation and dependency modernization;
- a stable library/API or JSON/Protobuf boundary (the repository is CLI/source-file oriented);
- a GigWerk contract schema and compiler to Myth syntax;
- trace-complete example generation or a policy to reject incomplete recursive traces;
- output parser, typechecker, sandbox, and resource limits;
- structured failure reasons (no solution, timeout, search limit, parse/type error);
- stronger contract checking beyond finite examples;
- support for products, polymorphism, primitive runtime types, effects/state/heap if required;
- a reproducibility manifest recording revision, search plan, context, examples, and output hash;
- an OCaml-to-Android deployment path. Myth itself does not package Android artifacts.

For a first GigWerk vertical, use a small terminating ADT DSL (e.g., Nat/List/Tree), pure functions only, explicit examples, bounded search, and deterministic output selection. Avoid claiming arbitrary-code synthesis or Android readiness until a separate toolchain is validated.

## Documented demo commands (not executed in this report)

The repository README documents this minimal command sequence:

```bash
opam install core
opam install menhir
make
./synml.native tests/pldi-2015-benchmarks/list_stutter.ml
```

The expected README example emits a `list_stutter` function. These commands are evidence from project documentation; this research did **not** execute the build or generated code, and therefore does not claim local build success, current OCaml compatibility, or runtime verification.

## Verification status and evidence boundary

This report performed public source/document inspection and GitHub metadata inspection. It did not modify GigWerk, push changes, install heavy dependencies, run unsafe code, build Myth, or execute synthesized output. “Correctness” statements are limited to what the paper formally describes and what the documented benchmark protocol reports. The project’s old revision, absent explicit license, unverified modern build, and finite-example semantics are material caveats.

## Evidence URLs

1. https://github.com/silky/myth
2. https://www.cis.upenn.edu/~stevez/papers/OZ15.pdf
3. https://uchicago-pl.github.io/smyth/
4. https://github.com/UChicago-PL/smyth (distinguishing later Smyth project; not evaluated as the selected project)
