# What is left

Measured, not estimated. Re-measured after the booking path landed.

## The headline

**18 OCaml modules. 10 are wired into the running program.** Was 4 of 15.

```
WIRED       Caps  Actor  Behaviors  Store  Booking
            Conditions  Terms  Grants  Kit  Phases
            Bridge (gate seam)  Persist (introspection door)
NOT WIRED   Trace  Reconstruct  Affect  Embed  Working
```

`Bridge.confidence` was already reachable from `gigwerk review|forms`.
`Bridge.gate` is now reachable too: `propose` builds the real `Bridge.composition`
and `Booking.book`'s seam decides through it when elpi is present, and through
`Conditions.evaluate` when elpi is `Engine_missing`. `booking_verdict.decided_by`
says which. **The gate is NOT end-to-end provable until elpi/swipl binaries are
provided** — the engine-verdict arm of the seam (and all of `test_bridge`'s
real-engine checks) skip until then, but the seam and its engine-missing fallback
are fully exercised (see `test_booking.ml`'s gate-seam section).

`Persist` is now wired on the introspection side: `gigwerk introspect
list|read|add|forget|rewrite` round-trips the AI's notebook through
`Persist.load_introspect`/`save_introspect`, so it survives a restart (verified
across three separate `main.exe` processes). `Persist`'s SARCASM side
(`save_doc`/`load_store`) and `Trace` are still unwired.

**21+ tables. 9 written by OCaml**: `gig`, `gig_prediction`, `gig_outcome`,
`booking_verdict`, `form`, `form_review`, `span`, `sarcasm_doc`, `sarcasm_link`,
`introspect_entry`. Was 7.

**238 checks passing** across five test binaries, plus 13 SWI tests and 10 SQL
boundary cases. The booking tests were mutation-verified: 14 deliberate
mutations, each producing the expected failure and nothing else. Two mutations
found faults in *my own tests* — an assertion that could not fail, and a missing
case — both recorded in `BOOKING.md`.

**`lint.sh` is clean across five languages**, and every checker in it has been
proven able to fail on a real fault. See `LINTERS.md`.

## The loop that now closes

    propose → conditions → terms → kit fit → actor → phase check → review → band

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
| **Conditions / Terms / Grants / Kit / Phases** | **done, wired** | — |
| **Actor runtime** | minimal | two behaviours; no inbox delivery; no step loop |
| **Confidence** | **wired** | soul_version never stamped, so bands are not yet soul-scoped |
| **Elpi gate** | wired as a seam | `propose` builds the composition; `Booking.book` decides through `Bridge.gate` when elpi answers, else `Conditions`. End-to-end proof waits on the elpi binaries. The two engines still **disagree** — see below |
| **Persistence** | partially wired | `introspect` CLI door round-trips through `Persist` and survives a restart. SARCASM's `save_doc`/`load_store` still uncalled |
| **Trace** | built, unwired | `Actor.run_gig` opens no spans; `Trace.gig` is a string, `span.gig_id` an FK'd integer, and nothing converts |
| **Fact store** | schema only | **not per-project**; **not 3 provenance columns**; specs not embedded/linked |
| **SARCASM** | built, persistable, unwired | not fed from working; contraction never invoked |
| **Immediate 64k** | **not built** | `Working` is a separate band |
| **Working 128k** | partial | band exists; **no condensing process** |
| **Introspection** | wired | `gigwerk introspect` door round-trips through `Persist`; survives restart |
| **RAG (a tool)** | **not built** | no corpus, no ingest, no capability row |
| **CLI** | 6 commands, no access | `queue`, `import`, `export`, `introspect` |
| **Soul** | schema + v1 body | never loaded; `soul_version` never stamped on a gig or review |

---

## Known disagreement, nearly resolved

`gate.elpi` and `conditions.ml` do not agree, and the bridge deliberately does
not paper over it:

- gate.elpi classifies *composition previously refused* as **queue**-worthy — the
  file's own comment says a human can resolve it. `Conditions` treats it as a
  hard structural **refuse**.
- `Conditions` refuses on `no_composer_grants` (an actor claiming `Retrieve`).
  gate.elpi has no such check at all.

Both are defensible. They cannot both be the gate. Resolving this is a decision,
not a bug fix, and it is the thing standing between `Bridge.gate` and being
wired.

[They can actually both be different mechanisms on one gate]

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

**2. Wire `Persist` fully** — the introspection door is wired: `gigwerk introspect
list|read|add|forget|rewrite` round-trips the AI's notebook through `Persist` and
survives a restart (verified across separate processes). What remains is
`Persist`'s SARCASM side (`save_doc`/`load_store`) and `Trace`, both still
uncalled.

**3. Immediate/working as two bands, with condensing between them.** The one
piece where the wrong shape was built rather than nothing: one band with a floor
and ceiling, when it needs 64k verbatim plus 128k where contraction happens.

**4. Per-project fact stores with three provenance columns**, specs embedded and
linked. Still schema-only, and it is what actors reference.

---

## Honest scale

The booking path is done and it was the larger claim. What it cost was mostly not
code: two bugs that no module could see from inside itself, and two fake tests of
my own that mutation testing caught.

What is genuinely finished: the capability boundary (kernel-verified), the
confidence rule (two independent implementations agreeing, now reachable from the
program), the booking path (238 checks, mutation-verified), the linter layer
(five languages, each proven able to fail).

What is genuinely absent: the memory layers are built and cannot yet remember,
and the gate that is supposed to decide bookings is not the one deciding them.
