# The booking path

`Conditions → Terms → Kit → Actor booked to match`

    gigwerk propose critic --artifact notes.txt --grant read,query

## Why that order, since it is not the order the types suggest

My instinct was Kit → Terms: the kit knows which actions it needs, so let it hand
those to Terms. That is backwards, and the way it is backwards is the same
failure the whole design exists to prevent. **If the kit supplies the budget, the
thing that runs inside the bound is the thing that set the bound.** A kit author
who wants more room writes a bigger number, and the number stops being a bound
and becomes a declaration.

So the envelope is authored *above* the kit, and the kit is then checked to see
whether it fits inside. Terms first, kit second, and a kit needing an action the
envelope does not grant is refused rather than accommodated.

This is the discipline `Caps` applies to space — the dirfd has no parent —
applied to quantity: **the allowance has no author downstream of itself.**

In the CLI the envelope comes from the human's flags, not from the entity's
claims. If `--grant` defaulted to whatever the composition already claimed, the
envelope would be derived from the thing it is supposed to bound and every
proposal would fit by construction. Which is why this refuses:

    $ gigwerk propose critic --artifact notes.txt
    decision  refuse
    kit needs actions the envelope does not grant: read, query

The refusal *is* the mechanism working.

## What "booked to match" means, and both halves are checked

**1. The actor's grants are the KIT's, not the envelope's.** Envelope permits
read+write+spawn+query, kit only reads and queries → the booked actor holds read
and query. Least authority, computed at booking, not trusted at runtime. This is
the single most important line in `booking.ml`; a test proves the narrowing by
booking a deliberately over-wide envelope and asserting the two actions the actor
must *not* have.

**2. The wall clock is `min(kit ask, terms remaining)`.** Whichever is tighter,
always, resolved before the fork so no code inside the gig participates.

## The fork problem, stated rather than papered over

A gig runs in a forked child. Terms is an immutable OCaml value, so
`Terms.spend` inside the child mutates a copy that dies with the child — the
parent never learns what was consumed. A per-action counter therefore **cannot**
be a global bound across gigs, and pretending otherwise would be a budget figure
nobody reads.

Two Terms values instead, each bounding what it can actually bound:

| | held by | bounds | dies with the child? |
|---|---|---|---|
| `envelope` | the parent | bookings, debited once before the fork | no — that is the point |
| `gig_terms` | the child | actions within one gig | yes, and that is correct |

`gig_terms` dying is not a leak: it was never a running total. The wall clock
(SIGALRM) is the one bound the child cannot lie about, which is why it is the
backstop rather than the accountant.

## Phases cross the fork, which is the point

The child reports `PHASE \x1f PAYLOAD` on the pipe. The **parent** checks the
phase against the kit's ladder. An undeclared phase is a breach detected by the
reader, not a self-report the reader trusts. `\x1f` because the verdict encoding
already owns `|`, and only the first separator splits — a payload cannot forge a
second transition.

A phase name means the step *completed*, which is what makes three outcomes
separable:

| what the parent observed | `matched` | why |
|---|---|---|
| settled on the terminal phase | `yes` | it did its job |
| a real non-terminal phase, then stopped | `partial` | it did part of it |
| no phase at all | `no` | it produced nothing |
| a phase outside its own ladder | `no` | a breach is never partial credit |
| crash, budget kill, failure | `no` | — |

A critic that correctly reports a *bad* artifact settled on `verdict_emitted` and
is a **match**. A critic that could not read produced no verdict and is not. That
distinction feeds the confidence rule directly, so getting it wrong corrupts
every band silently rather than failing loudly.

## Two bugs the wiring found

Neither was visible from any module in isolation.

**A transient refusal permanently killed a shape.** `booking_verdict` was doing
two incompatible jobs: the audit log of every refusal *and* the dead set that
`not_refused_before` reads. So refusing a proposal because the envelope the human
authored *this time* did not cover the kit wrote a `refuse` row against the
**form** — and the form, whose identity deliberately ignores envelopes, could
never book again. One `attaches_to` column fixes the whole class:

- `composition` — a structural failure. In the dead set, and permanence is
  correct: fixing a structural problem changes `cap_set`, `policy_set` or
  `state_shape`, which makes it a different form.
- `proposal` — the envelope was too narrow, expired, exhausted; or the
  adversarial judge outweighed the proposer *this time*; or a human was asked.
  Says nothing about the shape. **One skeptical judge cannot kill a form.**
- `kit` — the kit is malformed; every composition built from it is affected, the
  composition that reached for it is not itself dead.

`Conditions` makes the composition/proposal call itself rather than having it
reconstructed downstream by matching on a reason string — that alternative is one
typo away from a shape being permanently killed by a single skeptical judge.

**`form_sig` had two collisions.** Joining a sorted list with commas is not
injective: `["a,b"]` and `["a";"b"]` render the same key, so one capability whose
name contains the delimiter is indistinguishable from two — two different shapes
sharing one confidence record, silently. Count-prefixing fixes that; it does not
fix `["a,b";"c"]` vs `["a";"b,c"]`, which are both two elements and both render
`a,b,c`. Both prefixes are needed, and the second case was found *by mutation
testing* — dropping the length prefix left every other identity test green.

## The whole loop, as it actually runs

    $ gigwerk propose critic --artifact notes.txt --grant read,query
    form      0db8c5c23fc175db
    decision  book
    gig_terms critic@0db8c5c2...[read,query] budget=2
    matched   yes
    phase     verdict_emitted (settled)

    $ gigwerk review --gig 1 --held yes --critic pass --judge clear
    recorded review 1 for form 0db8c5c23fc175db
    band      c_needs_review  certainty 0.0667      <- cold start pins the
                                                       denominator at 15
    ... fourteen more clean reviews ...
    band      a_autopass      certainty 1.0000

    $ gigwerk review --gig 16 --held no ...
    band      b_last_review   certainty 0.9333      <- one recent failure blocks
                                                       autopass at 93%

    $ gigwerk review --gig 17 --held yes --judge refuted
    band      b_last_review   certainty 0.8667      <- the judge burns the slot
                                                       despite a held prediction

That is loop 3 closed: AI → booker → store → actor → booker → human review →
SWI-Prolog → band. The band is read back immediately after every review on
purpose — a review that lands and changes no band is a review that never reached
the form, which is the FK-orphan failure that once made three tests "pass" while
inserting nothing.

## Refusals, exhaustively

| refusal | attaches to | reachable from |
|---|---|---|
| `Refused` (structural) | composition | a widened scope, a missing capability, two writers, an unresolved shape, an actor claiming `Retrieve` |
| `Refused` (adversarial) | proposal | `refutation ≥ support` with refutation > 0 — ties refuse |
| `Queued` | proposal | a claimed capability has `requires_booking = 1` and no human verdict exists |
| `Envelope_carries_composer_grant` | proposal | `--grant retrieve` — the envelope is what gets narrowed into the actor's terms, so the check belongs one layer above the kit |
| `Envelope_dead` | proposal | expired, or its booking budget is spent |
| `Kit_rejected` | kit | composer-only grant, no terminal phase, empty purpose, grants with no action allowance |
| `Kit_exceeds_envelope` | proposal | names exactly the missing actions |
| `No_wall_left` | proposal | a kit asking for zero wall clock; the terms side cannot reach zero because `Terms` is second-granular and `live` refuses expiry first |
