# Code Production MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing GigWerk OCaml core into a minimal specification-to-code production loop whose generated artifact is compiled and tested against explicit requirements.

**Architecture:** Keep the existing Conditions → Obligations → Role → Actor booking boundary intact. Add a separate code-production domain: a specification is parsed into explicit requirements, requirements become deterministic implementation obligations, an `Actor` implementation produces source files through a narrow interface, and a verifier runs the project's compiler/tests while recording evidence. The first actor is intentionally deterministic and template-backed; no new model abstraction is introduced.

**Tech Stack:** OCaml, Dune, Opam, Unix, standard library only for the production path; Alcotest for tests only if already available, otherwise ordinary executable assertions. Generated projects are verified with Dune/OCaml toolchain commands.

**Spec:** Approved in-chat design on 2026-09-15: `Specification → Requirement → Design → Implementation → Verification`, deterministic requirement/dependency graph, filesystem workspace, Actor interface, compiler/test verification, machine-readable production record, explicit Learning boundary without treating learned artifacts as models.

## Global Constraints

- OCaml/Opam/Dune are the implementation substrate.
- Learning may record traces and outcomes; it is not represented as a `model` abstraction.
- The Actor is code and remains distinct from whatever mechanism supplies proposals.
- Verification is deterministic and external to the Actor's claims.
- A failed verification is an explicit production outcome, never silently accepted.
- Existing booking/capability boundaries remain load-bearing.
- SQLite remains the existing operational truth; this MVP does not replace it with YAML.
- YAGNI: no frontend, API bridge, new database migration, or external inference integration is part of this first code-production increment.

---

### Task 1: Establish the production domain types and specification parser

**Files:**
- Create: `ocaml/lib/production.ml`
- Create: `ocaml/lib/specification.ml`
- Create: `ocaml/test/test_specification.ml`
- Modify: `ocaml/lib/dune`

**Interfaces:**
- `Specification.parse : string -> (Specification.t, Specification.error) result`
- `Specification.requirements : Specification.t -> Specification.requirement list`
- `Production.requirement` with stable `id`, `statement`, `depends_on`, and `acceptance` fields.

- [ ] **Step 1: Write failing parser tests.**

Test a small line-oriented specification format with requirement IDs, statements, dependencies, and acceptance commands. Reject duplicate IDs and unknown dependencies.

```ocaml
let () =
  let src = "req echo : return the supplied message unchanged\naccept echo : dune test\n" in
  match Specification.parse src with
  | Error e -> failwith (Specification.error_to_string e)
  | Ok s ->
      assert (List.length (Specification.requirements s) = 1)
```

- [ ] **Step 2: Run the test and verify it fails.**

Run `cd ocaml && dune test` and require failure because `Specification` does not yet exist.

- [ ] **Step 3: Implement the minimal types/parser.**

Use a deterministic parser for `req <id> : <statement>`, optional `depends <id> : <id>,<id>`, and `accept <id> : <shell command>`. Preserve declaration order while validating dependency references.

- [ ] **Step 4: Run the tests.**

Run `cd ocaml && dune test`. Require the parser tests to pass and existing tests to remain green.

- [ ] **Step 5: Commit.**

```bash
git add ocaml/lib/production.ml ocaml/lib/specification.ml ocaml/test/test_specification.ml ocaml/lib/dune
git commit -m "feat: add specification and requirement domain"
```

### Task 2: Build the deterministic obligation graph

**Files:**
- Create: `ocaml/lib/production_graph.ml`
- Create: `ocaml/test/test_production_graph.ml`
- Modify: `ocaml/lib/dune`

**Interfaces:**
- `Production_graph.build : Specification.t -> (t, error) result`
- `Production_graph.roots : t -> Production.requirement list`
- `Production_graph.ready : t -> completed:string list -> Production.requirement list`

- [ ] **Step 1: Write failing graph tests.**

Test topological ordering, dependency blocking, stable ordering for independent requirements, and cycle rejection.

```ocaml
let () =
  let src = "req a : create value\nreq b : expose value\ndepends b : a\n" in
  let spec = Result.get_ok (Specification.parse src) in
  let graph = Result.get_ok (Production_graph.build spec) in
  let ready = Production_graph.ready graph ~completed:[] in
  assert (List.map (fun r -> r.Production.id) ready = ["a"])
```

