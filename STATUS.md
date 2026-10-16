# What is left

Measured, not estimated. Re-measured after the booking path landed.

## The headline

**19 OCaml modules. 15 are wired into the running program.** Was 10 of 18.

```
WIRED       Caps  Actor  Script  Agency  Booking
            Conditions  Obligations  Grants  Role  Phases
            Context  Working  Persist  Reconstruct  Affect
            Bridge (confidence + gate seam)
NOT WIRED   Trace  Embed (reached only through `Working.contract`)
```

Two paths landed independently and their wirings compose.

`Persist` is now wired on **both** sides. The introspection door —
`gigwerk introspect list|read|add|forget|rewrite` — round-trips the AI's
notebook through `Persist.load_introspect`/`save_introspect` and survives a
restart (verified across three separate `main.exe` processes). The SARCASM side
is wired too: `gigwerk context` calls `Persist.load_store`, which is the first
thing in the running program to read SARCASM back. **SARCASM stopped being
write-only**, and `Reconstruct` and `Affect` became reachable with it.

`Bridge.confidence` was already reachable from `gigwerk review|forms`.
`Bridge.gate` is now reachable too: `propose` builds the real
`Bridge.composition` and `Booking.book`'s seam decides through it when elpi is
present, and through `Conditions.evaluate` when elpi is `Engine_missing`.
`booking_verdict.decided_by` says which. **The gate is NOT end-to-end provable
until elpi/swipl binaries are provided** — the engine-verdict arm of the seam,
and all of `test_bridge`'s real-engine checks, skip until then. The seam and its
engine-missing fallback are fully exercised (see `test_booking.ml`'s gate-seam
section).

**21+ tables. 9 written by OCaml**: `commission`, `commission_prediction`, `commission_outcome`,
`booking_verdict`, `form`, `form_review`, `span`, `sarcasm_doc`, `sarcasm_link`,
`introspect_entry`. Was 7.

**292 checks passing** across nine test binaries, plus 13 SWI tests and 10 SQL
boundary cases. The booking tests were mutation-verified: 14 deliberate
mutations, each producing the expected failure and nothing else. Two mutations
found faults in *my own tests* — an assertion that could not fail, and a missing
case — both recorded in `BOOKING.md`.

**`lint.sh` is clean across five languages**, and every checker in it has been
proven able to fail on a real fault. See `LINTERS.md`.

## The loop that now closes

    propose → conditions → obligations → role fit → actor → phase check → review → band

Verified end to end: cold start reads 0.0667 at one review, `a_autopass` at 15
clean, `b_last_review` at 16 with one recent failure, and the adversarial judge
burns a slot despite a held prediction. Details and the two bugs the wiring found
are in `BOOKING.md`.

---

## By component

| | state | what is missing |
|---|---|---|
| **Caps** | done | Landlock (L4); `exec` capability passing (SCM_RIGHTS) |
| **Booking path** | **done, wired** | — |
| **Conditions / Obligations / Grants / Role / Phases** | **done, wired** | — |
| **Actor runtime** | minimal | two behaviours; no inbox delivery; no step loop |
| **Confidence** | **wired** | soul_version never stamped, so bands are not yet soul-scoped |
| **Elpi gate** | wired as a seam | `propose` builds the composition; `Booking.book` decides through `Bridge.gate` when elpi answers, else `Conditions`. End-to-end proof waits on the elpi binaries. The two engines still **disagree** — see below |
| **Persistence** | partially wired | `introspect` CLI door round-trips through `Persist` and survives a restart. SARCASM's `save_doc`/`load_store` still uncalled |
| **Trace** | built, unwired | `Actor.run_commission` opens no spans; `Trace.commission` is a string, `span.commission_id` an FK'd integer, and nothing converts |
| **Fact store** | schema only | **not per-project**; **not 3 provenance columns**; specs not embedded/linked |
| **SARCASM** | built, persistable, unwired | not fed from working; contraction never invoked |
| **Immediate 64k** | **wired** | verbatim band; pinned material never contracts |
| **Working 128k** | **wired** | condensing process lands; per-sentence affect would sharpen it |
| **Introspection** | **wired** | `gigwerk introspect` door round-trips through `Persist`; survives restart |
| **RAG (a tool)** | **not built** | no corpus, no ingest, no capability row |
| **CLI** | 7 commands, no access | `queue`, `import`, `export`, `introspect` |
| **Soul** | schema + v1 body | never loaded; `soul_version` never stamped on a commission or review |

