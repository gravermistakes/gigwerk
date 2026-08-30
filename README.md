# GigWerk

The agent books the gigs. The actors do the labor. The gate is a refusal to book.

Basic forms to start from. Schema is validated, constraints bite, views return
sensible rows against sample data.

```
sql/schema.sql          the component store — this IS the ECS, not storage for one
actor.template.yaml     annotated composition template
presets/critic.yaml     reads an artifact, emits a deterministic verdict
fixtures/echo.yaml      zero capabilities — runtime smoke test, not a preset
presets/researcher.yaml read-only
presets/fileworker.yaml side-effecting, human-gated
skill/SKILL.md          the composer skill the agent runs
```

## What a component is

**A typed row.** One table per component type, `entity_id` as key. A "system" is
a query with joins, so archetype lookups come free and write-ownership is
one-writer-per-table rather than a convention.

Three kinds, deliberately not merged:

- **data** — `c_inbox`, `c_state`, `c_budget`. Pure values. The only kind
  written at runtime. Budget is wall time, memory, message quota — *not* tokens.
  An actor is deterministic code; the booker is the only thing that spends
  tokens, and it spends them choosing what to book.
- **capability** — a *build instruction*, not a permission. At spawn the runtime
  constructs a record holding exactly the claimed tools; an unclaimed tool isn't
  denied, it's absent, so calling it is a compile error. `scope` is a constructor
  argument — `fs_read` is built around a directory handle with no parent
  reference, not a glob checked later.
- **policy** — a Prolog predicate name, by role and engine.

That split is the mutable-surface ceiling made mechanical: the harness composes,
it does not create. Enforced by a foreign key, not by a guideline — claiming a
nonexistent capability raises `IntegrityError`.

## Why SQLite is load-bearing, not incidental

Composition and outcome live in the same relational space, so Aleph can search
for rules over **shape**, not just over result. `v_aleph_facts` is already flat
and ILP-shaped: one row per gig with `n_caps`, `n_effectful`, `tier`,
`had_prediction`, `outcome`, `good`.

If components were YAML blobs and only the ledger were SQL, ILP could learn that
things failed but nothing about what shape produced the failure. That's the
whole reason to put the ECS in the database.

## YAML is seed and export. SQLite is truth.

One-way in (`import`), one-way out (`export`) for review. Never edit both — a
two-way file/DB sync rots, and the human needs a diffable artifact. A YAML diff
is reviewable; a sqlite page diff is not.

## The one model in the system

The composer is the only thing that calls a model. Gate is logic, actor is code,
critic is code. So the model's blast radius is exactly one decision — which
composition gets proposed — and every consequence of that decision is checked by
something deterministic. If you ever want an actor to "judge" something, you
want a critic with a real check or a booking policy, not a smarter actor.

## The open problem, stated plainly

Everything above is plumbing. The unsolved part is **what the fitness signal for
a composition actually is.**

For code patches the label is clean: did the fault recur. For a composition it
isn't. `gig_outcome` currently offers `completed | failed | human_rejected |
budget_exceeded | starved`, and `completed` is a weak proxy for *good* — an actor
can complete every gig badly. This is the weakest link in the design and no
amount of schema fixes it.

Honest expectation: the first ~100 gigs are labeling work, not learning. Aleph
needs at least 3 positives and gives you nothing trustworthy at 40 examples.
Resist wiring the learner early; the temptation to do so is how you end up
trusting a rule that memorised one bad week.

Two things that make the labeling cheaper when you get there:

1. **Log refusals.** `booking_verdict` keeps `refuse` rows. Most systems discard
   these, and they are the negative set — without them Aleph's closed-world
   assumption silently treats *unlabeled* as *bad*.
2. **Predict before running.** `gig_prediction` is a separate table written
   earlier than `gig_outcome`, with a required `falsifiable_by`. `matched`
   (`yes|partial|no`) is a cheaper and more honest label than any post-hoc
   quality score, because it was committed to in advance.

## Watch acceptance in both directions

`v_acceptance` — under ~0.2 the composer is thrashing. Over ~0.9 you have become
a rubber stamp, which is how HITL systems actually die. Approval fatigue, not bad
proposals.

## Not done yet

- The Elpi gate program. The seven checks are listed in `actor.template.yaml`;
  none are implemented.
- `gigwerk` CLI (`import` / `export` / `propose`).
- Restart disposition rules. Correctly *not* per-component fields — they're
  derived from `crash` facts. That table exists so the query has inputs; the
  rules don't exist yet. Closed-world default must be `reset`, since an entity
  that comes back holding the value that killed it crashes forever and reads as
  a bad patch rather than an architectural hole.
