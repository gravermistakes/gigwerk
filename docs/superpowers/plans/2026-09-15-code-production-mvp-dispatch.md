# GigWerk Code Production MVP — Subagent Dispatch Contracts

These briefs are binding execution instructions for fresh implementation subagents. A subagent must execute only the task named in its brief. The implementation plan remains the source of truth, but these briefs eliminate discretionary interpretation at dispatch time.

## Global contract for EVERY implementation subagent

Repository: `gravermistakes/gigwerk`
Branch: `feat/code-production-mvp`

Read before editing:
- `docs/superpowers/plans/2026-09-15-code-production-mvp.md`
- `README.md`
- `ocaml/README.md`
- the exact files named in the task brief

Mandatory rules:
1. Work only on the files explicitly listed under your task. You may read any repository file needed to understand an interface, but do not modify files outside your task's modification set.
2. Do not redesign GigWerk's existing booking architecture. Do not introduce a new model abstraction. Do not introduce frontend code, API code, database migrations, or external inference dependencies.
3. Preserve existing public behavior unless the task explicitly changes it.
4. Use OCaml/Dune/Opam and the repository's existing conventions.
5. Write the failing test before implementation. Run it and observe the expected failure. Then implement the minimum behavior required by the task. Then run the relevant test and the full `cd ocaml && dune test` suite.
6. Do not weaken or delete tests to make them pass. Do not turn a verification failure into success. Do not silently swallow errors.
7. Do not add speculative abstractions, generic frameworks, or dependencies solely for elegance.
8. Before finishing, inspect `git diff --check`, run the relevant test commands again, and report exact commands and outcomes.
9. Commit only the files belonging to this task. Commit message must exactly match the message specified in the task brief.
10. If the repository contradicts the brief, do not silently reinterpret it. Record the conflict and stop rather than changing scope.

## Task 1 — Specification domain and parser

### Dispatch prompt

You are implementing **Task 1 only** of the GigWerk Code Production MVP.

Objective: create the smallest deterministic specification domain and parser needed by later tasks.

Modify/create ONLY:
- `ocaml/lib/production.ml`
- `ocaml/lib/specification.ml`
- `ocaml/test/test_specification.ml`
- `ocaml/lib/dune`

Required interfaces:
- `Specification.parse : string -> (Specification.t, Specification.error) result`
- `Specification.requirements : Specification.t -> Production.requirement list`
- `Production.requirement` must expose stable `id`, `statement`, `depends_on`, and `acceptance` fields.

Required grammar:
- `req <id> : <statement>` declares a requirement.
- `depends <id> : <id>,<id>` adds dependencies to an already-declared requirement.
- `accept <id> : <shell command>` associates an acceptance command with a requirement.
- Preserve declaration order.
- Reject duplicate requirement IDs.
- Reject dependency references to unknown requirements.
- Reject references from `depends`/`accept` to unknown requirements.
- Empty IDs are invalid.
- Empty statements are invalid.
- Empty acceptance commands are invalid.

Tests MUST cover: one requirement; declaration order; multiple dependencies; duplicate IDs; unknown dependency; unknown acceptance target; malformed lines; blank lines/comments if comments are supported.

Do NOT implement graph ordering, filesystem access, Actor behavior, subprocess execution, CLI changes, learning traces, or any form of code generation.

Definition of done:
- New parser tests fail before implementation for the intended reason.
- `cd ocaml && dune test` passes after implementation.
- Existing tests remain green.
- `git diff --check` is clean.
- Commit exactly: `feat: add specification and requirement domain`.

## Task 2 — Deterministic production graph

### Dispatch prompt

You are implementing **Task 2 only** of the GigWerk Code Production MVP.

Objective: turn a parsed specification into a deterministic dependency graph of production obligations.

Modify/create ONLY:
- `ocaml/lib/production_graph.ml`
- `ocaml/test/test_production_graph.ml`
- `ocaml/lib/dune`

Required interfaces:
- `Production_graph.build : Specification.t -> (Production_graph.t, Production_graph.error) result`
- `Production_graph.roots : Production_graph.t -> Production.requirement list`
- `Production_graph.ready : Production_graph.t -> completed:string list -> Production.requirement list`

Required semantics:
- A requirement is ready exactly when every declared dependency ID occurs in `completed`.
- Independent requirements retain specification declaration order.
- The graph must reject cycles and return an explicit cycle path or explicit cycle error.
- Unknown dependency IDs should already be rejected by Task 1; graph construction must still return an error rather than crash if handed malformed input.
- Do not mutate the input specification.

Tests MUST cover: simple root; dependency blocking; multiple dependencies; stable independent ordering; cycle detection; completed dependency unlocking; already-completed requirements excluded from `ready`.

Do NOT implement parsing, workspace operations, Actor interfaces, verification, CLI, or learning.

Definition of done:
- Tests fail before implementation, then pass.
- `cd ocaml && dune test` is green.
- No nondeterministic hash-table iteration leaks into returned ordering.
- Commit exactly: `feat: add deterministic production obligation graph`.

