# Terms · Grants · Conditions

Renamed from the bughunting vocabulary. Three modules, three different
questions, zero dependencies.

| module | question | was |
|---|---|---|
| `Grants` | **what** may this actor do | `Scope` |
| `Terms`  | **how many** and **until when** | `Lease` |
| `Conditions` | **what must hold** to book it | `Lance_rule_gate` |
| `Caps`   | **where** — kernel-enforced | (new) |

Four questions, four mechanisms. None of them is a string match, which is the
whole reason the vocabulary is worth separating.

## Grants is a closed variant

`Read | Write | Spawn | Query | Emit`. An action nobody defined isn't "unknown",
it's unrepresentable — a typo in a composition fails to parse instead of
silently granting nothing.

## Terms couples budget to permission

One value holding grants, budget, and expiry, checked per action. That coupling
is the point: exhaustion and ungranted-action become the same mechanism, so an
approved gig can't burn unbounded actions inside itself.

A budget number in a table nothing reads is not a budget. This has to be
threaded through every action to mean anything — which is why `spend` exists
alongside `check`: it checks and consumes in one step, so a caller cannot check
once and act twice.

Expiry is tested before budget, so a lapsed contract doesn't report a budget
figure as though it were still live.

## Terms is an ACL. Caps is not. Keep both.

`Terms.check` is ask-and-answer. The `openat2` dirfd in `Caps` is object
capability — no reference, no call, nothing to ask.

They are orthogonal, not competing: **a dirfd cannot express "twenty reads then
stop", and Terms cannot prevent a path escape.** Spatial bounds from the kernel,
quantitative bounds from Terms, threaded together.

## Conditions: three verdicts, and the ordering matters

`Refuse` is structural — malformed or unsafe, and no human decision changes it.
`Queue` is a decision a human can actually make. `Book` is clean.

Structural failures are evaluated **first**, so a malformed composition never
reaches the human queue. Review attention is the scarce resource in this design
— past roughly 0.9 approval the queue stops being read — so spending it on
compositions that were never bookable is the expensive mistake.

## The adversarial judge lives here

`support_strength` / `refutation_strength`, carried over from the original's
`exploit_strength` / `rejection_strength`. **Ties refuse.** An adversarial judge
that loses ties is a rubber stamp with extra steps.

## Tests

```sh
cd ocaml && dune build @runtest --force
```

`test_terms.ml` — 22/22, including that a structural refusal never surfaces a
procedural reason, and that a `spend` on an ungranted action does not consume
budget. `test_gigwerk.ml` — 16/16, the capability and process-boundary layer.

## Adopted from external references

**Observation contract** (`agent-harness-construction`). `verdict` gained
`follow_up` and `resource`. A verdict that reports a failure without a next step
makes the reader re-derive one — and `verdict_wellformed` enforces it rather
than documenting it: a failing verdict with an empty `follow_up` is a bug in the
behavior, not a legitimate state.

**Generalization guard** (`continuous-learning-v2`'s 2+ projects rule), in
`prolog/confidence.pl`. `promotable/2` returns `too_narrow(N)` until a candidate
rule is supported by ≥2 *distinct forms*. Aleph will induce a rule from one
form's history quite happily; promoting it teaches the gate that form's
accidents. There is deliberately no `promote/1` — eligibility is the most the
file will ever say, and a test asserts that predicate does not exist.

## Retracted: completion phrases

I rejected "magic phrase signals complete" as self-certification. That was wrong,
and the error was collapsing a distinction that matters: in the source document a
*model* emits the phrase. Here an *actor* emits it — deterministic code, emitting
exactly where its source says. Same syntax, entirely different trust. The pattern
was never the problem; the binding was.

So `Phases` exists, and it closes a gap `Terms` cannot reach. `Terms` bounds
*failure* to finish — budget spent, deadline passed. It has no way to express
finished early and correctly, so without this a gig that completes in 3 of 20
actions merely stops being called.

Three properties make the signal a condition rather than a report:

- **The ladder is declared by the tool.** Not by the composer, not per instance.
  The composer picks which behavior runs; it cannot pick what "done" means. A
  test asserts `critic` cannot emit `echo`'s terminal phrase and vice versa.
- **An undeclared phase is a breach**, not an unknown state. A behavior that can
  emit arbitrary strings can emit "done" by accident — which is the property that
  made the phrase untrustworthy to begin with.
- **Regression after terminal is refused.** Emitting work after `done` is a bug
  in the behavior, and it is caught at the emission rather than inferred later.

The repetition count drops out of the same reasoning. Thrice exists because the
emitter might be unreliable; a deterministic emitter needs one, and
`~consecutive:1` settles on a single emission. The default of 2 is insurance
against a *buggy* behavior that flip-flops, not against a lying one — and since
regression is already refused, the only route to two-in-a-row is actually being
finished.

## Rejected, with reasons

**pass@1 / pass@3 / cost-per-success.** Presumes a model doing the task. Actors
are deterministic, so pass@1 is 1.0 or 0.0 and the metric cannot move. `matched`
is the analogue, and only for the composer's proposals.

**Model-assigned confidence (0.3–0.9 by an observer model).** A model scoring
its own pattern extraction. Cheap and self-referential; the bands here come from
human review — expensive and externally grounded. Either is defensible. Mixing
them without knowing which you hold is how the loop closes quietly.

**A shared notes file as the context bridge.** It is the model remembering its
own narrative, which drifts. The store holds facts the runtime wrote. Both solve
"each invocation starts fresh"; only one has a referent outside the model.
