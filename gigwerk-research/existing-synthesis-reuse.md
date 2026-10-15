# GigWerk: Reusing Existing Deterministic Contract-to-Code Synthesis

**Finding:** **Yes—several projects already construct code from machine-readable requirements without an LLM or prose-to-code step.** None is a drop-in GigWerk/OCaml/Android implementation. Synquid and SuSLik provide substantial formal-contract-to-program machinery; cvc5 supplies a maintained generic synthesis backend; Popper/Metagol construct Prolog programs from examples and explicit rules. These are different reusable pieces, not interchangeable general-purpose developers.

> **Evidence boundary:** the comparison began with source/paper/document inspection. Follow-up local validation ran cvc5 1.1.2 and two Metagol construction examples successfully; details appear at the end. No full project suite or Android deployment was tested. The proposed narrow validation route is not a replacement for the user's broader code-production goal or an approved final architecture.

## What already exists—and what it does not mean

A deterministic synthesizer **derives/constructs** a candidate from an explicit contract and a defined implementation grammar. A finite set of grammar rules can describe infinitely many programs; practical search still needs resource bounds. The contract may be logical constraints, Separation Logic, refinement types, or examples plus a hypothesis bias. Its correctness claim is bounded by that input language, solver/checker assumptions, and search/resource limits.

For GigWerk, this is a good match only if the desired actor is expressed formally: typed state, command, result, legal transitions, invariants, and a small allowed expression/statement grammar. It is **not** evidence that any tool can autonomously construct arbitrary booking workflows, Android integration, network calls, persistence, lifecycle code, or arbitrary OCaml from a broad requirement.

HSWIP remains useful as an embedding reference: it is a Haskell-to-SWI-Prolog wrapper, **not the missing synthesizer**.

## Compact comparison

| Project | Requirement form | Constructs | Evidence-led fit for GigWerk | Key boundary |
|---|---|---|---|---|
| **cvc5 SyGuS** | SMT constraints + typed grammar | Typed `define-fun`/terms | **Best first generic formal-contract worker** for small, pure transition functions | No OCaml/Prolog/Android emitter; state/effects must be encoded |
| **SuSLik** | Separation-Logic pre/postconditions + heap predicates | Minimal C-like heap procedures | **Best actual formal heap-contract engine** for tightly bounded allocation/mutation routines | JVM boundary; no OCaml/Android output; not arbitrary code |
| **Popper** | Positive/negative examples + Prolog BK + bias | Definite Prolog rules | **Best Prolog-centered relational learner** | Example-relative, not general postcondition proof or termination proof |
| **Myth** | Typed ADTs + finite I/O examples | OCaml-subset functions | **Closest existing OCaml output** for small pure functions | Unknown license; old/stale prototype; examples are not formal postconditions |
| **Synquid** | Polymorphic refinement types | Pure recursive programs, optional Haskell | Strong pure-contract research base | Haskell/Z3 toolchain; no OCaml/Android/effects backend |
| **Metagol** | Examples + metarules + background predicates | Prolog rules | Usable only as a bounded research prototype | Superseded/stale; contract is bias + examples, not general formal specs |

## Practical ranking: 1–3

### 1. cvc5 SyGuS — recommended primary foundation

