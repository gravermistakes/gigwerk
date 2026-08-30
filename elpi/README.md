# Phase 2 — the booking gate, in real λProlog

Elpi 3.7.2, built and running. The gate decides `book` / `queue` / `refuse`
before the capability record is constructed.

```sh
elpi run_test.elpi  -exec main -- good      # book
elpi run_test.elpi  -exec main -- sneaky    # refuse: scope widens
elpi run_test2.elpi -exec main -- deadsig   # refuse: previously refused
elpi hoas.elpi      -exec demo -- x         # binders + narrowing
```

| composition | decision | why |
|---|---|---|
| `good` | book | scope strictly beneath the envelope |
| `sneaky` | refuse | `/srv/gigwerk-evil` against envelope `/srv/gigwerk` |
| `ghost` | refuse | claims a capability that does not exist |
| `misplaced` | queue | agent provenance running in-process |
| `effectful` | queue | `requires_booking` with no human verdict |
| `approved` | book | same claim, human verdict present |

## Scopes are segment lists, not strings

A string-prefix check accepts `/srv/gigwerk-evil` for an envelope of
`/srv/gigwerk` — same characters, different directory. Measured:

```
  /srv/gigwerk/work      string-prefix=True   segment-prefix=True
  /srv/gigwerk-evil      string-prefix=True   segment-prefix=False   <-- the bug
  /srv                   string-prefix=False  segment-prefix=False
```

`narrows` compares segments, so it cannot make that mistake. This is check 2,
and it is the one every other safety property rests on.

## Where λProlog earns its place

`wf_scheme` — a polymorphic shape is a **function from types to types**, checked
under a fresh binder introduced by `pi` with a local `wf x =>` hypothesis:

```prolog
wf_scheme F :- pi x\ (wf x => wf (F x)).
```

Plain Prolog needs a gensym and a side table to do this. Verified running on
`(t\ tpair t (tlist t))` and `(t\ tarrow t t)`.

Honest scoping: checks 1, 4, 6 and 7 are set membership, which plain Prolog does
just as well. Only 2 and 3 touch structure, and only 3 uses binders.

## Two Elpi gotchas that cost real debugging time

**`i:` modes make a fact table unqueryable.** `pred claim i:string, i:string,
i:list string` silently matched nothing for `claim "sneaky" C S`, because
mode-directed indexing requires input positions to be ground. Every composition
came back `book` with no reasons. Fact tables need `type ... -> prop`, no modes.

**`->` is not Elpi syntax.** That is SWI. `(C -> T ; E)` parses as an undeclared
global term, so `decide` never branched and everything returned `queue`. Elpi
uses cut-based disjunction: `( C, !, T ; E )`.

Both failed *silently and plausibly*, which is the dangerous kind.

## Check 3 is weaker than advertised

`wf` accepts any nesting of declared constructors, and an *undeclared*
constructor is rejected by Elpi's typechecker before the gate runs. So check 3
catches close to nothing today. It starts earning its keep when shapes carry
constraints beyond structure — arity, or a required field — where the binder does
work no set-membership test can.

## Not wired yet

- Facts come from `facts_test.elpi` by hand. `sql/export_facts.sql` must learn to
  emit Elpi clauses with scopes **pre-split into segment lists** — the splitting
  belongs in SQL, not in the gate.
- No `gigwerk propose` yet: nothing writes `booking_verdict` from a decision.
- Check 4 is store health, not composition health. It blocks booking while the
  write-ownership table is broken, which is right, but it belongs in a `doctor`
  command too.
