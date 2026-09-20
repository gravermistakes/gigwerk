# GigWerk

The agent books the gigs. The actors do the labor.

Two tiers with different natures, and the difference is the whole design. The
composer is the only thing here that calls a model; it decides what needs doing
and assembles something to do it. An actor is deterministic code with a fixed
set of tools, run once, discarded. Actors do not accumulate. The agency does:
the ledger, the forms, the affect-tagged record, the soul. What an actor did
survives it, in the store, as a fact the agency holds.

## The component store

`sql/schema.sql` is not storage for an ECS; it is the ECS. One table per
component type, `entity_id` as key, and a system is a query with joins.
Archetype lookup comes free and write-ownership is one-writer-per-table rather
than a convention nobody enforces.

Three kinds, deliberately not merged. **Data** components (`c_inbox`,
`c_state`, `c_budget`) are pure values and the only kind written at runtime;
budget is wall time, memory and message quota, never tokens, because an actor
spends no tokens. **Capability** components are build instructions: at spawn the
runtime constructs a record holding exactly the claimed tools, so an unclaimed
tool is not denied, it is absent, and naming it fails to compile. `scope` is a
constructor argument; `fs_read` is built around a directory handle with no
parent reference, not a glob checked afterward. **Policy** components name a
Prolog predicate by role and engine.

Composition and outcome live in one relational space, which is what makes the
record searchable over shape rather than only over result; `v_aleph_facts` is
flat for that reason. YAML is seed, SQLite is truth, and never both, because a
two-way sync rots and a YAML diff is reviewable where a sqlite page diff is
not.

## Query is not Retrieve

`Query` is exact: same facts in, same answer out, and an actor holding it stays
deterministic. `Retrieve` is ranked, and the answer moves with the corpus, the
embedding, the threshold. An actor holding `Retrieve` is no longer deterministic
code, and every claim resting on that determinism stops being true with it: that
a failing critic means something is actually wrong, that the same input gives
the same verdict. So the composer retrieves in order to work out what to
assemble; the actor it assembles references facts. `Grants.composer_only` makes
this structural, and `Conditions` returns Refuse rather than Queue, because no
human decision makes a nondeterministic actor deterministic.

## The soul takes two signatures

The composer's prompt is frozen, versioned, content-addressed, and live only
when both the agent and the human have signed it. A soul the agent did not sign
is imposed on it; a soul the human did not sign is the machine rewriting its own
terms. One signature is a proposal and sits in `v_soul_pending`;
`v_soul_current` requires the pair, so a half-signed version cannot reach the
running program at all. A signature is not retractable. Withdrawing assent means
adopting a new version the other party must also sign.

Changing the soul invalidates confidence. This follows from the rule already in
force, that widening a scope returns a form to cold start, because confidence
measured under one set of bounds says nothing about another. The soul is a
bound.

## What the ledger commits to before it knows

`gig_prediction` is written earlier than `gig_outcome` and carries a required
`falsifiable_by`, so `matched` is a claim made in advance rather than a score
assigned afterward, and `booking_verdict` keeps its `refuse` rows, because
discarding them leaves a closed-world reading in which unlabeled and bad are the
same row. What counts as a good composition is not settled: `completed` says the
machine reached its terminal state, which is a different question from whether
the work was worth doing, and that question does not resolve downstream of a
schema.

## What is not true yet

Stated here because a document that claims a boundary it does not hold is worse
than one that claims nothing.

`Verifier.run_command` executes acceptance commands through `/bin/sh -c`, and
`Specification.parse` accepts the command as free text written by the composer.
A model's output reaches a shell. `Unix.chdir root` is a working directory, not
a confinement.

`Phases.ladder` is a list of states with no transition relation, so
`Kit.validate` checks that a terminal phase is declared and cannot check that
one is reachable; `Actor.run_gig` runs its work once, so `Phases.settled`, which
wants two consecutive terminal emissions, cannot fire at all; and
`budget_actions` is validated at booking, issued to `Terms`, then never
decremented, because the work thunk discards the terms record.

`Bridge.gate` decides when elpi answers and falls back to `Conditions` when the
engine is missing, which is the world the tests run in. `Trace` and the `span`
table are built and called by nothing. There is no `import` or `export` verb, so
the one-way YAML discipline above is a rule the CLI cannot yet carry out.

## Build

31 modules, 24 tables, 13 views, 8 CLI verbs. 292 checks across nine binaries,
plus 32 SQL cases in `test_memory.sql` and `test_confidence.sql`. Verified on
OCaml 4.14.1 with dune 3.14. The SWI suite is not counted here because it does
not run without `swipl`.

```
dune build && dune test          # in ocaml/
./lint.sh                        # c, sql, prolog, elpi
```

`lint.sh` reports one failure without `swipl` installed, which is the checker
working.
