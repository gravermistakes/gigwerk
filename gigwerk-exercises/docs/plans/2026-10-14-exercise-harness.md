# OCaml Exercise Harness Implementation Plan

> Execute the tasks in dependency order; test-first for every new shared component.

**Goal:** Make the linked 87-exercise catalogue a truthful contract-to-OCaml benchmark for GigWerk's model-free production actor.

**Architecture:** Independent setup workers derive solution-blind requirements, contracts and tests. Synquid constructs candidates within bounded execution. A shared OCaml syntax backend lowers generated terms without exercise algorithms; a batch runner compiles and tests them, preserving explicit incomplete statuses.

**Tech stack:** Pinned Synquid 0.4 runtime, OCaml 4.14, standard-library-only OCaml backend, Python standard-library orchestration, canonical ocaml.org source snapshot.

## 1. Catalogue contracts and independent tests

- Exactly one worker for each of the 87 published source files; one reviewer over all item artifacts.
- Keep published solution bodies quarantined.
- Preserve full semantics, including order, multiplicity, exact interfaces and all required result sets.
- Partial contracts, unsupported language/runtime features and timeouts remain explicit.
- Never use an answer implementation as a synthesis component.

## 2. Shared term backend

Files: `backend/synquid_backend.ml`, `backend/test_backend.ml`, `backend/main.ml`.

- Write failing tests for generic lambdas, numeric/Boolean literals, application, builtin list/option/pair constructors, nested layout matches, conditionals and lets.
- Compile/run the tests and record red evidence before implementation.
- Parse the observed upstream output grammar into an AST. Validate lexical scope and constructor arity.
- Emit OCaml without substituting algorithms or simplifying conditions. Match the original OCaml interfaces at the module boundary.
- Reject unsupported/hole/error terms. Preserve explicit primitive/component declarations.
- Re-run backend tests and the previous BST semantic test before continuing.

## 3. Bounded catalogue runner

Files: `scripts/verify_catalogue.py`, `results.json`, `RESULTS.md`.

- Write failing tests for status transitions, refusal to mark partial specifications fulfilled, and separate compiler/runtime failures.
- For each item, use only actual captured synthesis output. Normalize declared interfaces/types/components, lower, compile and run independent OCaml tests with timeouts.
- Record: contract status, specification strength, synthesis exit/status, lowering status, compiler status and semantic-test status.
- Fulfilled requires all relevant gates; a candidate is not fulfillment. Missing item artifacts remain missing, not silently dropped.
- Use one bounded-concurrency script for deterministic per-item command execution.

## 4. Verification and correction

- Correct shared infrastructure failures through failing regression tests.
- Reattempt only justified contract/tool failures, not endless timeout extension.
- Validate candidate semantics against tests independent of synthesis input, and retain negative controls.
- Include all 87 target items in the final coverage report, including blocked or unsolved ones.

## 5. Delivery

Package source contracts, generated OCaml, backend, tests, provenance and measured results. Exclude the large runtime image and host build caches. Deliver an honest coverage count and reusable local runner. Do not claim arbitrary-code generation, complete catalogue fulfillment, APK integration or Android execution unless actually verified.