**Why it ranks first:** cvc5 is the clearest generic match for “formal requirements, not prose.” Its SyGuS interface combines typed candidate grammars (`synth-fun`) with semantic logical constraints (`constraint`), then returns a satisfying function term if it can find one. The official example synthesizes max/min from constraints rather than a finite example list ([SyGuS function example](https://cvc5.github.io/docs/cvc5-1.0.7/examples/sygus-fun.html)); grammar is explicitly the typed search-space boundary ([grammar example](https://cvc5.github.io/docs/cvc5-1.0.7/examples/sygus-grammar.html)). The underlying project is active in the supplied evidence, but integration must pin an exact revision/options rather than rely on that fact ([repository](https://github.com/cvc5/cvc5)).

**Recommended GigWerk role:** derive a **pure, deterministic state-transition term**:

`transition : State × Command → Result × State`

Initially permit only ADTs/enums, bounded integers, `ite`/matches, tuples/records, and declared invariant predicates. Model booking, Android, databases, clocks, network, callbacks, and cancellation **outside** the synthesized function. The harness—not the synthesizer—performs I/O and passes explicit inputs/outputs.

**What can be reused exactly:** cvc5’s solver, SyGuS/SMT-LIB input contract, parser/API/CLI, and solver-level candidate check.

**What cannot be reused:** a Prolog frontend, OCaml emitter, state/effect semantics, target-language typechecking, runtime adapter, Android NDK/JNI/package support, resource/cancellation policy, or domain contract library. Build these as thin, auditable GigWerk-owned layers.

**Verification meaning:** a returned term satisfies the supplied SyGuS constraints under supported SMT theories and configured solver assumptions. It can return `unknown`, exhaust resources, or fail to find a candidate; it does **not** by itself establish termination, safety of lowered OCaml, or Android correctness ([cvc5 publication](https://doi.org/10.1007/978-3-030-99524-9_24)). Preserve the contract, grammar, exact solver revision/options, result term, and a replay check for every accepted output.

### 2. SuSLik — use only for bounded, heap-shaped kernels

**Why it ranks second:** SuSLik is the strongest evidence of a genuine formal **contract-to-imperative-code** engine. It searches Synthetic Separation Logic derivations from Separation Logic pre/postconditions and inductive heap predicates, emitting C-like procedures with loads, stores, allocation/deallocation, branches, and calls ([repository](https://github.com/tygus/suslik), [POPL paper](https://dl.acm.org/doi/10.1145/3453483.3454087)). This is superior to example learning when the requirement is an explicit heap transformation—e.g., a bounded internal data-structure routine.

**Recommended GigWerk role:** an optional later worker for small, isolated mutable-memory algorithms only. Do **not** make it the general actor engine: its source language and contracts are heap-oriented, and it has no native OCaml, Prolog, Kotlin, Java, or Android backend.

**What can be reused exactly:** Scala/JVM synthesis implementation, SSL `.def`/`.syn` representation, minimal C-like output, and optional certificate targets (HTT/VST/Iris; see [certification notes](https://raw.githubusercontent.com/tygus/suslik/master/certification.md)).

**What is missing:** OCaml/Prolog bridge, controlled JVM worker, lowering/backend, domain API model, Android packaging, and a strict policy around timeouts and the cyclic proof checker. The supplied source evidence warns that an unavailable cyclic checker can make termination checking unsound; certificates also are not automatically an end-to-end GigWerk proof.

**Verification meaning:** the paper states soundness for derived programs—safe reads/writes/deallocation and specification satisfaction under its assumptions, with well-founded recursive behavior for supported predicates. Search can time out/fail, and certificate workflows can require manual proof work.

### 3. Popper — choose only if Prolog is the primary product language for rules

**Why it ranks third:** Popper is a real deterministic symbolic synthesizer, but its contract is **inductive**: positive/negative examples, Prolog background knowledge, and an explicit hypothesis bias (predicate declarations, types/directions, recursion and bounds). It generates definite Prolog programs using ASP/Clingo plus SWI-Prolog evaluation ([README](https://raw.githubusercontent.com/logic-and-learning-lab/Popper/main/README.md), [paper](https://arxiv.org/abs/2005.02259)). It is therefore the best candidate among the supplied projects for Prolog-centered relational policy/rule construction.

**Recommended GigWerk role:** a narrowly sandboxed optional worker for relations such as eligibility/classification or recursively defined domain rules, **only** when GigWerk provides examples, negative counterexamples, background predicates, and a very small bias. It should not be selected to meet a claim of general formal-contract synthesis.

**What can be reused exactly:** Python/Clingo/SWI-Prolog worker, directory input convention (`exs.pl`, `bk.pl`, `bias.pl`), and printed Prolog hypothesis format.

**What is missing:** Prolog contract lowering, OCaml process adapter, safe output parsing, sandboxed replay, independent property checking, a typed IR/verified lowering to OCaml, actor-state semantics, termination/resource governance, and Android integration.

**Verification meaning:** for its supplied background knowledge and hypothesis language, Popper checks that an output entails all supplied positives and no negatives. That is **example-relative** correctness; it is not a proof of arbitrary postconditions, general termination, target-language semantic equivalence, or safe mobile runtime behavior.

## Important alternatives, correctly scoped

### Myth: closest OCaml-like output, but not the recommended foundation

Myth is a genuine synthesis engine for a typed, pure OCaml subset: declared ADTs, a typed goal, and finite input/output examples lead to printed recursive OCaml-like code ([repository](https://github.com/silky/myth), [PLDI paper](https://www.cis.upenn.edu/~stevez/papers/OZ15.pdf)). It is useful as a **research comparison or narrow prototype** after licensing is clarified.

It is not first choice because examples do not constitute general formal postconditions; recursive examples must be trace-complete; the supplied inspection found no explicit license file/SPDX; and the last inspected source commit was in 2019. No current build was performed. It does not supply Prolog input, effects/heap semantics, Android packaging, or an arbitrary OCaml backend.

### Synquid: strong pure refinement-contract synthesis, but Haskell-facing

Synquid constructs pure recursive functions from polymorphic refinement-type contracts over ADTs, measures, predicates, and termination measures ([repository](https://github.com/nadia-polikarpova/synquid), [paper](https://dl.acm.org/doi/10.1145/2908080.2908093)). Its MIT license is favorable, and it is a compelling reference for a pure-contract tier. However, the supplied evidence places it on Haskell with old/stale Z3/Stack assumptions; it offers optional generated Haskell, not OCaml or Android, and has no evidenced support for mutable state, effects, concurrency, or Android APIs.

### Metagol: research option only, not a strategic choice

Metagol generates Prolog hypotheses by instantiating user-provided metarules against examples/background predicates ([repository](https://github.com/metagol/metagol), [README](https://raw.githubusercontent.com/metagol/metagol/master/README.md)). It can express recursion, invented predicates, mutual recursion, and some higher-order patterns. But its own README says it is no longer under development and mostly superseded by Popper. It has the same essential limitation: bias plus examples is not a general formal contract.

## Minimal, low-risk integration path

1. **Scope the first validation, not the final product.** Test a pure transition function from a typed formal contract plus an explicit grammar. This is a proof-of-mechanism; it does not fulfill the broader arbitrary-code goal by itself.
2. **Define a tiny typed IR.** Use immutable `State`, closed `Command`, `Result`, integers/enums, pure helper functions, invariant predicates, and a total transition signature. Reject mutable references, I/O, time, threads, callbacks, reflection, native calls, unbounded collections, and unsupported arithmetic in v1.
3. **Use cvc5 behind a process boundary.** Deterministically lower this IR to SyGuS, with fixed grammar/revision/options, wall-clock/memory/output limits, cancellation, and structured `success | unsat | unknown | timeout | rejected` results.
4. **Treat Prolog as an adapter option, not the execution core.** A Prolog notation/frontend can lower only an explicitly accepted declarative subset to the IR. Reject operational Prolog features rather than silently approximating them. Introduce Popper only if example-and-bias rule learning is genuinely required.
5. **Lower accepted terms to a deliberately small OCaml subset.** This renderer is GigWerk-owned, not supplied by cvc5. Parse/typecheck the generated output and independently replay the same constraints before acceptance. Keep the Android layer outside the generated code until the pure core is stable.
6. **Add heap synthesis only on evidence.** If a concrete isolated heap procedure is required, evaluate SuSLik as a dedicated worker with its own contract/backend/proof policy—not as a replacement for the core pure actor route.

## Recommended next validation/demo

Run an isolated, reproducible **cvc5 SyGuS smoke test** before any GigWerk implementation: build a pinned official cvc5 revision in a disposable environment, execute its documented `examples/api/smtlib/sygus-fun.sy` example, and capture the exact binary hash, options, input, output, exit status, and replay result. Then repeat with **one hand-authored, non-production, bounded GigWerk-shaped pure transition contract** (for example, a two-state command handler with a rejection branch). Success criteria are: (1) a candidate is constructed from constraints and grammar rather than examples/prose, (2) replay satisfies the contract, (3) its term maps mechanically to the proposed OCaml subset, and (4) timeout/`unknown`/invalid-output paths are handled as normal outcomes. Do not test Android, persistence, booking APIs, or Prolog lowering in this first demo.

For a separate heap claim, the equivalent low-risk proof point is SuSLik’s documented `examples/listcopy.syn`, with the cyclic proof checker present and the emitted procedure/certificate artifacts retained. These documented commands were **not run** in the supplied research.

## Licensing, maintenance, and platform caveats

- **cvc5:** Modified BSD/BSD-3-Clause family, but optional dependency choices can introduce GPL obligations; perform a build-configuration license review before shipping. Supplied evidence describes active maintenance, not a guarantee of future compatibility.
- **SuSLik:** BSD 2-Clause; latest inspected revision dates to 2022. Treat it as research software and pin all JVM/solver/prover dependencies.
- **Popper:** MIT; supplied metadata was current-looking, but runtime requirements include modern Python and SWI-Prolog. Pin the entire worker environment.
- **Metagol:** BSD 3-Clause, but explicitly no longer under development / mostly superseded.
- **Synquid:** MIT, but stale toolchain assumptions (including Z3-version tension) must be resolved before a build claim.
- **Myth:** no explicit license was found in the supplied inspection. **Do not embed, redistribute, or depend on it until license/author permission is confirmed.**
- **Android:** none of the six projects is evidence of Android support. NDK/JNI, ABI, lifecycle, process isolation, cancellation, storage/network bridging, and mobile test verification are independent future work.

## Verification status and residual uncertainty

The initial source survey ran no demos. Follow-up validation on the parent Sandbox did run the following:

- **cvc5 1.1.2**, Ubuntu package `1.1.2-1build1`: the official `sygus-fun.sy` specification produced `max`/`min` function definitions from logical constraints. Two runs with `--seed=0 --tlimit=10000` returned byte-identical output. A separate SMT query asking for any violation of the supplied contract returned `unsat`. This uses the same solver, so it is replay evidence, not an independent proof checker or OCaml equivalence proof.
- **Metagol**, revision `7b617992d30d3cee37a6f4bb8667f717a46cc6a3`, with host SWI-Prolog 9.0.4: `grandparent.pl` constructed a three-clause program with an invented helper; `mutual-recursion.pl` constructed mutually recursive even/odd-like clauses. Both exited successfully under a 20-second external timeout. These demonstrate program construction from background predicates, examples and metarules—not universal formal-contract correctness.

Inputs, outputs, a solver binary hash and the counterexample query are in the accompanying `demo` evidence directory. The other four candidate projects were not built or executed. No full suite, generated OCaml compilation, GigWerk integration or Android test was performed.

The decisive remaining uncertainty is **operational fit**, not existence: whether an engine can express a real GigWerk contract without requiring the agent to author the implementation, and whether its output can be lowered to OCaml without changing semantics. A general recursive-functional task is the next relevant test; repeating small arithmetic demonstrations is not enough to establish the requested developer actor.
