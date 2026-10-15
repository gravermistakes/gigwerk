# Popper inductive logic program synthesis — GigWerk reuse assessment

**Scope.** Exactly one project was investigated: the canonical Popper implementation maintained by the Logic and Learning Lab. Evidence was taken from the repository, its checked-out source/examples/metadata, and the authors' paper. No code was executed and no dependencies were installed.

## Identity and provenance

- **Project:** Popper (inductive logic programming system)
- **Canonical repository:** https://github.com/logic-and-learning-lab/Popper
- **Repository license:** MIT (repository `LICENSE`, copyright Logic and Learning Lab, 2021).
- **Paper:** Andrew Cropper and Rolf Morel, *Learning programs by learning from failures*, Machine Learning 110(4), 801–856 (published 2021), DOI https://doi.org/10.1007/s10994-020-05934-z; open version https://arxiv.org/abs/2005.02259 and full HTML https://arxiv.org/html/2005.02259v3.
- **Repository evidence:** default branch `main`; GitHub metadata reports 975 commits and top-level `examples/`, `popper/`, `scripts/`, `popper.py`, `pyproject.toml`, `setup.py`, `LICENSE`, and `solvers.md`. The checked-out current metadata declares package version 5.0.0 and Python >=3.14. The repository has active-looking current build/test metadata, but this investigation did not run it; do not infer production support for any target platform from that alone.

## What it actually synthesizes

Popper is genuine contract/bias-constrained program synthesis, but its contract is an **ILP learning problem** rather than an arbitrary software contract. The paper describes a generate–test–constrain loop: generate a candidate logic program satisfying syntactic hypothesis constraints; test entailment against positive/negative examples and background knowledge; learn constraints from failures; repeat until a consistent hypothesis is found or the bounded search space is exhausted. This is materially more than a theorem checker, an LLM coding wrapper, or a library binding.

The implementation uses Python orchestration plus **Clingo/ASP** for candidate generation and constraint solving and **SWI-Prolog** (via the current `janus_swi` dependency) for testing/evaluation. The paper explicitly says Popper combines answer-set programming and Prolog. It therefore constructs a symbolic output program; no model/LLM call is involved or required.

## Exact input language and output

Each problem directory requires three Prolog-syntax files:

1. `exs.pl`: positive and negative target examples, e.g. `pos(grandparent(ann,amelia)).` and `neg(grandparent(amy,amelia)).`
2. `bk.pl`: background knowledge, expressed as Prolog facts/rules.
3. `bias.pl`: hypothesis-space contract, including `head_pred/2`, `body_pred/2`, and optional `type/2`, `direction/2`, recursion and other constraints.

The output is a **definite logic program / set of Prolog rules** (the learned hypothesis), printed by the CLI. The repository's `synthesis-finddupl` example documents output of the form:

```prolog
f(A,B):- tail(A,C),head(A,B),element(C,B).
f(A,B):- tail(A,C),f(C,B).
```

This is real code generation in the target logical language, not merely a classifier label. It is nevertheless constrained to the supported hypothesis language and declarations; it does not promise arbitrary Python, OCaml, Android, imperative code, or unrestricted Prolog.

## Supported structures and boundaries

- **Recursion:** supported, including recursive target calls; enabled with `enable_recursion.` in the bias. The README warns recursion is expensive.
- **Lists and numbers:** explicitly supported by the paper; repository examples include list transformations, arithmetic-oriented predicates, and directions for numeric relations.
- **Types:** optional predicate type annotations in `bias.pl` (e.g. list/element/int), used to reduce search.
- **Modes/directions:** optional `in`/`out` argument annotations; if supplied, they must cover all relations (partial directions are unsupported).
- **Predicate invention:** not a general strength in this repository; README performance advice says to avoid predicate invention.
- **ADTs:** no evidence in the inspected primary sources of a general algebraic-data-type contract or an OCaml ADT backend. Prolog terms/lists and typed predicate declarations are not equivalent to OCaml algebraic data types.
- **State/heap/effects:** no evidence that Popper synthesizes imperative state machines, mutable heap protocols, Android lifecycle code, or effectful OCaml. Its semantics are definite logic programs evaluated through Prolog/ASP. It can model relational structures supplied as BK, but that is not a native heap/state synthesis guarantee.

## Correctness, optimality, and limits

The paper states soundness and completeness results for Popper under its stated assumptions (notably definite and separable hypotheses in the relevant proof). Operationally, a returned hypothesis is tested to entail all positives and none of the negatives under the supplied BK; this is an **example-relative logical guarantee**, not proof of arbitrary-contract correctness. The paper's termination condition is finite/bounded search exhaustion or finding a consistent hypothesis; it does not make unrestricted recursive programs terminate on all future inputs.