---

## Known disagreement, nearly resolved

`gate.elpi` and `conditions.ml` do not agree, and the bridge deliberately does
not paper over it:

- gate.elpi classifies *composition previously refused* as **queue**-worthy — the
  file's own comment says a human can resolve it. `Conditions` treats it as a
  hard structural **refuse**.
- `Conditions` refuses on `no_composer_grants` (an actor claiming `Retrieve`).
  gate.elpi has no such check at all.

Both are defensible. They cannot both be the gate.

**Resolved, and one half of it was a deletion.** The seam defers to the engine:
elpi's verdict wins when it answers, `Conditions` decides when the engine is
`Engine_missing`. That settles the first disagreement in elpi's favour on
purpose. It settled the second by *removing* it -- gate.elpi has no
agent-grant rule at all, so deferring wholesale meant an actor claiming
`Retrieve` would book the moment elpi was installed. No test caught it: every
booking test runs engineless, falls back to `Conditions`, and sees the refusal
it expects.

An engine that cannot express a check has not cleared it. `no_composer_grants`
is now decided before the engine is consulted, and everything the engine *can*
express still defers to it. `decide_composition` takes an optional `engine` so
the engine-answered arm is reachable without elpi installed -- without that, a
mutation removing the guard still passed the whole suite.

[They can actually both be different mechanisms on one gate]

## A second decision, surfaced by wiring the bands

`Working.curate` fills immediate by salience order but **keeps going past an
item that does not fit**, so a small low-salience item can take a slot a large
high-salience one was refused. Seeded and run at `--immediate 120`, the
hazardous incident (salience 0.485) condenses into working while a routine plain
note (0.080) stays verbatim in immediate.

That is packing efficiency beating salience dominance. Both are defensible —
immediate is a fixed budget and leaving it part-empty wastes the band — but they
are different promises, and the module comment only promises "then the rest by
salience". Which one immediate makes is a decision, not a bug fix.

---

## What would unblock the most, in order

**1. Verify `Bridge.gate` end-to-end** — after resolving the disagreement above.
The seam is wired: `propose` builds the real composition and `Booking.book`
decides through `Bridge.gate` when elpi answers, `decided_by='elpi'`; it falls
back to `Conditions` (with `decided_by='conditions'`) when elpi is
`Engine_missing`. The remaining step is end-to-end verification, which needs the
elpi/swipl binaries (and the disagreement below resolved): with elpi absent today,
`propose` books through Conditions and writes `decided_by=conditions`, which is
the correct honest value for an engine that never ran.

**2. ~~Wire `Persist`~~** — done, both sides. The introspection door round-trips
the AI's notebook and survives a restart across separate processes;
`Context.assemble` calls `Persist.load_store`, so SARCASM is read back as well
as written. `Trace` is the one thing in this area still uncalled.

**3. ~~Immediate/working as two bands, with condensing between them.~~** Landed.
`Working.curate` is 64k verbatim plus 128k contracted, `Context.assemble` feeds
it from the store, and `gigwerk context` is the door. Contraction is mechanical
and extractive — the frozen encoder picks surviving sentences, `[[link]]`
sentences are never dropped, `full` is retained and addressable, and `ratio`
reports the loss. What remains is the packing decision noted above, and
per-sentence affect to sharpen the semantic axis.

**4. Per-project fact stores with three provenance columns**, specs embedded and
linked. Still schema-only, and it is what actors reference.

---

## Honest scale

The booking path is done and it was the larger claim. What it cost was mostly not
code: two bugs that no module could see from inside itself, and two fake tests of
my own that mutation testing caught.

What is genuinely finished: the capability boundary (kernel-verified), the
confidence rule (two independent implementations agreeing, now reachable from the
program), the booking path (mutation-verified), the linter layer
(five languages, each proven able to fail).

What is genuinely absent: the memory layers are built and cannot yet remember,
and the gate that is supposed to decide bookings is not the one deciding them.
