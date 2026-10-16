---
name: smartgoal
description: Work toward a goal with a creative problem-solving workflow - read the project's own rules and design first, find the binding constraint, try several distinct approaches (installing existing tools before building), prove the cheapest on one case before scaling, and never spend a turn on a status-only message. Use when the person types /smartgoal with a goal.
---

# /smartgoal

The person has given a goal: `$ARGUMENTS`. Work toward it in this order. Each
step is done, not described.

## 1. Read before acting

- Read `CLAUDE.md` in full, and every design document, diagram or flow chart
  the person has shared or the repository holds (README, docs/, images in the
  conversation). Write down, in two or three lines, what the design says the
  goal is for and who does which part. In GigWerk: the Agent digests the
  problem and composes a solution-blind contract; deterministic machinery is
  booked to produce; acceptance checks intent against the contract; failure
  is logged and the performance repeated; success is stored and informs the
  next booking.
- If the design and the goal seem to conflict, say where, once, and ask.

## 2. Name the binding constraint

State, in one sentence, the single thing that most limits progress (not a list
of everything that is hard). Measure it on one case if it can be measured.

## 3. Generate distinct approaches, at least three

They must differ in kind, not in parameters. Always consider:

- **An existing tool.** Search for it and install it. The sandbox is a
  temporary cloud allocation: installing (apt, pip, opam, npm, dotnet,
  release binaries, git clones) is cheap and expected. Never reinvent a wheel
  someone already makes.
- **A different reading of the problem.** Reread the design for the part you
  have been treating as fixed.
- **More information through a legitimate channel.** In GigWerk that is the
  contract the Agent writes from the problem: types, worked cases,
  properties, pre- and postconditions. A contract is never code.
- **Splitting the work** across parallel subagents when the pieces are
  independent.

## 4. Prove the cheapest approach on one case

Before any run over a whole set: one instance, end to end, with its result
checked. Only then scale, and scale in the background while doing something
else useful.

## 5. Loop on evidence

After each result: log it, compare it with the binding constraint, and pick
the next approach from step 3 (or generate new ones). A failure means the
casting or the material was wrong; change one of them.

## Rules that are not style

- **No idle turns.** Every turn either runs a tool that changes or learns
  something, or asks the person one question (with two to four concrete
  options) and ends. A message that only reports that nothing changed is
  forbidden, including in reply to a stop hook or a goal loop. If truly
  blocked: one sentence naming the decision needed, once, then stop. The
  smartgoal hook counts turns with no tool call and puts this rule into the
  next turn's system prompt when one happens.
- **The person's money is spent per turn.** Long runs need a one-case proof
  first. Do not repeat a message already sent.
- **Honesty over the number.** Never tune against the set the result is
  graded on, never move the judge after seeing a result, and report what is
  not true yet.
