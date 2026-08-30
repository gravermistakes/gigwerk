# SARCASM

**Semantic-Affectual Re-Construction Augmented System Memory**

The name is the argument. RAG is *Retrieval-Augmented Generation*: retrieval
serves one generation, statelessly, per query. SARCASM augments the **system**
with memory — persistent, affect-carrying, path-dependent. RAG has one channel
and no history. That is why it reads encyclopedically: it *is* an encyclopedia
lookup, and it is doing that correctly.

---

## The mechanism

Every document carries two vectors, matched independently.

**Semantic** — a 256-dim feature-hashed surface embedding. What the document is
*about*.

**Affectual** — a six-tone vector. What it *was like*: `surprise`, `hazard`,
`novelty`, `cost`, `dissonance`, `valence`. Five magnitudes and one signed.

Every tone derives from something the ledger already records. Nothing
introspects, nothing is asked how it feels. Surprise is prediction error — the
ledger writes a prediction *before* the outcome, so it is a real violation of
expectation rather than hindsight. Hazard is side-effecting capabilities,
breaches, crashes. Novelty is prior run count. Dissonance is contradiction with
a live belief. Valence is a human approving or refusing — the only externally
grounded tone, and the only signed one.

### Two modes

**STRIKE — involuntary.** A flavour, a song. `strike` takes **no entry
argument**: no starting position, no path, no hops. The cue's affect signature
is matched against every memory's; the strongest resonance *is* the result.

Two conditions make it recall rather than search. A flat cue strikes nothing —
a stimulus that provoked nothing summons nothing. And the semantic overlap must
be *weak*: a cue already about the memory is a query, and finding it is
retrieval. The whole phenomenon is that the flavour has nothing to do with the
afternoon it returns.

**WALK — deliberate.** Land somewhere and follow onward. Three channels: `Link`
(an explicit `[[reference]]`), `Semantic` (proximity), `Resonance` (affect
match at near-zero semantic overlap). One step is chosen per document —
choosing all of them turns the walk back into a set, and the set is what reads
encyclopedically.

**Composed**: `remember` strikes, then walks outward from where it landed. The
struck step carries `from = None, via = Resonance` — nothing led there.

### The falsifiable claim

*Strike does not return what a semantic search returns* on the same store, same
string. There is a test.

The failure condition is not "extra steps" — the steps are the mechanism, and
they are what carries the load. The failure is the steps **stopping doing work**:
if strike starts returning what semantic search returns, the resonance channel
has collapsed into the semantic one and the extra machinery has gone decorative
while still costing what it cost.

---

## Contraction is not compaction

This is the distinction the whole thing rests on, and it is easy to lose.

A context-compaction command summarises forward and **discards the original**.
Four properties follow, and SARCASM must not share any of them:

| compaction | contraction |
|---|---|
| **replaces** — detail is gone, nothing reconstructs | **adds a layer** — `full` is retained, `expand` reaches it |
| **model-authored** — a summary is a Reading in a Record's clothes | **mechanical** — affect from the ledger, semantics from a frozen encoder |
| **flattens** — hierarchy and affect dissolve into prose | **preserves affect as a vector** — a separate retrieval channel |
| **one-shot** — compress twice and you summarise a summary | **coexisting** — digest and full both live |

The mechanical part is the load-bearing one. A compaction summary encodes *what
the model thought mattered*, which is the model's opinion about its own
salience — the closed loop again. SARCASM's weights come from prediction error,
hazard, and a human's verdict. None of those is a judgment the model gets to
make.

Concretely: search runs on the **digest**, expansion reaches the **full**. Detail
is addressable without being searchable, which is what lets a reconstruction
sharpen instead of merely paraphrase. `compression_ratio` reports the loss — a
contraction claiming no loss is not contracting.

---

## The numbers

Three tiers, and I was wrong about two of them until I measured.

### Derived — not knobs