## Task 3 — Confined workspace and code-producing Actor interface

### Dispatch prompt

You are implementing **Task 3 only** of the GigWerk Code Production MVP.

Objective: create the filesystem boundary and the narrow Actor interface through which code can be produced without allowing the Actor to escape its workspace or decide verification success.

Modify/create ONLY:
- `ocaml/lib/workspace.ml`
- `ocaml/lib/code_actor.ml`
- `ocaml/lib/template_actor.ml`
- `ocaml/test/test_code_actor.ml`
- `ocaml/lib/dune`

Required interfaces:
- `Workspace.create : string -> (Workspace.t, Workspace.error) result`
- `Workspace.write : Workspace.t -> path:string -> contents:string -> (unit, Workspace.error) result`
- `Workspace.read : Workspace.t -> path:string -> (string, Workspace.error) result`
- `Code_actor.S.produce : context -> Production.requirement -> Workspace.t -> (Production.artifact, Code_actor.error) result`
- `Template_actor.create : templates:(string * string) list -> (module Code_actor.S)`

Workspace security requirements:
- Canonicalize the root once at workspace creation.
- Reject absolute paths.
- Reject `..` path components.
- Create parent directories only beneath the canonical root.
- Never follow a path that escapes the root through symlink traversal if the implementation can detect it using standard Unix facilities; at minimum, reject explicit `..` and absolute escape paths and test the documented boundary.
- Return structured errors instead of raising for expected invalid-path cases.

Actor requirements:
- `produce` receives immutable context, exactly one requirement, and exactly one supplied workspace.
- Actor may write source files through `Workspace.write` only.
- Actor returns an artifact containing the requirement ID and all paths it produced.
- Actor does not execute generated programs.
- Actor does not declare verification success.
- Template actor is deterministic: same context + requirement + templates produce identical file contents.
- No external inference service, subprocess, database, or network call is allowed.

Tests MUST cover: successful write/read; nested directories; absolute path rejection; parent traversal rejection; artifact requirement ID; generated path list; deterministic output; Actor cannot report verification success; Actor cannot write outside workspace.

Do NOT modify `actor.ml`, `booking.ml`, `store.ml`, CLI code, verifier code, or database schema.

Definition of done:
- Tests fail before implementation, then pass.
- Full Dune suite is green.
- `git diff --check` is clean.
- Commit exactly: `feat: add confined code-producing actor interface`.

## Task 4 — Deterministic compiler/test verifier

### Dispatch prompt

You are implementing **Task 4 only** of the GigWerk Code Production MVP.

Objective: execute the acceptance commands declared by the specification from the generated workspace and convert process results into structured verification evidence.

Modify/create ONLY:
- `ocaml/lib/verifier.ml`
- `ocaml/test/test_verifier.ml`
- `ocaml/lib/dune`

Required interfaces:
- `Verifier.verify : Workspace.t -> Specification.t -> Verification.t`
- `Verification.t` records, for every executed acceptance command: command text, exit status, stdout, stderr, and pass/fail status.

Required semantics:
- Run acceptance commands from the workspace root.
- Execute the exact command text supplied by the specification; do not rewrite it into a semantic approximation.
- Preserve stdout and stderr separately.
- Use process exit status as the pass/fail authority. Never infer success merely because stdout contains words such as `PASS`.
- Enforce a finite timeout.
- A timeout is a structured verification failure, not a crash of the verifier.
- A failed acceptance command makes overall verification fail.
- Multiple acceptance commands are independently recorded.

Tests MUST create temporary valid and invalid Dune projects and cover: success, syntax failure, type failure, nonzero exit status with misleading stdout, stderr capture, and timeout.

Do NOT add remote execution, sandboxing frameworks, Docker, frontend integration, learning, CLI changes, or arbitrary command rewriting.

Definition of done:
- Tests fail before implementation, then pass.
- Full Dune suite is green.
- Timeout cleanup does not leave child processes running.
- Commit exactly: `feat: verify generated code with deterministic commands`.

## Task 5 — Production orchestration and CLI

### Dispatch prompt

You are implementing **Task 5 only** of the GigWerk Code Production MVP.

Objective: assemble the existing specification, graph, Actor, workspace, and verifier into one deterministic production run and expose it through the CLI.

Modify/create ONLY:
- `ocaml/lib/producer.ml`
- `ocaml/test/test_producer.ml`
- `ocaml/bin/main.ml`
- `ocaml/bin/dune`
- `fixtures/code-production.echo`

Required interfaces:
- `Producer.run : actor:(module Code_actor.S) -> specification:Specification.t -> workspace:string -> Producer.result`
- `Producer.result` records every requirement outcome, every produced artifact, every verification result, and the terminal status.
- CLI: `gigwerk produce <spec-file> --workspace <dir> --template <name>`.

