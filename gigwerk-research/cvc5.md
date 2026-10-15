# cvc5 Syntax-Guided Synthesis (SyGuS): GigWerk reuse assessment

**Research scope.** Exactly one project was researched: [cvc5](https://github.com/cvc5/cvc5), specifically its SyGuS engine and public examples. Evidence was collected from the canonical repository, official documentation, the project publications page, and the official TACAS 2022 system-description paper. The repository was inspected read-only via a shallow clone; no build, solver execution, unsafe code, dependency installation, or GigWerk modification was performed.

## Executive finding

cvc5 is a real contract-to-term/program synthesizer, not merely an example-fitting library, theorem checker, LLM coding assistant, or wrapper. A SyGuS problem supplies a **typed grammar** (the syntactic search space) plus logical constraints; cvc5 enumerates candidate terms/programs and checks them against the constraints. Its official API example synthesizes `max` and `min` from universally quantified semantic constraints, with an explicit grammar for `Int` and `Bool`, and returns SMT-LIB-style `define-fun` solutions. It therefore fits a deterministic actor architecture in which an upstream component emits a formal contract and grammar, while cvc5 searches for an implementation.

It is **not** an arbitrary-code generator. The output is a term/definition in the supplied SyGuS grammar and supported background theories. A GigWerk integration must design a domain-specific typed grammar and a lowering/compilation path from returned SMT-LIB terms to OCaml (or another target). cvc5 does not consume Prolog contracts directly, does not emit OCaml/Android code directly, and does not promise termination on all synthesis problems.

## Identity and canonical sources

- **Project / ID:** cvc5 SyGuS engine (`cvc5`), part of the cvc5 SMT solver.
- **Canonical repository:** <https://github.com/cvc5/cvc5>
- **Official docs:** <https://cvc5.github.io/docs/>; SyGuS function example: <https://cvc5.github.io/docs/cvc5-1.0.7/examples/sygus-fun.html>; grammar example: <https://cvc5.github.io/docs/cvc5-1.0.7/examples/sygus-grammar.html>.
- **Official system paper:** Barbosa et al., “cvc5: A Versatile and Industrial-Strength SMT Solver,” TACAS 2022, DOI <https://doi.org/10.1007/978-3-030-99524-9_24>. The paper describes cvc5 as an SMT solver and system architecture; the project publications page is <https://cvc5.github.io/publications.html>.

## Exact input language and contract shape

### Text input: SyGuS/SMT-LIB

The repository contains `examples/api/smtlib/sygus-fun.sy` and hundreds of regression inputs under `test/regress/cli/.../sygus`. The input is SMT-LIB/SyGuS syntax, including declarations such as:

```lisp
(set-logic LIA)
(synth-fun max ((x Int) (y Int)) Int
  ((Start Int (0 1 x y (+ Start Start) (- Start Start)
                   (ite StartBool Start Start)))
   (StartBool Bool ((and StartBool StartBool) (not StartBool)
                    (<= Start Start)))))
(declare-var x Int)
(declare-var y Int)
(constraint (>= (max x y) x))
(constraint (>= (max x y) y))
(constraint (or (= (max x y) x) (= (max x y) y)))
(check-synth)
```

The official C++ example expresses the same structure through `Solver::mkGrammar`, `Grammar::addRules`, `synthFun`, `declareSygusVar`, `addSygusConstraint`, and `checkSynth`. A grammar has typed nonterminals, variables, constants, and production rules; synthesis functions have argument sorts and a return sort. A grammar is optional in some API calls, but omitting it does not make the language arbitrary: the solver still operates over the supported SyGuS/theory term space.

### Contract semantics

The contract is a logical relation/constraint over synthesized function applications. In the official `max`/`min` example, constraints require lower bounds, selection of one input, and a sum relation between `max` and `min`. This is semantic synthesis, not merely memorizing finite input/output examples. PBE/example-only problems are also possible in the broader SyGuS ecosystem, so an integrator must inspect the actual constraints and grammar used; cvc5 does not turn examples into a general-purpose specification automatically.

### Supported structures evidenced in source/tests

The source tree contains dedicated SyGuS grammar, datatype, enumerator, solver, and quantifier-synthesis components (`src/expr/sygus_*`, `src/smt/sygus_solver.*`, `src/theory/quantifiers/sygus/`). The checked-in regression inventory includes grammar tests, algebraic datatypes, arrays, strings, higher-order occurrences, invariants, abducts, and recursive-function-related cases. The options source includes `sygus-rec-fun-infer`, documenting recursive-definition inference. This supports richer typed term structure than numeric examples, but does **not** establish unrestricted general recursion, arbitrary mutable state, heap effects, Android APIs, or compilation to executable machine code. The core model is SMT terms/functions over theories; state/heap must be encoded into a supported pure/logical theory or handled by an external effectful runtime.

## Exact output

For the official API example, `checkSynth()` returns a synthesis result and `getSynthSolutions(...)` returns cvc5 `Term` objects. The documented expected output is equivalent to:

```lisp
(define-fun max ((x Int) (y Int)) Int (ite (<= x y) y x))
(define-fun min ((x Int) (y Int)) Int (ite (<= x y) x y))
```

CLI output is SMT-LIB-like synthesized definitions/terms. There is no native OCaml source emitter or Android package generator in the evidence inspected. The returned term can be serialized/printed and then transformed by a GigWerk-specific backend, provided the grammar-to-target mapping is total and semantics-preserving for the selected fragment.

## Implementation, license, maintenance

- **Implementation language:** The README states cvc5 is written entirely in C++. It exposes C++ as the primary API and provides Java and Python bindings; official installation docs also describe the C API and language-binding configuration in current source/docs. No official OCaml or Prolog binding was identified in the inspected canonical repository.
- **License:** Modified BSD / BSD-3-Clause family. The repository `COPYING` grants redistribution and modification under the modified BSD terms. It warns that optional GPL libraries (for example CLN, GLPK-related support, and Normaliz) can change licensing obligations; avoid those optional dependencies for a clean permissive integration. The official site identifies the project license as BSD.
- **Maintenance evidence:** GitHub metadata showed the `main` branch, an active repository with 14,000+ commits, and a current revision observed during research (`e500561...`, dated 2026-10-14 in the API response). Source `cmake/version-base.cmake` identified latest release metadata as `1.4.2` in the inspected revision. Dates and revision are point-in-time evidence, not a promise of future maintenance.

## Models and determinism

- **Model calls:** None required. cvc5 is a native symbolic solver/synthesizer; the official examples and source show no LLM/model service dependency.
- **Determinism:** The actor can be made deterministic by pinning cvc5 revision, options, grammar, logic, resource limits, and platform/build. However, do not infer bit-for-bit determinism across all platforms or versions without testing; enumeration modes include `auto`, `smart`, `fast`, `random`, and `var-agnostic`, and the source documents randomized enumeration parameters.
- **Search limits:** The source documents synthesis enumeration modes, candidate-verification timeout (`--sygus-verify-timeout`, 0 means no limit), verification instantiation-round limit (default 10; `-1` means no limit), and other synthesis timeouts. A search may find a solution, report infeasible/unsat for a bounded/finite search context, return unknown, or exhaust resources. No universal termination guarantee for arbitrary SyGuS contracts should be claimed.

## Correctness guarantees and limits

A returned candidate is intended to satisfy the supplied SyGuS constraints under cvc5's supported theory reasoning. That is a solver-level logical guarantee subject to the selected logic, options, resource limits, and trust in the solver/build; it is not a proof that arbitrary generated target-language code is safe, terminating, memory-safe, or behaviorally equivalent after lowering. The TACAS paper is a system description of cvc5, not a formal proof that every synthesis result is independently proof-carrying. If GigWerk requires an auditable certificate, preserve the original contract, grammar, cvc5 version/options, candidate, and an independent replay/check step.

## Fit for GigWerk

### Strong fit

1. **Formal contract as actor input:** translate a GigWerk contract into SMT-LIB SyGuS or the C++/Python API.
2. **Model-free deterministic synthesis:** no neural model or remote call is needed.
3. **Broader than examples:** typed grammars and logical constraints support relational specifications and structured terms.
4. **Actor boundary:** cvc5 can be a deterministic worker that accepts a versioned contract/grammar and returns a candidate plus status.

### Prolog / OCaml fit

- **Prolog:** No direct Prolog input language was found. Prolog can remain the contract/orchestration language, but a serializer/translator must map Prolog predicates and terms to SMT-LIB theories and SyGuS grammar productions. Operational Prolog semantics (unbounded recursion, cuts, side effects, dynamic predicates) are not automatically represented.
- **OCaml:** No official OCaml binding was found in the inspected repo/docs. Practical options are (a) invoke the cvc5 CLI with generated SMT-LIB and parse output, (b) build a small C ABI shim and bind it from OCaml, or (c) bind/bridge through an available supported language. CLI integration is simplest but needs robust parsing, process/resource isolation, and version pinning.
- **Android later:** Official docs mention ARM64 cross-compilation and WebAssembly compilation, but this is not evidence of an Android-ready artifact. Android packaging would require a separate NDK/CMake integration, ABI/dependency audit, JNI or native bridge, and mobile resource/time policy. Treat this as future engineering, not current capability.

## Missing glue / principal risks

1. **Contract compiler:** Prolog/ GigWerk contract representation → SyGuS SMT-LIB/API terms.
2. **Grammar authoring:** a finite, typed DSL of allowed actor constructs; this is the key safety and capability boundary.
3. **Target backend:** cvc5 term/SMT-LIB definition → OCaml AST or another executable representation, with a semantics-preservation story.
4. **Effects/state:** encode state as explicit data/state-transition relations or add a verified external runtime; cvc5 does not synthesize arbitrary heap-mutating Android code from the example API.
5. **Resource policy:** timeouts, memory/process sandboxing, deterministic options, cancellation, and failure statuses.
6. **Replay evidence:** retain contract, grammar, solver revision, configuration, candidate, and post-lowering validation.
7. **Licensing:** keep optional GPL dependencies disabled unless GigWerk accepts the resulting obligations.

## Small documented demo commands (not executed here)

These commands are copied/adapted from official documentation; they are **not claimed to have been run locally**.

### CLI SyGuS file

```sh
# From a configured cvc5 build, where build/bin/cvc5 exists:
build/bin/cvc5 examples/api/smtlib/sygus-fun.sy
```

The input file is the repository's `examples/api/smtlib/sygus-fun.sy`; it uses `set-logic`, `synth-fun`, typed grammar productions, `declare-var`, `constraint`, and `check-synth`.

### Official build flow

```sh
./configure.sh
cd build
make -j2
# documented test target (not run in this research)
make check
```

The official installation page documents `./configure.sh`, `make`, `make check`, and `make install`; it also documents `--python-bindings`, `--java-bindings`, ARM64 cross-compilation, and WebAssembly options. Building cvc5 was intentionally not attempted here.

## Verification status

- **Repository inspection:** completed read-only from a shallow clone; source/examples/options/test metadata inspected.
- **Solver/build execution:** not performed. Therefore this report does not claim local reproduction, successful compilation, benchmark performance, or Android viability.
- **Test evidence:** repository inspection found approximately 310 SyGuS/synthesis-named regression files in the shallow clone, plus API examples. This is evidence of checked-in coverage, not a test run.

## Sources

1. Canonical repository and README: <https://github.com/cvc5/cvc5>
2. Official SyGuS function API example: <https://cvc5.github.io/docs/cvc5-1.0.7/examples/sygus-fun.html>
3. Official SyGuS grammar page: <https://cvc5.github.io/docs/cvc5-1.0.7/examples/sygus-grammar.html>
4. Official installation/build/testing documentation: <https://cvc5.github.io/docs/cvc5-1.0.7/installation/installation.html>
5. Official publications index: <https://cvc5.github.io/publications.html>
6. Barbosa et al., TACAS 2022 paper: <https://doi.org/10.1007/978-3-030-99524-9_24>
7. Source files inspected in the canonical repository: `examples/api/smtlib/sygus-fun.sy`, `examples/api/cpp/sygus-fun.cpp`, `src/options/quantifiers_options.toml`, `cmake/version-base.cmake`, `COPYING`, `src/expr/sygus_*`, `src/smt/sygus_solver.*`, `src/theory/quantifiers/sygus/*`, and `test/regress/**/sygus/*`.