| value | why it is not a choice |
|---|---|
| surprise `0 / 0.5 / 1.0` | encoding of a three-valued field |
| valence `±1.0` | endpoints of a signed range |
| magnitude `/6.0` | arithmetic mean over six dimensions |
| `4` chars/token | empirical for English; wrong in the third digit, right in the first |

### Measured — calibrated against the shipped encoder

Run `dune exec calib/calib.exe`:

```
semantic cosine, feature-hashed 256d
  unrelated    mean=0.065  sd=0.111  range=[-0.023, 0.279]
  related      mean=0.321  sd=0.113  range=[ 0.139, 0.459]
  paraphrase   mean=0.828  sd=0.028  range=[ 0.789, 0.855]

affect resonance, 6-tone vector
  dread vs near-dread   1.000
  dread vs elation      0.396   (identical magnitudes, opposite sign)
  dread vs routine      0.000
  routine vs novel      0.428
```

**`min_resonance = 0.7` survives.** The measured gap runs from 0.428 (routine
vs novel — should not fire) to 1.000 (near-dread — should). 0.7 sits inside it
with room on both sides.

**`max_semantic = 0.30` did not survive, and the fix needed a second fix.** The
unrelated and related distributions *overlap*: unrelated reaches 0.279, related
falls to 0.139. No constant separates them, and one tuned for terse log lines
will not work for prose. Replaced with a **percentile of the cue's actual
similarity distribution over this store**.

Which introduced a different failure: **a percentile over a small store is
unstable.** With six documents the 25th percentile is essentially the
second-smallest value, so adding one unrelated document moves the threshold and
a cue that fired stops firing. That is not hypothetical — it broke seven tests
the first time it landed.

So the percentile applies only above `min_store_for_percentile = 20`; below it,
a conservative measured absolute (`0.18` — unrelated mean + 1sd). Neither rule
is right everywhere. **The switch between them is the actual design.**

**`is_flat` at 0.15 did not survive.** A background-hum vector (`novelty 0.1,
cost 0.2`) measures norm 0.224 and was passing as a live cue — exactly the
furniture the predicate exists to exclude. Raised to 0.30, which puts hum below
the line and leaves `dread` (norm 1.64) far above.

**`novelty = 1/√(n+1)`** is IDF-shaped and the curve checks out: n=3 → 0.500,
n=15 → 0.250, n=99 → 0.100.

### Invented — no data behind them

| value | what it encodes | what would actually tune it |
|---|---|---|
| weights `.30/.25/.15/.05/.20/.05` | *ordering* is a real claim — prediction error is the primary salience signal. Values are guesses. | which tone best predicts "the human wanted to see this" |
| channels `link 1.0 / res 0.9 / sem 0.75` | links strongest, resonance nearly so, raw proximity weakest | share of walks per channel the human found useful |
| hazard `0.4 / 0.3 / 0.5` | side-effecting / breached / crashed | which of the three actually precedes incidents |
| walk affect bias `0.35` | how hard affect bends the path | drift rate you can tolerate |
| threshold `0.02`, budget `1200` | when a thread has gone cold | nothing principled; observe |

---

## The structural finding

Five of six tones are non-negative, so any two non-flat vectors have a cosine at
or above zero and usually a high one. **Valence's sign is doing most of the
discriminating work** — measured: dread vs elation scores 0.396 with *identical
magnitudes*, purely because the sign flips.

That is defensible on its own terms — grief resonates with grief, and a triumph
should not remind you of a disaster merely because both were loud. But it means
the other five tones separate less than the design implies, and resonance is
closer to a valence-match with magnitude modulation than to a six-way
comparison.

The fix, when there is a populated store to compute it from: **centre the five
unsigned tones** by subtracting each one's store-wide mean, so a below-average
tone reads negative and can actively push a cosine down. Noted in `affect.ml`,
not implemented, because a mean needs data that does not exist yet.
