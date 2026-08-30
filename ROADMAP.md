# GigWerk — five phases to a harness you can use

Ordering rule: **every phase ends in something usable on its own.** No phase
exists only to enable the next one. If a phase's deliverable is "now the next
layer is possible," it's mis-cut.

Second rule: **the hardest unknown goes first.** Object-capability across a
process boundary is the one thing in this design that could turn out not to
work as described. It lands in Phase 1, not Phase 4.

---

## Phase 0 — the format correction (an hour, do it first)

Not a real phase, but it blocks everything.

YAML has no reader in your stack. SWI doesn't ship one; sqlite has none; only
OCaml has bindings. Keeping YAML makes OCaml a prerequisite for anything to
turn at all.

- Composition format becomes **JSON**. `sqlite3` has `json_extract` built in,
  SWI has `library(http/json)` in core, OCaml has `yojson`. All three read it
  with zero new dependencies.
- Keep the annotated YAML files as **documentation** — they're doing real work
  explaining the three component kinds. They stop being inputs.
- `presets/*.json` become the inputs.

Cost, stated plainly: no comments in the seed files.

---

## Phase 1 — one actor runs, hand-authored, end to end

**Usable as:** a capability-scoped task runner. Useful before any AI touches it.

```
gigwerk run echo   --message "hello"     # zero capabilities
gigwerk run critic --artifact ./out.txt  # reads, emits a verdict row
```

Build:
- OCaml + Eio. `dune` project, `gigwerk` executable.
- Read a composition from sqlite, construct the capability record, spawn,
  deliver one message, step, write `gig` + `gig_outcome`.
- Capability constructors for real: `fs_read`, `sqlite_query`. Two is enough.
- The `echo` fixture first — it proves delivery/step/outcome without tools.

**The hard part, and the reason this is Phase 1.** A directory handle cannot
cross a process boundary as a value. So ocap has two shapes:

- *in-process actors* get the real `Eio.Path.t`. Genuine ocap.
- *subprocess actors* cannot. The child must either receive an **fd passed over
  a unix socket** (`SCM_RIGHTS`), or **re-derive** the handle from the scope
  string under a Landlock ruleset applied before exec.

Decide this in Phase 1 by writing it, not by reasoning about it. If fd-passing
works, ocap holds across the boundary and the design is intact. If you fall
back to re-derivation, then for subprocess actors the enforcement is Landlock
rather than the handle — which is still strong, but it is a *different claim*
than the one in the schema comments, and the comments need correcting.

**Done when:** `echo` and `critic` both run, write outcome rows, and a
capability the composition didn't claim is a compile error in the actor's
behavior — demonstrated by trying it and failing to build.

---

## Phase 2 — the gate refuses things

**Usable as:** the difference between a task runner and a harness. Something
can now say no.

```
gigwerk propose ./composition.json     # book | queue | refuse + reasons
```

Build:
- Elpi embedded via `Elpi.API`. Start by **exporting facts as Elpi clauses**
  (same pattern as `sql/export_facts.sql` feeding SWI) rather than writing
  builtins — FFI can wait.
- The seven checks from `actor.template.yaml`. In priority order, because they
  are not equally valuable:
  1. every claimed capability exists *(SQL foreign key already does this — the
     Elpi version is for the error message)*
  2. **every scope narrows, never widens** ← the one that matters
  3. `state.shape` resolves to a real Elpi type ← where HOAS earns its keep
  4. no two systems own write on the same component
  5. `provenance=agent` ⇒ `tier=subprocess`
  6. `requires_booking` ⇒ a human verdict row exists
  7. `composition_sig` not in the refused set
- Scope-narrowing must run **before construction**. After construction there's
  nothing left to widen, so the check has no subject.

**Done when:** a composition that widens a scope is refused with a reason
naming the capability and both envelopes, and the refusal is a row in
`booking_verdict`.

---

## Phase 3 — the loop closes

**Usable as:** the actual harness. Your review becomes confidence; confidence
buys back your attention.

```
gigwerk queue                  # what's waiting on you
gigwerk review <gig>           # your verdict; writes form_review
gigwerk forms                  # C / B / A bands per form
```

Build:
- Wire the composer skill to `gigwerk propose`. The skill exists; the CLI it
  calls doesn't yet.
- Review queue as a real surface, not an implied one.
- `prolog/confidence.pl` already computes the bands — connect it to booking so
  A-band forms auto-book and C-band forms stop.
- Feedback module: `gig_outcome` + `form_review` written on every gig close,
  including crashes and budget kills.

**Done when:** a form you've reviewed 12+ times auto-books without asking you,
and a form that starts failing drops out of auto-book inside 15 gigs.

This is the phase where the ~100 reviews of runway start accruing. It can't
start earlier and shouldn't start later.

---

## Phase 4 — the judge, and critics per language

**Usable as:** confidence you can trust rather than confidence you hope in.

Build:
- Adversarial judge as a **second model**, separate from the composer. Two
  disciplines make it work rather than being a second opinion in name:
  it sees **artifact and outcome only, never the composer's justification**,
  and its prior is **refuted-under-uncertainty** so ties kill.
- Per-language linters behind one interface: `(source, before) → verdict +
  reasons`. You already have the Lisp one — `gate.lisp` from the SBCL build is
  exactly this shape. OCaml gets the compiler. Python gets ruff plus an AST walk.
- `judge_refuted` already burns a confidence slot in `confidence.pl`. Decide
  then whether a refutation should also *veto* autopass outright — stronger,
  but one aggressive refutation then costs 15 gigs of runway.

**Done when:** a composition that passes the gate and completes its gig is
still held out of A-band because the judge refuted it.

---

## Phase 5 — Aleph

**Usable as:** the system proposing its own booking rules. Last, and gated on
data existing.

Build:
- Mode declarations over `gig_result/8` — already flat and ILP-shaped in
  `export_facts.sql`.
- Induced rules → your review → gate logic. **Never** Aleph → gate directly;
  that closes the loop on itself.

**Do not start this before ~100 labeled gigs exist.** Aleph wants 3 positives
minimum and gives you nothing trustworthy at 40 examples. The temptation to
wire it early is how you end up trusting a rule that memorised one bad week.

**Done when:** a rule Aleph induced, that you approved, changes a booking
decision you can point at.

---

## What's already done

- `sql/schema.sql` — store, constraints bite, views return sane rows
- `prolog/confidence.pl` — three-band rule, 10/10 plunit
- `sql/test_confidence.sql` — same rule in SQL, 10/10, independent check
- `sql/export_facts.sql` — sqlite → Prolog facts, the one door both readers use

## Where the risk actually is

Not in phases 3–5. Those are wiring, and the shapes are settled.

Phase 1's fd-passing question is the one that could force a design change, and
Phase 2's scope-narrowing check is the one that everything else's safety rests
on. If both land, the rest is construction.