Search is explicitly bounded in the implementation: `--max-vars` (default 6), `--max-body` (default 10), a rule/clause bound, and `--timeout` (README default 3600 seconds). The paper's algorithm searches increasing program size for optimal solutions within the configured space; “optimal” means the selected size/minimality criterion within that search, not globally shortest arbitrary code. Noisy mode uses an MDL cost function. Recursion, larger bounds, invention, and rich BK can make search expensive. The paper reports experiments, not a universal performance or termination guarantee.

## Maintenance and test evidence

The public repository contains regression infrastructure (`scripts/test_benchmark_regression.py`) with deterministic environment controls (`PYTHONHASHSEED=0`, Clingo seed), benchmark baselines, program-size and timeout checks. It also contains many real examples: synthesis (find duplicate, length, reverse, sorted, etc.), robot strategies, games, kinship, trains, and noisy datasets. This is evidence of maintained engineering and reproducibility scaffolding, not proof that all benchmarks pass today. The current package metadata requires Python >=3.14 and depends on Clingo, `janus_swi`, OR-Tools, python-sat/pypblib, bitarray, cykhash, and Cython-built extension code. No local execution was attempted because the request forbade heavy installation/execution; **test status is therefore unverified in this environment**.

## Fit for GigWerk

**Good fit:** Popper can serve as a deterministic, model-free symbolic synthesis worker when GigWerk's contract is expressible as a finite/bounded Prolog hypothesis space plus BK and positive/negative behavioral examples. Its bias file is a genuine explicit synthesis contract: permitted heads/bodies, arities, types, directions, recursion, and size bounds. The output is inspectable Prolog and can be passed to a separate verifier/runtime. It makes no model calls.

**Poor/direct fit:** It is not an OCaml actor, does not emit OCaml, and does not synthesize arbitrary code from a standalone formal specification. It requires examples (including negatives for the standard setting), BK, and a search bias; it cannot infer a useful unconstrained algorithm from only an informal contract. It does not provide Android packaging, mobile runtime integration, a stable library API for OCaml, or a proof that synthesized recursive code terminates on all inputs.

## Missing glue for GigWerk

1. Define a GigWerk contract-to-ILP lowering: target predicates, BK vocabulary, admissible clauses, types/directions, examples and negative counterexamples.
2. Add an OCaml process/API adapter that invokes Popper out-of-process, validates/parses its Prolog output, records solver settings and timeout, and rejects malformed or out-of-contract hypotheses.
3. Add a deterministic Prolog execution/verification sandbox and a second-stage contract checker; example fit alone is insufficient.
4. Decide how relational Prolog output becomes an actor interface (state transition relation, action selection, serialization, failure behavior). This is the largest semantic gap.
5. If OCaml/Android output is required, implement a verified compiler/translation from the restricted learned clause subset to OCaml (or retain a Prolog runtime); Popper itself supplies neither.
6. Add resource budgets, recursion/termination policy, adversarial counterexample generation, and reproducible regression tests. Treat timeouts/search exhaustion as normal “no synthesis” outcomes.

## Small documented demo (not run)

From the repository README:

```bash
git clone https://github.com/logic-and-learning-lab/Popper.git
cd Popper
uv run popper.py examples/iggp-rps-next-score
# documented recursion example:
uv run popper.py examples/synthesis-finddupl
```

Prerequisites documented by the README are SWI-Prolog, GNU Coreutils, and `uv`; current `pyproject.toml` additionally declares Python >=3.14 and packaged solver/runtime dependencies. These commands are documentation-derived and were **not executed** here.

## Bottom line

Popper is a credible canonical choice for **deterministic, model-free induction of bounded Prolog definite programs from examples + BK + an explicit logical bias**. It is not, by itself, GigWerk's requested OCaml deterministic actor or a general contract-to-arbitrary-code synthesizer. Reuse is plausible as an isolated synthesis backend after a carefully restricted Prolog contract and a substantial OCaml/runtime/verification glue layer.

## Evidence URLs

1. Repository and README: https://github.com/logic-and-learning-lab/Popper
2. Repository raw README: https://raw.githubusercontent.com/logic-and-learning-lab/Popper/main/README.md
3. Repository raw `pyproject.toml`: https://raw.githubusercontent.com/logic-and-learning-lab/Popper/main/pyproject.toml
4. Repository raw regression script: https://raw.githubusercontent.com/logic-and-learning-lab/Popper/main/scripts/test_benchmark_regression.py
5. Paper abstract/metadata: https://arxiv.org/abs/2005.02259
6. Full paper HTML: https://arxiv.org/html/2005.02259v3
7. Published paper landing page: https://dl.acm.org/doi/10.1007/s10994-020-05934-z
