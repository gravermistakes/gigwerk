# Synquid refinement-type program synthesis — GigWerk reuse assessment

**Scope.** Exactly one project was researched: **Synquid**, the canonical implementation of *Program Synthesis from Polymorphic Refinement Types*. Evidence was taken from the canonical public GitHub repository, its raw source/build files, GitHub API metadata/tree, and the authors’ ACM/arXiv paper. No GigWerk files were modified; no heavy dependencies were installed; the repository was cloned read-only and source was inspected, not built or executed.

## Identity and evidence

- **Canonical repository:** [github.com/nadia-polikarpova/synquid](https://github.com/nadia-polikarpova/synquid)
- **Repository README:** [README.md](https://github.com/nadia-polikarpova/synquid/blob/master/README.md)
- **Official paper:** [ACM PLDI’16 DOI](https://dl.acm.org/doi/10.1145/2908080.2908093); open author version [arXiv:1510.08419](https://arxiv.org/abs/1510.08419), revised 21 Apr 2016, with [PDF](https://arxiv.org/pdf/1510.08419)
- **Repository metadata:** [GitHub API](https://api.github.com/repos/nadia-polikarpova/synquid)
- **Repository tree/revision:** [master tree](https://api.github.com/repos/nadia-polikarpova/synquid/git/trees/master?recursive=1), observed HEAD `9bceb4cc775e07ab279fff8c51fdd86ae0b2878c` (commit date 2022-04-05; “Update README.md”). GitHub metadata currently reports `pushed_at` 2022-04-06, `archived: false`, one open issue, and `updated_at` 2026-09-28. The latter is metadata activity, not evidence of active source maintenance; the latest source push observed is 2022.
- **Implementation/build evidence:** [Synquid.hs](https://raw.githubusercontent.com/nadia-polikarpova/synquid/master/src/Synquid.hs), [Parser.hs](https://raw.githubusercontent.com/nadia-polikarpova/synquid/master/src/Synquid/Parser.hs), [Synthesizer.hs](https://raw.githubusercontent.com/nadia-polikarpova/synquid/master/src/Synquid/Synthesizer.hs), [synquid.cabal](https://raw.githubusercontent.com/nadia-polikarpova/synquid/master/synquid.cabal), [stack.yaml](https://raw.githubusercontent.com/nadia-polikarpova/synquid/master/stack.yaml), [demo benchmark](https://github.com/nadia-polikarpova/synquid/blob/master/test/demo/List-Replicate.sq).

## Direct answers

| Field | Finding |
|---|---|
| **Input language** | Synquid’s own `.sq` DSL: top-level type signatures/refinement types, synthesis goals, algebraic `data` declarations, measures (including `termination measure`), predicates, qualifiers, mutual declarations, inline formulas, and optional library files. Refinements use Boolean/integer/set formulas, dependent function binders, polymorphism, predicates, and datatype measures. A goal can be a complete type signature with an implementation hole (`??`) or an omitted implementation. This is a contract/specification language, not input-output-example induction. |
| **Actual output** | A synthesized **pure functional program** in Synquid’s functional language, printed as plain/ANSI/HTML; `-o` writes generated **Haskell** and `-m` selects the Haskell module name. The README’s `replicate` example is generated recursively from a refinement type. Output is not Prolog, OCaml, Android bytecode, or a general arbitrary-language AST. |
| **Implementation language** | **Haskell** (GitHub language metadata; `src/*.hs`). Uses Z3 through the Haskell binding/module and a Horn/least-fixpoint solver; `stack.yaml` pins resolver `lts-15.3` and extra dependency `z3-4.3.1`. The README instead asks users to install Z3 4.7.1, so dependency instructions are historically inconsistent. |
| **License** | **MIT**, explicitly in `synquid.cabal`, and GitHub API reports SPDX `MIT`; repository contains `LICENSE`. |
| **Model calls** | **None required or used.** It is deterministic symbolic synthesis: bidirectional type-directed exploration plus liquid/refinement checking, qualifier generation, Z3/Horn solving. No LLM/model inference API appears in the inspected design/build/source evidence. |
| **Maintenance** | Public, not archived, 153 stars/16 forks in the observed API response; latest source push/HEAD is April 2022. The 2022 README news item announces a Docker image. Treat it as research software with stale toolchain assumptions, not an actively maintained production library. |

## Is this actual contract-to-code synthesis?

**Yes, within a deliberately bounded pure-functional synthesis domain.** The paper states that Synquid synthesizes recursive functions that *provably satisfy a specification in the form of a polymorphic refinement type*. The repository README gives the same contract-to-code behavior: `replicate :: n:Nat -> x:a -> {List a | len _v = n}` is the specification and Synquid generates a recursive implementation. This is materially different from examples-only induction, theorem checking without code generation, LLM coding, or HSWIP (which is only a Haskell/SWI-Prolog binding).

The paper explicitly contrasts Synquid with example-based systems: examples generally do not fully specify a program and require manual verification; refinement types can state abstract properties such as sorted-list/tree behavior. The paper reports sorting algorithms and balanced-search-tree operations, not merely numeric toy examples.

## Supported structures and boundaries

- **Recursion:** first-class target. The CLI exposes termination strategy controls (`--fix`/fixpoint strategy), and the paper’s central claim is recursive-function synthesis. `termination measure` declarations are part of the parser; default synthesis derives a termination metric from arguments.
- **Algebraic data types:** supported. The parser accepts `data ... where` declarations and constructor signatures; repository benchmarks include lists, trees, AVL trees, red-black trees, binary heaps, address books, and ASTs. Refinement predicates/measures can describe these structures.
- **Higher-order/polymorphic functions:** supported by the parser/type representation and benchmark suite (e.g., fold/map-style examples and polymorphic refinement types).
- **State/heap/effects:** **not evidenced as supported; treat as unsupported for GigWerk.** The implementation language and paper target pure recursive functional programs. The paper’s comparison explicitly characterizes heap-based tools separately and notes its own evaluation is side-effect free. No heap/store/assignment/reference/effect construct was found in the parser or listed program representation. Do not present Synquid as an imperative/stateful actor synthesizer.
- **Broader than numeric examples:** yes for pure data-structure algorithms and AST transformations; no evidence for arbitrary Android/GUI/network/concurrent/native code.

## Correctness guarantees, termination, and search limits

The guarantee is conditional: if Synquid returns a program, its refinement-type checking establishes that the program satisfies the supplied type/refinement contract (subject to the soundness assumptions of its checker, Z3, and solver implementation). The paper’s abstract says “provably satisfy,” and the source pipeline resolves declarations, synthesizes, then type-checks/reconstructs a typed program.

This is **not completeness for arbitrary contracts**. Search is bounded and tunable. `Synquid.hs` exposes defaults including application depth 3, scrutinee depth 1, match depth 2, auxiliary-function depth 1; it also exposes partial/best-effort solutions, memoization, symmetry reduction, solver strategy, and logging. The paper’s evaluation reports a two-minute timeout for benchmark settings. Therefore “no result” can mean the contract is outside the supported logic, the component library is insufficient, or the bounded search/solver timed out; it is not a proof of impossibility.

Termination is supported for recursive synthesis through fixpoint/termination-metric machinery and explicit termination measures, but this is a functional termination discipline—not a general proof of Android actor liveness, resource bounds, responsiveness, or absence of effects.

## Prolog/OCaml fit for GigWerk

- **Contract fit:** strong if GigWerk can express actor behavior as pure functional contracts over algebraic state snapshots, lists/trees, integer/Boolean/set refinements, measures, and explicit termination metrics. Synquid is genuinely contract-to-code rather than example induction.
- **OCaml fit:** moderate at the algorithmic level, weak as a drop-in. Synquid emits Haskell, not OCaml. A backend or translation layer would be required; generated code relies on Synquid’s runtime/type conventions and supplied component libraries.
- **Prolog fit:** weak-to-moderate as a contract front end only. Synquid does not parse Prolog and its refinement logic is not general Horn-clause Prolog. A translator from a restricted Prolog contract/predicate subset into `.sq` data declarations, measures, predicates, qualifiers, and refinements would be required; translating generated functional code back into deterministic Prolog would be a separate backend problem.
- **Model-free deterministic actor:** good conceptual fit for the synthesis engine itself: no model calls, explicit symbolic search, deterministic given configuration/environment. But Synquid does not itself provide an actor runtime, event loop, policy/state machine, Android integration, or effectful execution layer.

## Missing glue for GigWerk

1. Define a **restricted GigWerk contract subset** that maps soundly to Synquid’s refinement logic; decide how state is represented immutably.
2. Build a Prolog-to-Synquid contract compiler (if Prolog remains the authoring language), including ADTs, measures, predicates, qualifiers, and termination measures; reject unsupported effects/negation/meta-calls explicitly.
3. Build a Synquid-to-OCaml backend or a verified/checked Haskell-to-OCaml bridge. The stock `-o` output is Haskell only.
4. Supply a component/library model for actor operations. Synquid synthesizes from available symbols/components; it does not invent arbitrary APIs or discover Android SDK behavior.
5. Add an effect/state boundary: generated pure transition functions plus a separately audited OCaml runtime adapter for I/O, concurrency, persistence, and Android lifecycle.
6. Add resource/search governance (depth/time limits, reproducible solver version, failure taxonomy, artifact hashes) and a second checker in the target toolchain.
7. Package only after target-language semantics and Android API interactions are independently tested; this report does **not** claim Android compatibility or verified local execution.

## Small documented demo commands

From the repository README:

```bash
git clone https://github.com/nadia-polikarpova/synquid.git
cd synquid
stack setup
stack build
stack exec -- synquid [args]
```

A concrete repository benchmark is `test/demo/List-Replicate.sq`; a representative direct invocation after building is:

```bash
stack exec -- synquid test/demo/List-Replicate.sq
```

The CLI source documents output generation and bounds, for example:

```bash
stack exec -- synquid test/demo/List-Replicate.sq -o generated.hs -m Generated
stack exec -- synquid test/demo/List-Replicate.sq --print-stats
```

These commands are documented/derived from the README and `Synquid.hs`; they were **not executed in this research task**. The repository’s README requests Z3 4.7.1 while `stack.yaml` lists Haskell package `z3-4.3.1`; resolve that version mismatch before attempting a build.

## Test/build status

**Source inspection completed; local execution not claimed.** The public tree contains extensive `test/checking`, `test/current`, `test/demo`, `test/job-talk`, `test/unfinished`, and `test/unit` `.sq` suites plus oracle files. The clone and metadata/source inspection succeeded, but Synquid was not built and tests were not run, in accordance with the request not to install heavy dependencies and not to claim verified local execution.

## Bottom line

Synquid is a credible reusable **model-free, deterministic, refinement-contract-to-pure-functional-code synthesizer** for recursive, polymorphic, algebraic-data algorithms. It is substantially broader than numeric examples and is not a mere checker or LLM wrapper. It is **not** a ready-made GigWerk actor generator: Prolog/OCaml contracts, mutable/effectful state, Android APIs, runtime orchestration, target-language emission, and production resource guarantees all require new glue and careful semantic validation.
