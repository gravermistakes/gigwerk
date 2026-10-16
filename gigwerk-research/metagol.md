# Metagol meta-interpretive learning: reuse assessment for GigWerk

**Scope.** This report covers exactly one project: the canonical `metagol/metagol` repository. It distinguishes contract-/bias-constrained logic-program synthesis from example-only induction, theorem proving, LLM coding, and wrappers. Claims below are based on the repository README/source/examples and primary or institutional paper pages; no local execution is claimed.

## Structured identification

| Field | Finding |
|---|---|
| Project | Metagol (the repository itself says it is an inductive logic programming system based on meta-interpretive learning) |
| Canonical repository | [`https://github.com/metagol/metagol`](https://github.com/metagol/metagol) |
| Implementation | Prolog; README says it runs with SWI-Prolog. Core file is `metagol.pl`. |
| License | BSD 3-Clause (“New”/Revised); both GitHub metadata and the repository license identify this. |
| Model calls | None required or present. It is symbolic Prolog search/meta-interpretation, not an LLM or neural model. |
| Current status | README explicitly says this version is no longer under development and is mostly superseded by Popper. GitHub metadata reports the latest push as 2021-09-13; the latest visible commit is `7b617992d30d` (“Update README.md”, 2021-09-13). GitHub’s page metadata currently reports 254 commits and a later page update, but that is not evidence of active source maintenance. |

## What the system actually synthesizes

Metagol takes:

1. **Positive and negative ground examples** (`learn(Pos, Neg)`),
2. **Background knowledge** declared through predicates such as `body_pred/1` (and optionally compiled predicates), and
3. **User-supplied metarules** (`metarule(...)`) defining the allowed clause shapes and therefore the hypothesis/search space.

The README’s grandparent example learns a Prolog program from mother/father background facts plus five positive and one negative examples. The produced output is a set of ordinary Prolog clauses, including an invented predicate (`grandparent_1`). This is genuine program synthesis by constrained symbolic search: the learner instantiates metarules, meta-interprets/proves examples, rejects negative entailments, grounds the resulting program, and pretty-prints it. It is **not** arbitrary-code generation: users must provide the metarules and background predicate declarations, and only programs expressible by that bias are searched.

The core source confirms this operational boundary. `learn/3` calls `proveall/3`, `nproveall/3`, `ground/1`, and optional `check_functional/3`; synthesis branches call `metarule(...)`, manage invented symbols, and recursively prove bodies. `learn/2` prints the resulting program. There is no LLM/API invocation and no separate theorem prover.

## Exact input and output languages

### Input

The input is **SWI-Prolog source/data** using Metagol’s declarations and ordinary Prolog terms:

- `body_pred(Name/Arity)` declares usable background predicates.
- `metarule(Name, Subs, Head, Body)` (or shorthand forms expanded by term expansion) supplies second-order predicate variables and first-order variables. The README gives identity, inverse, pre/post-connection, and chain forms.
- Positive/negative examples are ordinary atoms, e.g. `grandparent(ann,amelia)`.
- Background facts/rules are ordinary Prolog.
- Optional `ibk(Head, Body)` gives interpreted background knowledge (the README’s `map/3` example is recursive and higher-order).
- Optional `func_test/3` plus `metagol:functional` imposes a functional consistency check.

### Output

The output is a **ground Prolog logic program** (a list of instantiated metarule substitutions internally, then ordinary clauses via `pprint/1`). It may contain invented predicate symbols (`target_1`, `f_1`, etc.), recursion, mutual recursion, and higher-order constructions represented as Prolog predicates/terms. It does not output OCaml, Java/Kotlin, Android bytecode, a native actor, or a general-purpose imperative program.

## Supported structures (with evidence and limits)

- **Recursion:** explicitly supported. README supplies a recursive metarule and points to `find-duplicate`, `sorter`, `member`, and string examples. The repository includes `examples/mutual-recursion.pl`; its comments say it learns `even` while inventing `odd`.
- **Predicate invention:** supported, including invented helper predicates and the higher-order paper’s predicate/function/condition invention within interpreted definitions.
- **Higher-order/list transformations:** supported through interpreted background knowledge (IBK). `examples/higher-order1.pl` defines recursive `map` IBK and learns a list transformation using `my_succ/2`.
- **Algebraic data types:** no dedicated typed ADT system is exposed by this repository. Prolog’s recursive terms/lists can encode tree/list-like structures, but that is not the same as OCaml ADTs or static type checking.
- **State/heap:** no native mutable heap/state model is documented. State can be represented relationally by threading arguments through predicates, but this is an integration convention the GigWerk layer would have to impose, not a Metagol guarantee.
- **Broadness beyond numeric examples:** yes in the ILP sense: repository examples cover kinship, graphs, strings, robots, sorting, trains, constants, higher-order list operations, and mutual recursion. Still, all learned behavior is constrained by the supplied Prolog background and metarules; this is not unconstrained synthesis from an informal contract.

The official higher-order paper describes `Metagol_ho` as extending MIL with higher-order definitions/IBK and reports experiments in robot strategies, chess, list transformations, and string decryption. That paper also says higher-order predicate invention can learn abstractions such as `map/3` and `until/4`. It explicitly identifies metarule selection as a limitation and says some metarules lack theoretical justification.

## Correctness, termination, and search limits

Metagol’s practical correctness condition is example entailment under its Prolog meta-interpreter: all positives must be provable and negatives must not be provable (`nproveall/3`). The optional functional mode checks a user-supplied condition across provable outputs. This is **not** a general formal proof of semantic equivalence, safety, totality, resource bounds, or refinement against a GigWerk contract.

Search is bounded and incomplete relative to arbitrary programs:

- Iterative deepening searches by number of clauses.
- README documents `metagol:max_clauses/1`, default 10, and `metagol:timeout/1`, default 600 seconds.
- The source includes recursion-path checks and prevents recursive one-clause cases, but these are search controls rather than a general termination theorem for every learned program.
- The README calls metarule choice an open and hard problem. The higher-order paper likewise lists metarule choice and some higher-order/curry metarules without theoretical justification as limitations.

Therefore, “learned” means a bounded search found a hypothesis satisfying the supplied examples/checks; it does not mean the actor is globally verified or guaranteed to terminate on all inputs.

## Model-free deterministic actor fit

Metagol is a plausible **symbolic contract-to-logic-program synthesis kernel**, not a complete GigWerk actor. It can be deterministic in the engineering sense if SWI-Prolog version, clause ordering, metarule order, timeout, and search settings are pinned; however, the repository does not promise a canonical deterministic result across environments. It is model-free/no-LLM: no learned numeric policy or model call is involved.

The fit is strongest where GigWerk’s contract can be compiled to:

- a finite set of positive/negative relational tests,
- explicit Prolog background predicates, and
- a deliberately designed metarule grammar for the permitted program shapes.

It is weaker where “contract” means a full formal specification whose consequences must be theorem-checked, or where the actor must synthesize arbitrary OCaml/stateful Android code without the agent choosing an algorithmic bias.

## Prolog/OCaml and Android integration assessment

**Prolog fit:** direct. The canonical implementation is Prolog/SWI-Prolog, accepts Prolog declarations and examples, and emits Prolog clauses. A GigWerk orchestration layer could generate a temporary Prolog task, invoke a pinned SWI-Prolog process, parse the learned clauses, and run independent checks.

**OCaml fit:** indirect and missing glue. Metagol has no OCaml implementation, OCaml output backend, OCaml AST emitter, or OCaml FFI in this repository. An OCaml actor would need a new adapter plus a safe translation/validation pipeline (Prolog terms → a restricted intermediate representation → OCaml AST/code), with explicit handling for invented predicates, recursion, higher-order terms, and runtime semantics. Do not treat HSWIP-like bindings as a synthesizer; a binding only embeds/calls Prolog.

**Android later:** not supported directly. Packaging would require choosing a SWI-Prolog/mobile runtime strategy or compiling generated code to a separate supported target. The repository provides no Android build files, JNI/Kotlin bridge, sandbox, resource limits, or mobile packaging guidance.

## Small documented demo (not executed here)

From the repository README:

```sh
git clone https://github.com/metagol/metagol.git
cd metagol
swipl examples/grandparent.pl
```

The README shows the expected shape of the learned result: `grandparent/2` calling an invented helper and clauses for `mother/2` and `father/2`. The repository’s examples also use timing directives such as `:- time(a).` and `examples/tests.pl` contains expected internal programs for regression-style checks. **This report did not install SWI-Prolog or execute the example; the command is documented, not locally verified.**

## Reusability decision and missing GigWerk glue

**Decision: reusable as a research component, not drop-in.** Reuse the conceptual MIL/metarule search and potentially the Prolog implementation for a prototype. Do not claim that Metagol itself constructs arbitrary GigWerk actors from contracts, emits OCaml, verifies formal contracts, models mutable heaps, or packages Android.

Required glue/work:

1. Define a GigWerk contract-to-Prolog encoding and a restricted metarule library (the contract compiler/algorithmic bias remains a design responsibility).
2. Define a deterministic, pinned SWI-Prolog execution envelope with timeout, clause limit, resource limits, and stable ordering.
3. Add independent validation: positive/negative regression, contract/property checking, termination/resource policy, and rejection of unsafe predicates.
4. Build a typed IR and Prolog→OCaml backend, or keep the actor in a deliberately sandboxed Prolog runtime; neither exists here.
5. Specify state/heap semantics and effect boundaries; Metagol only supplies relational clauses/terms.
6. Add provenance, reproducibility, and Android packaging/runtime work.

## Evidence sources

- Canonical repository README/source/license/examples: [`https://github.com/metagol/metagol`](https://github.com/metagol/metagol), [`README.md`](https://raw.githubusercontent.com/metagol/metagol/master/README.md), [`metagol.pl`](https://raw.githubusercontent.com/metagol/metagol/master/metagol.pl), [`LICENSE`](https://raw.githubusercontent.com/metagol/metagol/master/LICENSE)
- Representative source examples: [`grandparent.pl`](https://raw.githubusercontent.com/metagol/metagol/master/examples/grandparent.pl), [`higher-order1.pl`](https://raw.githubusercontent.com/metagol/metagol/master/examples/higher-order1.pl), [`mutual-recursion.pl`](https://raw.githubusercontent.com/metagol/metagol/master/examples/mutual-recursion.pl), [`tests.pl`](https://raw.githubusercontent.com/metagol/metagol/master/examples/tests.pl)
- Official/institutional MIL paper record: [University of Surrey record for Muggleton et al., *Meta-interpretive learning: application to grammatical inference*](https://openresearch.surrey.ac.uk/esploro/outputs/journalArticle/Meta-interpretive-learning-application-to-grammatical-inference/99537123002346)
- Higher-order MIL paper: [Cropper, Morel & Muggleton, *Learning higher-order logic programs* (PDF)](http://andrewcropper.com/pubs/mlj19-metaho.pdf)
- Related official paper page consulted for context: [Bartha & Cheney, *Towards meta-interpretive learning of programming language semantics*, arXiv:1907.08834](https://arxiv.org/abs/1907.08834)

## Bottom line

Metagol is real symbolic program synthesis, but its “contract” is a **Prolog hypothesis bias plus examples/background predicates**, not an arbitrary formal contract. It is a good candidate for GigWerk’s model-free deterministic synthesis experiment if GigWerk accepts a Prolog-centered, bounded, relational actor language and supplies the missing contract compiler, validator, deterministic sandbox, OCaml bridge, and later Android packaging. It should not be represented as a verified arbitrary-code synthesizer or as an OCaml actor implementation.
