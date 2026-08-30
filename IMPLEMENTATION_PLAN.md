# GigWerk Android APK Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a standalone Android APK with a Svelte frontend and GigWerk’s OCaml internals compiled and running on-device, with deterministic programming-agent execution, adaptive API throttling, GitHub integration, per-repository write toggles, and complete linting and verification.

**Architecture:** Use a Capacitor-hosted Svelte/TypeScript frontend inside a Kotlin Android shell. Compile the existing OCaml 4.14/Dune core to Android ARM64 native code, expose only a narrow C ABI, and call it through a Kotlin native plugin. Keep the component/ECS and ledger model in SQLite, enforce repository write policy in the native/OCaml path, and make every write action reviewable and explicitly approved.

**Tech Stack:** Svelte 5, TypeScript, Vite, Capacitor, Kotlin, Android SDK/NDK, C ABI/JNI, OCaml 4.14, Dune, SQLite, GitHub REST/Git transport, ESLint, Prettier, svelte-check, Android Lint, OCamlformat, Alcotest/QCheck where practical, and Gradle.

---

### Task 1: Provision and pin the native build toolchain

**Files:**
- Create: `toolchain/README.md`
- Create: `android/gradle/libs.versions.toml`
- Create: `Makefile`
- Modify: `ocaml/dune-project`

**Step 1: Write the failing environment check.**

Create a `make doctor` target that checks Java, Gradle wrapper, Android SDK/NDK, OCaml, Dune, Opam, Node, and npm versions and exits non-zero when a required tool is unavailable.

**Step 2: Run the check and record the expected failures.**

Run `make doctor`. The current clean environment is expected to report missing Android SDK/NDK and OCaml/Dune/Opam.

**Step 3: Provision the toolchain.**

Install or download reproducible local toolchains, pin Android API/NDK versions, pin OCaml/Dune versions, and add documented setup commands without storing credentials.

**Step 4: Re-run the check.**

Run `make doctor` and require a zero exit status with all required versions printed.

**Step 5: Commit.**

```bash
git add toolchain android Makefile ocaml/dune-project
git commit -m "build: pin Android and OCaml toolchains"
```

### Task 2: Add the Svelte and Capacitor Android shell

**Files:**
- Create: `frontend/package.json`
- Create: `frontend/src/`
- Create: `frontend/index.html`
- Create: `android/`
- Create: `capacitor.config.ts`

**Step 1: Write the failing frontend smoke test.**

Add a Playwright test that loads the app at a phone viewport and expects a visible GigWerk home surface with navigation to Projects, Actors, Queue, and Verification.

**Step 2: Run the test.**

Run the frontend test and confirm it fails because the Svelte app does not yet exist.

**Step 3: Implement the minimal shell.**

Create a Svelte mobile-first shell with safe-area padding, keyboard-safe forms, bottom navigation, project context, and an error boundary. Configure Capacitor for an Android application ID and local web assets.

**Step 4: Run the smoke test.**

Run the Playwright test at 360x800 and 412x915. Require no horizontal overflow and visible touch targets.

**Step 5: Commit.**

```bash
git add frontend android capacitor.config.ts
git commit -m "feat: add Svelte Capacitor Android shell"
```

### Task 3: Preserve and expose the OCaml core through a narrow ABI

**Files:**
- Modify: `ocaml/lib/bridge.ml`
- Modify: `ocaml/lib/caps_stubs.c`
- Create: `native/include/gigwerk_api.h`
- Create: `native/gigwerk_api.c`
- Create: `android/app/src/main/cpp/CMakeLists.txt`
- Create: `android/app/src/main/java/im/gigwerk/core/GigWerkPlugin.kt`

**Step 1: Write ABI contract tests.**

Test JSON requests for health, list capabilities, compose actor, evaluate booking, create prediction, execute deterministic actor, inspect outcome, and read verification events. Test malformed JSON, unknown operations, and capability violations.

**Step 2: Run the tests and confirm failure.**

Run the native/OCaml tests before the bridge exists and confirm the expected missing-symbol failures.

**Step 3: Implement the ABI.**

Keep the OCaml modules as the source of truth. Add a stable C ABI with explicit allocation/free functions, bounded input sizes, structured error codes, and no direct filesystem path acceptance from the frontend. Compile the OCaml library for ARM64 and link it through the Android NDK. Expose the ABI through a Capacitor plugin that returns JSON-safe results.

