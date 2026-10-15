# SuSLik Synthetic Separation Logic — GigWerk Reuse Assessment

**Scope.** Exactly one project is assessed: [TyGuS/suslik](https://github.com/tygus/suslik), the canonical SuSLik implementation. This report distinguishes specification-to-program deductive synthesis from examples-only induction, theorem checking alone, LLM coding, and HSWIP-style language bindings.

## Executive assessment

SuSLik is a real **contract/specification-to-code synthesizer**. It accepts Separation Logic specifications plus inductive heap predicates and searches derivations in Synthetic Separation Logic (SSL), emitting a minimal C-like imperative procedure. It is not example induction, an LLM coding system, or merely a theorem prover: the SSL rules construct the program while simultaneously establishing the proof obligations. The original system synthesizes possibly recursive but loop-free heap programs; the repository also contains the cyclic-synthesis extensions for auxiliary recursion/mutual recursion.

It is a strong conceptual fit for GigWerk's model-free deterministic actor: the contract can drive deterministic proof/search-based construction, with no model call. It is **not a drop-in Prolog or OCaml component**. The implementation is Scala/JVM, the input language is SuSLik's custom SSL syntax rather than Prolog, and the output is SuSLik's C-like AST/text (optionally certificates for Coq HTT/VST/Iris). A GigWerk integration would need a parser/contract bridge, process or library boundary, output lowering, runtime/Android strategy, and likely a new target language/backend. It should not be advertised as arbitrary-code synthesis or general ADT synthesis.

## Identity and provenance

- **Project:** SuSLik / Synthetic Separation Logic.
- **Canonical repository:** https://github.com/tygus/suslik
- **Primary paper:** Polikarpova and Sergey, *Structuring the Synthesis of Heap-Manipulating Programs*, POPL 2019; official preprint: https://ilyasergey.net/papers/suslik-preprint.pdf
- **Cyclic extension:** Itzhaky et al., *Cyclic Program Synthesis*, PLDI 2021: https://dl.acm.org/doi/10.1145/3453483.3454087
- **Certification paper/docs:** Watanabe et al., *Certifying the Synthesis of Heap-Manipulating Programs*, repository docs: https://raw.githubusercontent.com/tygus/suslik/master/certification.md
- **Evidence inspected:** repository README, LICENSE, build.sbt, SSLParser.scala, Synthesis.scala, examples/listcopy.syn, certification.md, and a shallow public clone. No code was modified and no synthesis/build/test was executed.

## Structured facts

| Field | Finding | Evidence/qualification |
|---|---|---|
| Input format | Custom SuSLik SSL syntax: `.def` files define `predicate` clauses; `.syn` files contain a Hoare-style pre/post specification (`{pure ; spatial}`), function signature, and optional expected result. The parser also supports `.sus` programs with holes. | README's `lseg` and `listcopy.syn` examples; `SSLParser.scala` parses types, assertions, points-to/block/predicate heaplets, inductive predicates, function specs, and statements. |
| Contract meaning | Separation Logic assertions over symbolic pure constraints and disjoint heaplets; inductive predicates encode recursive data-structure shapes. SSL transformation judgments decompose a contract into subcontracts while constructing commands. | POPL paper sections 1–2 and soundness theorem. |
| Actual output | A synthesized procedure in a minimal C-like imperative language: `let` loads, stores, `malloc`, `free`, calls, `if/else`, sequencing, and (for supported synthesis) recursive calls. Output is not OCaml, Prolog, Java/Kotlin, or Android bytecode. | README `listcopy` output; `language/Statements.scala`; paper abstract. |
| Implementation language | Scala 2.12/JVM; sbt assembly produces `suslik.jar`; source package is `org.tygus.suslik`. | `build.sbt` and repository source tree. |
| License | BSD 2-Clause (copyright TyGuS Project; “All rights reserved” plus redistribution conditions). | `LICENSE`, README badge. |
| Maintenance/latest revision | Public GitHub page reports 1,308 commits. Inspected shallow clone's latest commit is `2ac760860b450d3a0a68181ff81c242d0fdc93b2`, dated 2022-04-22, subject `Update LICENSE`. This is evidence of repository history, not a claim of active current maintenance. | GitHub page and local `git log -1`; no stronger activity claim made. |
| Model calls | No LLM/model call is part of the synthesis architecture. Search is deterministic/backtracking over SSL rules, with memoization and configurable DFS/BFS/cost search. Pure sub-synthesis may delegate to CVC4 (optional; source says enumeration fallback). Z3/CVC4/Cyclist are solver/prover dependencies, not generative language models. | POPL paper; README options; `Synthesis.scala` warnings; source references to CVC4 and Cyclist. |
| Correctness | SSL soundness theorem: a derived program is valid for its spec, including safe reads/writes/deallocation, under the stated well-formedness and recursive-call assumptions. Termination theorem applies when specs use well-founded predicates. | POPL paper Theorems 3.3 and 3.4. |
| Search/termination limits | It is not complete for arbitrary contracts. Search is backtracking and can fail or time out; CLI default timeout is 300,000 ms. Limits include max open/close/call depth, guard conjuncts, and configurable search strategy. The repository warns that if the cyclic proof checker is unavailable, termination checks are treated as true and are **not sound**. | README CLI; `Synthesis.scala`; paper search algorithm/limitations. |
| Certification | Optional certificate generation targets Coq HTT, VST, and Iris. Certification docs say pure lemmas may be `Admitted` by default for HTT unless CoqHammer/manual proofs are used; advanced benchmarks may need manual proof editing. | `certification.md`; do not equate synthesis soundness with every generated certificate being fully machine-closed. |

## What it can synthesize

**Supported well:** pointer/heap-manipulating transformations described by symbolic heaps and inductive predicates: linked-list/tree copying, append, free, flattening, rotations, allocation/deallocation, reads/writes, conditionals, and calls. The repository contains benchmark groups for lists, doubly linked lists, AVL/BST/red-black/rose trees, packed structures, and integer examples. The original paper reports structural recursion without sketches; the cyclic extension reports auxiliary recursive procedures and mutual recursion beyond the earlier tool's reach.

**State/heap:** yes, explicitly. Points-to cells, offsets/blocks, separating conjunction, allocation/free, and recursive heap predicates are core concepts.

**Recursion:** yes, subject to the SSL well-foundedness/reduced-subheap discipline; the cyclic extension adds systematic auxiliary recursion and mutual recursion. The original output is described as possibly recursive but loop-free.

**Algebraic data types:** no evidence that SuSLik has native ML/Haskell-style algebraic data types or arbitrary inductive values. Its “inductive” mechanism is Separation Logic inductive predicates describing heap layouts. GigWerk ADTs would need encoding as tagged heap records/predicates or a new front end.

**Broader than numeric examples:** yes for the demonstrated domain—heap/data-structure programs—not arbitrary general-purpose code. The contract language does include `int`, `bool`, `loc`, sets, intervals, arithmetic/Boolean/set expressions, but the implementation domain and examples are pointer/heap transformations.

## Fit for GigWerk

### Prolog/OCaml fit

- **Prolog preferred:** Conceptually compatible with a Prolog-like contract discipline (predicates, clauses, unification-style symbolic reasoning), but the actual accepted syntax is not Prolog and there is no Prolog front end in the canonical project.
- **OCaml actor:** Possible as an external deterministic actor: OCaml can emit `.def`/`.syn`, invoke the JVM executable, collect output/certificate, and apply policy checks. Alternatively, a substantial reimplementation/port of the parser, SSL rules, search state, SMT integration, and certificate emitters would be required.
- **No model needed:** The core path is symbolic proof/search. CVC4 is optional for pure synthesis; absence falls back to enumeration, with higher cost. Z3 and Cyclist are external solver/prover dependencies.

### Integration potential

1. Define a GigWerk contract subset that maps to SuSLik symbolic heaps and inductive predicates.
2. Generate `.def` predicate libraries and `.syn` goal specs from OCaml/Prolog-side contracts.
3. Run `./suslik` as a deterministic worker with a hard timeout and explicit solver configuration.
4. Parse the emitted C-like program or certification artifact into a constrained GigWerk backend.
5. For Android later, lower only a validated supported subset to C/NDK or Kotlin/Java/Compose-adjacent generated code; SuSLik itself does not package Android applications.

### Missing glue / risks

- No native OCaml or Prolog API; JVM/Scala process or port required.
- No direct Android/Kotlin/Java backend.
- No general arbitrary-code contract language; heap-oriented SSL is the actual boundary.
- No native ADT semantics beyond heap encodings.
- Need deterministic reproducibility policy around search order, solver versions, timeouts, and generated-code normalization.
- Need reject/handle synthesis failure and timeout as first-class actor outcomes.
- Need keep the cyclic proof checker configured; the source explicitly says treating missing termination checks as true is unsound.
- Certification can contain admitted pure lemmas under documented defaults and advanced cases can require manual proof work.
- This report does not claim local build or synthesis execution; dependencies were intentionally not installed.

## Small documented demo commands (not executed)

From a checked-out repository root, after installing the README's dependencies (JDK 8, sbt >=1.1.6, Scala >=2.12.6, Z3 >=4.8.9, CVC4 1.7, and Cyclist):

```sh
# Build the standalone JVM artifact
sbt assembly

# Synthesize the documented linked-list-copy example
./suslik examples/listcopy.syn

# Run a documented benchmark example
./suslik src/test/resources/synthesis/all-benchmarks/sll/append.syn

# Run the repository test suite (documented; not run for this report)
sbt test

# Optional documented certificate generation (HTT example)
./suslik examples/listfree.syn --assert false --certTarget htt --certDest .
```

The README's documented `listcopy` output includes load, conditional, recursive call, allocation, and stores. The `--timeout`, `--maxOpenDepth`, `--maxCloseDepth`, `--maxCallDepth`, `--dfs`/`--bfs`, `--delegate`, and `--certTarget` options expose practical search and integration controls.

## Bottom line

SuSLik is reusable as a **model-free, contract-directed deterministic synthesis worker** for a bounded but meaningful class of heap/data-structure programs. It is materially closer to GigWerk's desired actor than examples-only induction, theorem checking, LLM coding, or HSWIP. The honest reuse posture is an adapter/protocol boundary around the existing Scala/JVM executable, with a deliberately restricted SSL contract subset and an explicit lowering/certification pipeline—not a claim that SuSLik can synthesize arbitrary OCaml/Prolog/Android code.
