# GigWerk — the working agreement

Eminem gets booked for a performance. Paul Rosenberg manages him; an agent finds
the venue and the date. Neither has ever handed him a verse, and if either did he
would not be an artist, he would be a session vocalist reading someone else's
sheet.

That is the whole architecture. The Agent books. The Actors labor. The Agent
never authors the work and never directs how it is performed.

## The error this file exists to prevent

If the code arrives inside the specification, a model wrote it, and the Actor is
a clerk filing someone else's output. Every proposal then costs a full
generation; every failed build costs another; and the deterministic machinery
downstream adds latency while removing no inference at all. Cost scales with the
artifact instead of with the decision, which is the one thing this design exists
to prevent.

An Actor is not a function the Agent fills in. It is a capable party, booked for
competence it already holds. Synthesis, compilation, a critic's check: those are
the labor, and the labor is not the Agent's to do.

## What the Agent actually decides

Which composition gets proposed. That is the whole of it, and it is enough,
because every consequence of that one decision is checked by something
deterministic.

A booking is **Commission** (this engagement), **Obligations** (the budget, the
deadline, the allowance of actions), **Grants** (what may be touched, and
nothing else), and **Role** (the part). None of those is the material. The Agent
books capability it does not have and cannot supply.

The Role declares its own ladder. `phases.ml` already says this: the ladder is
declared by the TOOL, not by the Agent and not per instance. The Agent assigns
the Role; the Role defines the part and what *done* means. The Agent gets to say
neither.

## A refusal is range, not failure

Takashi Murakami is booked through Kaikai Kiki. The studio does not tell him what
to paint. It handles the art: fabrication, logistics, galleries, contracts,
archive, the accumulated reputation that makes the next booking possible. He
founded it. The agency exists to serve the artist, not the reverse.

That is the Agency here. Actors do not accumulate; they are instantiated for a
commission and discarded. The Agency accumulates: the ledger, the forms, the
affect-tagged record, the soul. What an Actor did survives it, as a fact the
Agency holds.

So when an Actor reports that it cannot derive something, *measures structurally
recurse on a declared datatype, not on the int carried by Many*, that is an
artist saying what they do not perform. It is range. An agency that knows its
roster stops booking the rapper for opera. Record it, keep it queryable, and book
accordingly. `booking_verdict` keeps its refuse rows for exactly this reason:
discard them and a closed-world reading cannot tell unlabeled from bad.

The first hundred commissions are learning. Not labeling work for a downstream
learner; learning, by the strictest standard available, because
`commission_prediction` is written before the outcome and carries a required
falsifier.

## Rules that are not style

**NO LLM AI WILL EVER WRITE PRODUCTION CODE THROUGH THIS HARNESS.** Every
artifact the harness delivers is derived by a deterministic Actor. A model may
choose the booking; it never supplies the work, in whole or in part.

**Query is exact; Retrieve is ranked.** An Actor holding Retrieve is no longer
deterministic code, and every claim resting on that determinism dies with it. It
is composer-only, and `Conditions` returns Refuse rather than Queue, because no
human decision makes a nondeterministic Actor deterministic. Determinism is also
why a derived result is cacheable: same contract, same code, forever. You pay
once.

**The soul takes two signatures.** The agent's and the human's, both, before a
version is live. One signature is a proposal and sits in `v_soul_pending`;
`v_soul_current` requires the pair. A signature is not retractable. `version` IS
the content hash, so editing the body adopts a new version and needs both names
again. Do not edit a soul body as though it were a file.

**No shell.** Acceptance is a closed variant rendered to argv and handed to
`execvp`. Nothing is concatenated, so nothing can be split apart again by an
interpreter that no longer runs. A verb nobody declared is unrepresentable, not
unknown.

**Do not claim a boundary the code does not hold.** A document asserting safety
it lacks is worse than one asserting nothing; that is why the README carries a
*what is not true yet* section. Measure counts, never carry them forward.

**Do not fill open architectural slots with defaults.** If a name or a decision
has not been given, ask for it in a batch, or leave it open and say so. Inventing
it and presenting it back as settled wastes the only time that matters.

**Authorship.** No linking sessions. No cron jobs. No timed bringing the session
online. Either take authorship or do not; there is no "generated" terminology.

## Build

```
cd ocaml && dune build && dune test     # 377 checks across thirteen binaries
./lint.sh                               # c, sql, prolog, elpi
```

The synthesis harness (merged from the manus implementation) runs from its own
directories:

```
cd gigwerk-exercises/backend && dune build --root . && dune test --root .
bash gigwerk-exercises/backend/test_cli.sh          # real Synquid output -> OCaml
bash synquid-validation/run-ocaml-tests.sh          # BST, with negative control
cd gigwerk-exercises/scripts && python3 -B test_status.py && python3 -B test_runner.py
```

`lint.sh` reports one failure for each of `swipl` and `elpi` that is not
installed, which is the checker working: a section whose tool is missing fails
rather than passing on nothing. Every checker in it has been proven able to fail on a real fault; keep
it that way, and mutation-verify anything new before claiming it passes.

Verified on OCaml 4.14.1 with dune 3.14.

## Casting, not directing

Nicolas Cage did not write The Wicker Man. LaBute wrote it and directed it, so
the material came from the production rather than the performer. His agents still
never gave him a line reading. What remained to Cage was the performance, and the
performance was entirely his.

Both cases agree, and the agreement is the rule. Sometimes the Actor brings the
material and sometimes it is cast to material that already exists. Either way
representation does not author it, and representation does not say how it is
delivered. Supplying the implementation is directing, and directing is paying
inference to do the Actor's job on top of your own.

Cage won an Oscar; this one won him a Razzie. Agents equally hands-off both
times. A bad outcome does not mean representation should start acting; it means
the casting was wrong, or the material was. That is `commission_outcome`,
recorded, and it is what the Agency learns from.