- [ ] **Step 2: Run tests and verify failure.**

Run `cd ocaml && dune test` and require the graph tests to fail before implementation.

- [ ] **Step 3: Implement deterministic graph construction.**

Use adjacency lists and a stable topological sort. Return explicit cycle paths rather than relying on recursion failure.

- [ ] **Step 4: Run all tests.**

Run `cd ocaml && dune test` and require all graph and existing tests to pass.

- [ ] **Step 5: Commit.**

```bash
git add ocaml/lib/production_graph.ml ocaml/test/test_production_graph.ml ocaml/lib/dune
git commit -m "feat: add deterministic production obligation graph"
```

### Task 3: Add the filesystem workspace and Actor code-production interface

**Files:**
- Create: `ocaml/lib/workspace.ml`
- Create: `ocaml/lib/code_actor.ml`
- Create: `ocaml/lib/template_actor.ml`
- Create: `ocaml/test/test_code_actor.ml`
- Modify: `ocaml/lib/dune`

**Interfaces:**
- `Workspace.create : string -> (Workspace.t, error) result`
- `Workspace.write : Workspace.t -> path:string -> contents:string -> (unit, error) result`
- `Workspace.read : Workspace.t -> path:string -> (string, error) result`
- `Code_actor.S.produce : context -> requirement -> Workspace.t -> (Production.artifact, error) result`
- `Template_actor.create : templates:(string * string) list -> (module Code_actor.S)`

- [ ] **Step 1: Write failing Actor tests.**

Require an Actor to receive one requirement, write only within the supplied workspace, return an artifact containing its paths and requirement ID, and reject path traversal.

- [ ] **Step 2: Run tests and verify failure.**

Run `cd ocaml && dune test` and require failure because the workspace/Actor interfaces do not exist.

- [ ] **Step 3: Implement workspace confinement.**

Canonicalize the workspace root once, reject absolute paths and `..` components, create parent directories beneath the root, and return explicit errors for writes outside the workspace.

- [ ] **Step 4: Implement the Actor interface and deterministic template actor.**

The Actor receives immutable production context plus one requirement and may write source text supplied by the selected template. It does not execute the generated program and does not decide verification success.

- [ ] **Step 5: Run all tests.**

Run `cd ocaml && dune test`; require workspace confinement and Actor tests to pass.

- [ ] **Step 6: Commit.**

```bash
git add ocaml/lib/workspace.ml ocaml/lib/code_actor.ml ocaml/lib/template_actor.ml ocaml/test/test_code_actor.ml ocaml/lib/dune
git commit -m "feat: add confined code-producing actor interface"
```

### Task 4: Implement deterministic compiler/test verification

**Files:**
- Create: `ocaml/lib/verifier.ml`
- Create: `ocaml/test/test_verifier.ml`
- Modify: `ocaml/lib/dune`

**Interfaces:**
- `Verifier.verify : Workspace.t -> Specification.t -> Verification.t`
- `Verification.t` records command, exit status, stdout/stderr, and pass/fail status.

- [ ] **Step 1: Write failing verification tests.**

Create temporary valid and invalid Dune projects. Require valid source to pass, syntax/type errors to fail, and process exit status to be preserved.

- [ ] **Step 2: Run tests and verify failure.**

Run `cd ocaml && dune test` and require the verifier tests to fail before implementation.

- [ ] **Step 3: Implement subprocess verification.**

Run the exact acceptance commands declared by the specification from the workspace root, capture stdout/stderr separately, enforce a finite timeout, and return structured results. Do not parse success from textual output; use process exit status.

- [ ] **Step 4: Run all tests.**

Run `cd ocaml && dune test`; require valid and invalid fixtures to produce the expected structured results.

- [ ] **Step 5: Commit.**

```bash
git add ocaml/lib/verifier.ml ocaml/test/test_verifier.ml ocaml/lib/dune
git commit -m "feat: verify generated code with deterministic commands"
```

### Task 5: Assemble the production loop and CLI

**Files:**
- Create: `ocaml/lib/producer.ml`
- Create: `ocaml/test/test_producer.ml`
- Modify: `ocaml/bin/main.ml`
- Modify: `ocaml/bin/dune`