Required production order:
1. Parse/read the specification before Actor execution.
2. Build the dependency graph.
3. Create the workspace.
4. Select only requirements returned by `Production_graph.ready`.
5. Invoke the Actor once per ready requirement.
6. Mark a requirement completed only after its Actor call succeeds.
7. Continue until no incomplete requirements remain or production fails.
8. Run verification only after required artifact generation is complete.
9. On first production failure, stop production but retain all prior artifacts/evidence.
10. Verification failure produces a failed terminal result; it never becomes success merely because generation succeeded.

CLI output MUST be machine-readable enough to identify terminal status, requirement IDs, artifact paths, and verification results. Do not build a general-purpose CLI framework.

Tests MUST cover: two requirements with dependency order; generated artifacts; verification after generation; invalid generated code causing failure; production Actor failure retaining prior evidence; missing template; malformed specification.

Do NOT modify booking/capability logic, store schema, GitHub integration, or any other CLI command behavior.

Definition of done:
- End-to-end tests fail before orchestration, then pass.
- `cd ocaml && dune test` passes.
- The checked-in fixture can be executed with the exact CLI command in the main plan.
- Commit exactly: `feat: add specification to verified code production loop`.

## Task 6 — Evidence trace and Learning boundary

### Dispatch prompt

You are implementing **Task 6 only** of the GigWerk Code Production MVP.

Objective: persist/serialize a deterministic production trace while preserving the explicit boundary that learning records evidence and outcomes but is not represented as a `model` abstraction.

Modify/create ONLY:
- `ocaml/lib/learning.ml`
- `ocaml/test/test_learning.ml`
- `ocaml/lib/producer.ml`
- `ocaml/lib/dune`

Required interfaces:
- `Learning.trace` contains specification digest, requirement outcomes, artifact digests, verification outcomes, and terminal status.
- `Learning.record : Learning.trace -> unit`
- `Learning.to_json : Learning.trace -> string`

Required semantics:
- Identical traces serialize identically byte-for-byte.
- Production failure remains failure in the trace.
- Partial traces are retained when production stops early.
- Artifact digests are computed from exact artifact contents.
- Specification digest is computed from exact specification input.
- JSON field ordering must be deterministic.
- There must be no field or type named `model` in this learning layer.
- The trace must not claim that verification was learned.
- Do not introduce a JSON dependency solely for this task; implement only the narrowly required encoder.
- Use existing `Digest` consistently unless repository constraints prove otherwise.

Tests MUST inspect exact serialized output for at least one fixture and compare two independently constructed identical traces for byte equality. Tests MUST prove that failed verification remains failed and that a partial production result remains partial/failed as appropriate.

Do NOT implement learning algorithms, prediction models, embeddings, inference, database persistence, or new abstractions unrelated to trace recording.

Definition of done:
- Tests fail before implementation, then pass.
- `cd ocaml && dune test` and the Task 5 CLI fixture are green.
- Commit exactly: `feat: record production and verification traces`.

## Task 7 — Final verification and documentation

### Dispatch prompt

You are implementing **Task 7 only** of the GigWerk Code Production MVP.

Objective: prove the complete MVP is executable and document exactly what it does and does not do.

Modify/create ONLY:
- `ocaml/README.md`
- `README.md`
- the final fixture documentation file(s) explicitly needed by the main plan, but do not modify implementation files.

Do NOT modify OCaml implementation code. If you find an implementation defect, report it rather than fixing it in this task.

Run:
- repository lint/verification commands already present in the repository
- `cd ocaml && dune build @all`
- `cd ocaml && dune test`
- valid production fixture command
- invalid production fixture command

Documentation MUST specify:
- exact specification grammar
- exact CLI invocation
- Actor interface boundary
- workspace confinement semantics
- dependency execution semantics
- verification semantics
- machine-readable production evidence
- deterministic template Actor limitation
- explicit statement that arbitrary code synthesis is NOT claimed by this MVP

Failure fixture must demonstrate that invalid generated code results in a non-success terminal status and retains verification evidence.

Definition of done:
- Every verification command and result is recorded in the task report.
- No implementation files were changed.
- Documentation matches actual behavior rather than planned behavior.
- Commit exactly: `docs: document verified code production MVP`.

## Reviewer contract for EVERY task

The reviewer must independently read the task brief, the implementation plan, and the resulting diff. Review against four questions:

1. Scope: did the implementation modify anything outside the task's allowed modification set?
2. Contract: do every required interface, semantic rule, and test requirement exist exactly as specified?
3. Regression: does `cd ocaml && dune test` remain green, and are new tests meaningful rather than vacuous?
4. Boundary integrity: did the task accidentally introduce a model abstraction, bypass the Actor/workspace/verifier boundary, weaken verification, or alter existing booking/capability behavior?

A reviewer must classify each finding as `blocking`, `non-blocking`, or `no finding`. A blocking finding requires a fix and scoped re-review. A non-blocking finding must not be used as an excuse to expand task scope.

A reviewer must never approve merely because the code looks plausible. The approval condition is: task contract satisfied + relevant tests pass + full suite passes + no unauthorized scope change.