**Step 4: Run unit and bridge tests.**

Run Dune tests, C ABI tests, and Android JVM/native tests. Require deterministic results for identical inputs.

**Step 5: Commit.**

```bash
git add ocaml native android
 git commit -m "feat: embed GigWerk OCaml core behind native ABI"
```

### Task 4: Implement the operational gate, budgets, and deterministic actors

**Files:**
- Modify: `ocaml/lib/booking.ml`
- Modify: `ocaml/lib/actor.ml`
- Modify: `ocaml/lib/conditions.ml`
- Modify: `ocaml/lib/store.ml`
- Modify: `sql/schema.sql`
- Create: `sql/migrations/0002_operational_gate.sql`
- Create: `ocaml/test/test_gate.ml`

**Step 1: Write failing tests.**

Cover missing capabilities, broad scopes, side-effecting actors without approval, budget exhaustion, repeated refusal, prediction-before-run, provenance rules, and project-specific GitHub write policy.

**Step 2: Run tests and confirm failure.**

Run `dune test` and verify the new gate tests fail against the Phase 1 runner.

**Step 3: Implement the minimum complete gate.**

Add deterministic checks for capability existence, least privilege, scoped paths, budget limits, prediction/falsifier presence, human approval, and refusal logging. Add durable ledger rows for booking verdicts, predictions, outcomes, approvals, and verification events.

**Step 4: Run tests and fixtures.**

Run all OCaml tests plus fixture runs for echo, critic, researcher, and fileworker. Require refusals to be recorded and never silently converted into bookings.

**Step 5: Commit.**

```bash
git add ocaml sql
git commit -m "feat: enforce operational booking gates and budgets"
```

### Task 5: Add per-repository GitHub policy and explicit write approval

**Files:**
- Create: `frontend/src/lib/github/`
- Create: `frontend/src/routes/projects/ProjectPolicy.svelte`
- Create: `native/github_policy.c`
- Modify: `ocaml/lib/grants.ml`
- Modify: `sql/schema.sql`

**Step 1: Write failing policy tests.**

Test that each repository has an independent `write_actions` flag defaulting to false; reads remain available when writes are disabled; all write classes are denied when disabled; enabling the flag still requires per-operation approval; and a policy cannot be bypassed by calling the bridge directly.

**Step 2: Run tests and confirm failure.**

Run native, OCaml, and frontend tests against the unimplemented policy.

**Step 3: Implement the policy.**

Add project records keyed by repository identity, secure OAuth/PKCE token storage using Android Keystore-backed encryption, read-only GitHub operations, and guarded write operations for commits, branches, pull requests, issues, and file changes. Every write generates a diff/intent record, requires explicit approval, and is then rechecked by the native gate immediately before execution.

**Step 4: Run policy tests.**

Verify cross-repository isolation, toggle persistence, token redaction, approval expiry, and denial behavior while offline or rate-limited.

**Step 5: Commit.**

```bash
git add frontend native ocaml sql
git commit -m "feat: add per-repository GitHub write controls"
```

### Task 6: Implement adaptive throttle-conscious API access

**Files:**
- Create: `frontend/src/lib/throttle/AdaptiveThrottle.ts`
- Create: `native/throttle_policy.c`
- Create: `ocaml/lib/throttle.ml`
- Create: `ocaml/test/test_throttle.ml`

**Step 1: Write failing throttle tests.**

Cover token-bucket admission, concurrency caps, `Retry-After`, GitHub rate-limit headers, exponential backoff with jitter, request coalescing, offline queueing, cancellation, and bounded retry counts.

**Step 2: Run tests and confirm failure.**

Run the throttle test suite before implementation.

**Step 3: Implement the throttle.**

Use per-provider and per-repository budgets, adaptive refill based on observed headers and latency, bounded exponential backoff, idempotency keys for safe retries, and visible queue state. Never retry non-idempotent writes automatically.

**Step 4: Run deterministic and timing-tolerant tests.**

Use a fake clock and fake transport. Require no request storm after a rate-limit response and ensure queued writes remain approval-gated.

**Step 5: Commit.**

