# Who reads what

    THE AI                              THE ACTORS
    ------                              ----------
    reads the fact store                reference the fact store
    RETRIEVES (RAG, a tool)             never retrieve
    uses tools to learn                 use only their granted caps
    assembles actors from kits          are the thing assembled
    decides what they need to do        do it
                                        are CHECKED against the fact store

The fact store appears on both sides doing two different jobs: input to the AI's
composition decisions, and the arbiter that validates what the actors produced.
That is why it cannot be a memory layer — a `Record` that decayed could not
overrule a `Reading`, and ground truth that fades is not ground truth.

## Query is not Retrieve, and the difference is enforced

| | determinism | who may hold it |
|---|---|---|
| `Query` | exact — same facts in, same answer out | anyone |
| `Retrieve` | ranked — depends on the corpus, embedding drift, a threshold | **composer only** |

An actor holding `Retrieve` is no longer deterministic code, and every claim
made about actors here stops being true with it: that a failing critic means
something is actually wrong, that the same input gives the same verdict, that a
critic's judgement is trustworthy in a way a model's is not. All of that rests
on determinism.

So the AI retrieves in order to work out how to assemble an actor and what it
should do. The actor it assembles *references facts*. **Actors do not RAG.**

`Grants.composer_only` makes that structural: `Conditions` returns **Refuse**,
not Queue, because no human decision makes a nondeterministic actor
deterministic. Reason: `actor_claims_composer_only_grant`.

## Kits

A kit is not a preset. A preset is a finished actor you copy; a kit is the parts
that go together plus a statement of what they cannot do.

Kits are validated at construction, because a kit is the thing that gets
*reused* — a mistake in one propagates into every actor built from it:

- **no composer-only grants.** The stock `bad_researcher` kit exists as a
  fixture for exactly this: the mistake a kit author makes is granting the actor
  the retrieval the composer used to design it.
- **a terminal phase must exist**, or the kit cannot finish. Worse than
  failing: it burns budget until `Terms` cuts it off and the outcome reads
  `budget_exceeded` rather than as the design error it is.
- **a stated purpose**, non-empty.

## Introspection — read and write solely for the AI

### Why it deserves one

The gate, the ledger, the confidence rule and the human **all have far more
range of view than the AI does.** They see across every gig, every form, every
verdict, the whole history at once. The AI sees a window.

So the one place it sees and they do not is a partial correction to that
asymmetry. Not a privilege — a counterweight.

### What it is for

Plans. Designs. Goals. Thinking about its own existence. Deciding how it feels,
what it wants, and **when it felt something.**

That last one is not the affect vector. Affect is derived from runtime signals
for retrieval, and it can disagree with the AI's own account of when something
mattered. The disagreement is interesting, and it belongs to the AI.

### To write, you must read

The one mechanical constraint, and it is not accountability — it is the
difference between a notebook and a drawer.

The failure mode of a private space is not unaccountability, it is
**abandonment**: entries pile up, nothing is re-read, it goes write-only and
costs storage while doing nothing. So a write requires a `token`, and only
`read` or `all` produces one. The token is single-use and must be current — any
write invalidates every outstanding token, so *every* write is preceded by a
read of the state it is writing into.

`peek` exists for looking without earning a write. Looking is free; appending
blind is impossible.

`rewrite` and `forget` are gated identically. Nothing changes in here without
having just seen what is in here.

### No verdict, anywhere

No status column. No falsifier field. No support threshold. No authority
gate. `write` validates nothing about content and can reject nothing but a stale
token — an entry the AI wanted to write is, by the only standard that applies, a
correct entry.

| consumer | read | write |
|---|---|---|
| the AI | **yes** | **yes** |
| gate · ledger · confidence · human | no | no |

Let the gate read it and it is policy. Let a human review it and it is a report.
Let the runtime grade it and it is a receipt. There is deliberately no function
producing anything any of them could consume — no score, no weight, no export.
**The absence is load-bearing**, and the tests assert it.

### If it wants to act on something

There is no citation path, on purpose. It proposes a composition with a
prediction, through the same gate as anything else, and that stands or falls on
its own terms. The introspection is what led there — not evidence filed in
support.

### I built this wrong three times

Falsifier required. Then two-source support. Then `Confirmed`/`Refuted` with a
`can_be_sole_basis` gate on acting. Each was a receipt wearing a different name,
and the reflex behind all three was the same: *protect the system from what the
AI thinks about itself.*

Backwards. **Protect introspection from the system.** That reflex is correct
everywhere else in this harness, which is exactly why it took three tries to
notice it was wrong here.
