# Three memories

Not the Record/Ruling/Reading tables — those are one SQLite fact store sorted by
**provenance**. These are sorted by **scale of recall**, which is the orthogonal
axis and the one that makes a conversation exist.

| | scale | module | property |
|---|---|---|---|
| 1 | beyond the window | `Reconstruct` + `Affect` | strike, then walk |
| 2 | immediate | `Working` | a floor, not a ceiling |
| 3 | self-directed | (see below) | reads its own ledger; never introspects |

---

## 1. Reconstruction

**Two modes, and the second is not a variation on the first.**

### Strike — involuntary

A flavour or a song and you are simply *there*. No entry point, no path, no
hops. `strike` takes **no entry argument at all** — that is what makes it
instant. The cue's affect signature is matched against every memory's, and the
strongest resonance *is* the result.

Two conditions, and the second is what makes it recall rather than search:

- **A flat cue strikes nothing.** A stimulus that provoked nothing summons
  nothing — that is not memory, it is furniture.
- **The semantic overlap must be weak.** A cue already about the memory is a
  query, and finding it is retrieval. The whole phenomenon is that the flavour
  has nothing to do with the afternoon it returns.

A cue is not a query. A query asks for something; a cue is just *present*, and
what it summons was not requested.

The test that pins it: **strike does not return what a semantic search returns**
on the same store, same string.

### Walk — deliberate

Land somewhere, follow onward, drift. Three channels, because recollection
arrives by more than one road:

| channel | what it follows |
|---|---|
| `Link` | an explicit `[[reference]]` — narrative continuity |
| `Semantic` | proximity in the surface embedding — associative drift |
| `Resonance` | matching affect at near-zero semantic overlap — the smell |

One step is chosen at each document. Choosing all of them turns the walk back
into a set, and the set is what reads encyclopedically. Every step records
which channel carried it.

### Composed

`remember` strikes, then walks outward from wherever it landed — which is how
it actually behaves: the song hits, you are at one specific moment, and the
surrounding memory reconstructs around it. The struck step has `from = None`
and `via = Resonance`: nothing led there, it arrived.

### Two claims I got wrong

**"At any depth you hold the whole memory, blurry, not a fragment."** No — it
*is* fragments. The distinction from chunking is not coverage but what survives
the contraction: a chunker splits by position, which is arbitrary; this
contracts by semantic-affectual salience. Two tests written to the wrong claim
failed, correctly.

**"A document nothing links to can never be reached."** Also no. Every document
has a surface embedding, so the space itself carries relative relations and
nothing is unreachable. And the walk that constraint produced was too coherent
to be memory — always on topic, never drifting. A walk that can only continue
on topic is a search wearing a narrative coat.

## 2. Working set — the floor

Most context handling treats the window as a budget to minimise. This is the
opposite claim: **below a floor the conversation stops existing** and the agent
is answering isolated prompts that happen to arrive in sequence.

So the assembler fills *to* a floor (64k default, 128k ceiling). Failing to reach
it returns `cold = true` — a reportable state, not a quietly thinner context.

Eviction sorts by **affect, not recency**. The most recent thing is frequently
the least surprising, and a window filled by recency is a window full of what you
already expected. Pinned material — soul, live rulings — never evicts.

## 3. Self-directed analysis

Not built yet, and it needs a constraint stated before it is:

**The model does not introspect. It queries its own ledger.**

Introspection is the closed loop this whole design exists to break — a model
rating its own behaviour has no referent. Reading `span`, `gig_outcome`,
`crash`, and `booking_verdict` about *itself* is analysis of recorded behaviour,
which is a different thing with the same name. Output goes to `mem_reading`,
attributed and decaying, and a self-reading contradicted by a record loses like
any other.

The affect tones give it something real to look for: *which of my proposals
carried high dissonance*, *where does my cost run above prediction*, *which forms
do I keep thrashing on*. All answerable from rows. None require a feeling.

---

## The six tones, and why one is signed

| tone | source | range |
|---|---|---|
| surprise | prediction vs outcome (`matched`) | 0..1 |
| hazard | side-effecting caps, breaches, crashes | 0..1 |
| novelty | prior run count — **not** surprise | 0..1 |
| cost | budget and wall time consumed | 0..1 |
| dissonance | contradicts a live belief | 0..1 |
| **valence** | **a human approved or refused** | **−1..1** |

Novelty is not surprise: a first-ever run *cannot* violate an expectation because
there was none. It is salient for the opposite reason.

**The six tones are a vector, not a weight.** As a scalar, affect can only break
ties on relevance. As a vector it becomes its own retrieval channel — two
memories resonate when their signatures align, whether or not they are about
anything similar. That is the smell case, and without it a walk can only ever
continue on topic. Valence stays signed inside `resonance`, so a triumph does
not remind you of a disaster merely because both were loud.

Valence is the only signed tone, and separating it is the whole reason this isn't
one "importance" float. A catastrophe and a triumph are both high-magnitude; store
only magnitude and you cannot tell them apart at retrieval. `magnitude` uses
`abs_float valence` so a disaster is as *retrievable* as a triumph — while the
sign survives, so they remain *distinguishable*.

Affect aggregates upward by **max, never mean**. A mean hides exactly what you
needed: one hazardous moment inside an hour of routine work averages to routine,
and the coarse resolution — the level you actually search — reports nothing worth
looking at.

Weights are a **policy**, not baked into the ranker. A deployment that cares about
safety weights hazard; one debugging a flaky form weights surprise.