```bash
git add frontend native ocaml
git commit -m "feat: add adaptive API throttling"
```

### Task 7: Build the programming-agent operator UI

**Files:**
- Create: `frontend/src/routes/Projects.svelte`
- Create: `frontend/src/routes/Actors.svelte`
- Create: `frontend/src/routes/Queue.svelte`
- Create: `frontend/src/routes/Verification.svelte`
- Create: `frontend/src/components/`
- Create: `frontend/src/lib/stores/`

**Step 1: Write interaction tests.**

Test actor composition, capability selection, falsifiable prediction entry, booking refusal display, approval flow, repository toggle flow, queue pause/resume, and outcome inspection.

**Step 2: Implement the screens.**

Build a high-density but mobile-readable interface with project-scoped policy, actor cards, gate explanations, diff review, logs, budget meters, throttle status, and deterministic verification history.

**Step 3: Run interaction tests.**

Run Playwright tests at phone sizes and keyboard navigation. Require all destructive/write actions to have a confirmation step and clear current repository context.

**Step 4: Commit.**

```bash
git add frontend
 git commit -m "feat: add GigWerk programming-agent operator UI"
```

### Task 8: Complete linting, analysis, and verification architecture

**Files:**
- Create: `frontend/eslint.config.js`
- Create: `frontend/.prettierrc`
- Create: `.editorconfig`
- Create: `ocaml/.ocamlformat`
- Create: `scripts/verify.sh`
- Create: `.github/workflows/verify.yml`
- Modify: `Makefile`

**Step 1: Add failing quality gates.**

Make verification fail on TypeScript errors, Svelte errors, lint violations, formatting drift, unsafe `any`, unhandled native errors, OCaml warnings-as-errors, missing tests, Android lint errors, ABI drift, and forbidden direct GitHub writes outside the policy module.

**Step 2: Run the gates and catalog failures.**

Run `./scripts/verify.sh` and capture failures by layer.

**Step 3: Implement the gates.**

Add frontend lint/type/format checks, OCaml formatting and Dune checks, C compiler warnings-as-errors, Android Lint, unit/property tests, ABI contract snapshots, dependency audit, secret scanning, and APK manifest checks. Add CI ordering so cheap static checks run before native builds.

**Step 4: Run the complete verification suite.**

Require `./scripts/verify.sh` to pass locally and in CI. Produce a machine-readable report under `artifacts/verification/` without including credentials.

**Step 5: Commit.**

```bash
git add .github scripts Makefile frontend ocaml android native
git commit -m "test: add complete lint and verification architecture"
```

### Task 9: Build and validate the APK

**Files:**
- Create: `artifacts/verification/README.md`
- Create: `docs/architecture.md`
- Create: `docs/security-model.md`
- Create: `docs/build-apk.md`

**Step 1: Run the full verification suite.**

Run `./scripts/verify.sh`, `./gradlew assembleDebug`, and native smoke tests.

**Step 2: Install and smoke test on an Android emulator or connected device.**

Verify cold start, offline mode, database migration, OCaml core health, actor execution, refusal, GitHub read, disabled write, enabled write with approval, rate-limit backoff, process restart recovery, and log redaction.

**Step 3: Inspect the APK.**

Check ABI splits, permissions, exported components, debug/release signing mode, embedded assets, native libraries, and absence of secrets.

**Step 4: Commit documentation and verification artifacts.**

```bash
git add docs artifacts
 git commit -m "docs: document GigWerk APK architecture and verification"
```

**Step 5: Deliver.**

Provide the debug APK, source archive, reproducible build instructions, verification report, and known limitations. Clearly distinguish a verified APK from source-only output if an emulator or Android SDK remains unavailable.

---

## Execution Notes

The implementation must preserve the workshop’s central invariant: the composer proposes; the gate decides; the actor executes deterministic code; the critic checks outcomes; and the ledger records evidence. A Svelte control can request an operation, but it cannot grant itself capabilities or bypass project policy. GitHub write actions are independent per repository, disabled by default, and always require an explicit approval event even when the repository toggle is enabled.

The project should be built in small commits, with tests preceding each implementation slice. The first implementation checkpoint is toolchain provisioning because the current environment does not contain the Android SDK/NDK or OCaml/Dune toolchain required to produce a verifiable APK.
