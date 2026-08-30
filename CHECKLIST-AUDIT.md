# GigWerk vs. the standard harness checklist

| Component | Status | Where |
|---|---|---|
| Context Delivery | partial | `skill/SKILL.md` instructs read-before-propose; not enforced |
| Tool Integration | **covered, stronger** | `Caps` (ocap), `Grants` (closed variant) |
| Planning Mechanism | **missing** | no plan step exists |
| Action Execution | covered | `Actor.run_gig`, forked, bounded |
| Verification Process | **covered, differently** | see disagreement 1 |
| Permissions | **covered, differently** | see disagreement 2 |
| Monitoring | **was missing** | now `Trace` + `span` table |
| State Management | partial | `c_state` exists; disposition rules unwritten |
| Memory System | **covered, partially rejected** | see disagreement 3 |
| Testing / Linting | partial | harness self-tests green; per-language linters designed, one built |
| Tracing | **was missing** | now `Trace` |

Real gaps after this pass: **the planning loop** (Phase 3, needs the CLI) and
**the per-language linter layer** (one of N exists).

---

## Four places the checklist is wrong

### 1. "Include a method for the agent to verify its outputs"

This is the worst line in it. An agent verifying its own outputs is the closed
loop — the machine learns to feel verified. Verification has to come from
something that is not the agent and cannot be argued with by it.

Here: the **critic** is deterministic code (a failing critic means something is
actually wrong, every time), and the **judge** is a second model that never sees
the composer's justification, with ties refusing. Neither is the thing that
produced the work.

Build the checklist's version and you get a system that reports success at
exactly the moments it is most wrong.

### 2. "Set up authorization levels"

Levels are ordinal, and permissions are not. Is "spawn a subprocess in /tmp"
above or below "read /etc"? There is no answer, so any level assignment is
arbitrary, and arbitrary orderings leak — something ends up above a line it
should never have crossed because a number said so.

Here: an unordered capability **set** (`Grants`), a kernel-enforced root
(`Caps`), and quantity/expiry (`Terms`). Three bounds, no ordering, nothing to
get backwards.

### 3. "Store prior interactions and user preferences"

Two things with different trust in one box. Prior interactions are facts the
runtime observed. Preferences are inferred and drift. Store them together and a
drifted preference reads with the same authority as a recorded outcome.

Here: the ledger holds facts, confidence bands derive from human review, and
there is deliberately **no preference store**. What looks like a preference is
either a rule you approved or it is not in the system.

### 4. "Observability... so you can detect and correct problems before humans
have to review"

This frames review as a failure mode to be minimised. Here review is the
*calibration source* — the confidence bands mean something only because a human
produced the labels. Tracing that makes review cheaper is good. Tracing sold as
a replacement for review removes the only referent outside the system.

---

## And two things the checklist has no word for

**Nothing in it can refuse.** "Guardrails and Control" is permissions plus
monitoring — one scopes, one observes, neither blocks a proposal. There is no
gate anywhere in the list. A harness whose strongest control is a permission
check is a harness that cannot say *no, not this shape, here is why*.

**The loop has no stopping condition.** "Planning and Execution Loop" names
plan, act, verify, and never terminates. `Terms` (budget, expiry) and `Phases`
(a terminal phase emitted by deterministic code) are the two conditions here,
and neither is the model's to assert.