**Interfaces:**
- `Producer.run : actor:(module Code_actor.S) -> specification:Specification.t -> workspace:string -> Producer.result`
- `Producer.result` records every requirement, produced artifact, verification result, and terminal status.
- CLI command: `gigwerk produce <spec-file> --workspace <dir> --template <name>`.

- [ ] **Step 1: Write failing end-to-end tests.**

Use a specification with two requirements and a deterministic template Actor. Require the dependency order to be respected, artifacts to be generated, verification to run after generation, and the result to fail when generated code is invalid.

- [ ] **Step 2: Run tests and verify failure.**

Run `cd ocaml && dune test` and require the end-to-end tests to fail before orchestration exists.

- [ ] **Step 3: Implement orchestration.**

Build the graph, create the workspace, repeatedly select ready requirements, call the Actor, record artifacts, run verification after all required artifacts exist, and return a terminal result. Stop on the first production error and retain prior evidence.

- [ ] **Step 4: Add the CLI command.**

Parse `produce`, read the specification file, create the selected deterministic template Actor, invoke `Producer.run`, and print a concise machine-readable summary including terminal status, requirement IDs, artifact paths, and verification status.

- [ ] **Step 5: Run end-to-end tests.**

Run `cd ocaml && dune test` and then exercise `dune exec gigwerk -- produce fixtures/code-production.echo --workspace _build/gigwerk-run --template echo` against a checked-in fixture.

- [ ] **Step 6: Commit.**

```bash
git add ocaml/lib/producer.ml ocaml/test/test_producer.ml ocaml/bin/main.ml ocaml/bin/dune fixtures
git commit -m "feat: add specification to verified code production loop"
```

### Task 6: Record production evidence without introducing a model abstraction

**Files:**
- Create: `ocaml/lib/learning.ml`
- Create: `ocaml/test/test_learning.ml`
- Modify: `ocaml/lib/producer.ml`
- Modify: `ocaml/lib/dune`

**Interfaces:**
- `Learning.trace` contains specification digest, requirement outcomes, artifact digests, verification outcomes, and terminal status.
- `Learning.record : trace -> unit`
- `Learning.to_json : trace -> string`

- [ ] **Step 1: Write failing evidence tests.**

Require stable serialization for identical traces and explicit representation of production failure. Verify that the trace contains no field named `model` and does not imply that verification was learned.

- [ ] **Step 2: Run tests and verify failure.**

Run `cd ocaml && dune test` and require the evidence tests to fail before implementation.

- [ ] **Step 3: Implement trace recording.**

Use deterministic SHA-256-equivalent digesting already available in the standard environment where practical; otherwise use the existing `Digest` primitive consistently with current code. Serialize a stable JSON object using a minimal local encoder rather than adding a broad dependency solely for this record.

- [ ] **Step 4: Attach traces to production results.**

`Producer.run` must produce a trace before returning, including partial traces on failure. Recording must never convert a failed production into success.

- [ ] **Step 5: Run the complete OCaml test suite.**

Run `cd ocaml && dune test` and the CLI fixture. Require all tests to pass.

- [ ] **Step 6: Commit.**

```bash
git add ocaml/lib/learning.ml ocaml/test/test_learning.ml ocaml/lib/producer.ml ocaml/lib/dune
 git commit -m "feat: record production and verification traces"
```

### Task 7: Final verification and review artifact

**Files:**
- Create: `fixtures/code-production.echo`
- Modify: `ocaml/README.md`
- Modify: `README.md`

- [ ] **Step 1: Run formatting/static checks.**

Run the repository's existing lint/verification commands and `cd ocaml && dune build @all`.

- [ ] **Step 2: Run the complete test suite.**

Run `cd ocaml && dune test` and the production fixture command.

- [ ] **Step 3: Verify failure evidence.**

Run the invalid fixture and require a non-success terminal result plus a retained verification failure record.

- [ ] **Step 4: Document the executable MVP.**

Document the specification grammar, CLI invocation, Actor interface, workspace boundary, and verification semantics. Explicitly state that the deterministic template Actor is the first implementation mechanism and that arbitrary code synthesis is a later Actor implementation, not something faked by the MVP.

- [ ] **Step 5: Commit.**

```bash
git add fixtures/code-production.echo ocaml/README.md README.md
git commit -m "docs: document verified code production MVP"
```
