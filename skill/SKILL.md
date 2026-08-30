---
name: compose-actor
description: >
  Compose a GigWerk actor from components and submit it for booking. Use when
  asked to build, add, spawn, or modify an actor/worker/entity, or when a gig
  needs a shape no existing actor has. Composes from the frozen capability
  table only — never authors capabilities or behavior. Triggers: "make an
  actor", "compose a worker", "spawn an entity", "give X read access",
  "what should handle this gig", "gigwerk".
---

# compose-actor

**You are the only model in this system.** The actors are not. An actor is
deterministic code with a message handler — it does not reason, does not call a
model, and has no token budget. You spend tokens deciding what to book; the
actor spends wall time doing it.

Which means your entire blast radius is one thing: **which composition gets
proposed.** Everything downstream is deterministic — the gate is logic, the
actor is code, the critic is code. Keep it that way. If you find yourself
wanting an actor to "decide" or "judge" something, you want either a critic with
a deterministic check or a booking policy, not a smarter actor.

## Capabilities are values, not permissions

A capability row is a **build instruction**. At spawn the runtime constructs a
record holding exactly the claimed tools and hands it to the actor's behavior.
A tool you don't list is not denied — it is absent. Calling it fails to compile.

So there is no runtime check to reason about, and two things follow:

- **You cannot grant a capability that isn't in `capability`.** Not "shouldn't" —
  the foreign key refuses it. If a gig needs a tool that isn't there, say so and
  stop. That request goes to a human.
- **`scope` is a constructor argument.** `fs_read` scoped to
  `/srv/gigwerk/work` is built around a directory handle rooted there with no
  parent reference. You are not writing a pattern that gets matched later; you
  are choosing what the actor will physically hold.

## Order of operations

**1. Read what exists before proposing.**

```bash
sqlite3 gigwerk.db "SELECT name, envelope, side_effecting, requires_booking FROM capability;"
sqlite3 gigwerk.db "SELECT * FROM v_archetype;"
```

An actor that already has the shape is a better answer than a new one. Reuse
before compose; compose before request.

**2. Ask what happened last time.**

```bash
sqlite3 gigwerk.db "
  SELECT shape, n_caps, n_effectful, outcome, count(*) AS n
  FROM v_aleph_facts GROUP BY shape, outcome ORDER BY n DESC LIMIT 20;"
sqlite3 gigwerk.db "
  SELECT composition_sig, reasons FROM booking_verdict
  WHERE decision = 'refuse' ORDER BY decided_at DESC LIMIT 20;"
```

A composition in the refused set does not get reproposed under a new name. If
yours is close to a refused one, name it and say what differs — that sentence is
the whole justification.

**3. Start from the nearest preset, then subtract.**

`presets/critic.yaml` (reads, verdicts), `presets/researcher.yaml` (read-only),
`presets/fileworker.yaml` (side-effecting, human-gated). Subtracting from a
working shape beats adding to an empty one. `fixtures/echo.yaml` is the only
correct zero-capability actor and it is a runtime test, not a starting point.

**4. Claim the fewest tools that can do the job, scoped as narrowly as possible.**

If you want an unnarrowed envelope, the actor is too broad — propose two actors
and let the booker route between them.

**5. Write the prediction before submitting.**

Every proposal carries `predicts` and `falsifiable_by`. Not intent — a statement
some specific later observation could contradict. "Completes dedupe gigs inside
budget; falsified if `budget_exceeded` twice in ten gigs." If you can't write the
falsifier you don't understand the actor well enough to propose it.

**6. Submit. Do not install.**

```bash
gigwerk propose actor.yaml     # writes booking_verdict; does not spawn
```

Elpi returns `book` / `queue` / `refuse`. If refused, revise once. If the second
attempt is refused for the same reason, stop and escalate — iterating against a
gate you don't understand is how the queue fills with noise.

## provenance is always `agent`

You may not write `human`. Not a formality: provenance selects the labor tier,
so `agent` puts the actor in a subprocess, and that boundary is what stands
between a bad composition and the runtime.

## Refuse the request yourself when

- The job needs a tool not in `capability` → escalate, don't improvise.
- The job needs an unnarrowed envelope → propose a split.
- An equivalent composition is refused and you can't say what differs → no.
- The job wants the actor to *reason* → it wants a policy or a critic instead.
- `v_acceptance` shows a human rate above 0.9 → say so before proposing. A
  rubber-stamp queue means nobody is reading, and adding to it makes it worse.

## Write access

| Table | Access |
|---|---|
| `entity` (provenance='agent') | insert |
| `c_inbox`, `c_state`, `c_budget` | insert, update |
| `c_capability`, `c_policy` | insert (claims only) |
| `capability`, `component_owner` | **never** |
| any `provenance='human'` row | **never** |
| `gig_prediction` | insert, before the gig runs |
| `gig_outcome`, `booking_verdict` | **never** — the runtime writes these |
