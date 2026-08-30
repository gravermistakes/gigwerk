-- GigWerk component store.
--
-- The store IS the ECS. One table per component type, entity_id as key, and a
-- "system" is a query with joins. This is not a persistence layer bolted onto
-- an ECS -- it is the ECS, which is what makes Aleph cheap later: composition
-- and outcome live in one relational space, so ILP can learn which SHAPES
-- produce which RESULTS, not just which results happened.
--
-- Three kinds of component, deliberately not merged:
--   data        pure values, runtime-writable, restart disposition applies here
--   capability  a REFERENCE to a tool in the frozen core, never a definition
--   policy      a Prolog predicate name; logic, but declarative logic
--
-- Only `data` is written at runtime. That is the mutable-surface ceiling.

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

-- ---------------------------------------------------------------- entities

CREATE TABLE entity (
  id          INTEGER PRIMARY KEY,
  name        TEXT    NOT NULL UNIQUE,
  preset      TEXT,
  -- Decides the labor tier: 'human' composition runs in-process, 'agent'
  -- composition runs in a subprocess. Provenance is a field you already have,
  -- not one you'd have to add.
  provenance  TEXT    NOT NULL CHECK (provenance IN ('human','agent')),
  created_at  INTEGER NOT NULL,
  retired_at  INTEGER
);

-- --------------------------------------------------- kind 1: data components

CREATE TABLE c_inbox (
  entity_id   INTEGER PRIMARY KEY REFERENCES entity(id) ON DELETE CASCADE,
  capacity    INTEGER NOT NULL DEFAULT 256,
  overflow    TEXT    NOT NULL DEFAULT 'drop_oldest'
              CHECK (overflow IN ('drop_oldest','drop_newest','block','crash'))
);

CREATE TABLE c_state (
  entity_id   INTEGER PRIMARY KEY REFERENCES entity(id) ON DELETE CASCADE,
  shape       TEXT    NOT NULL,          -- Elpi type name; checked at booking
  initial     TEXT    NOT NULL DEFAULT '{}',
  current     TEXT                        -- NULL means never run or reset
);

-- An actor is deterministic code, not a model call. No token budget belongs
-- here: the booker spends tokens deciding what to book, the actor spends wall
-- time and memory doing it.
CREATE TABLE c_budget (
  entity_id   INTEGER PRIMARY KEY REFERENCES entity(id) ON DELETE CASCADE,
  wall_ms     INTEGER NOT NULL DEFAULT 30000,
  mem_bytes   INTEGER NOT NULL DEFAULT 268435456,
  msg_quota   INTEGER NOT NULL DEFAULT 1000,   -- messages per gig
  gigs_per_hr INTEGER NOT NULL DEFAULT 60
);

-- ------------------------------------------- kind 2: capability components
--
-- OBJECT-CAPABILITY, NOT ACCESS-CONTROL. This is the distinction that matters.
--
-- An ACL would say: the actor asks for `shell`, the gate checks whether it may,
-- the runtime allows or denies. That leaves a runtime check to get wrong.
--
-- Instead these rows are BUILD INSTRUCTIONS. At spawn, the runtime constructs a
-- capability record containing exactly the claimed tools and hands it to the
-- actor's behavior function. An unclaimed tool is not a denied tool -- it is
-- not a field. Calling it is a type error at compile time, not a refusal at
-- run time. There is no check because there is no reference.
--
-- `scope` is likewise not a pattern to match. It parameterises construction:
-- `fs_read` is built around a directory handle rooted where you rooted it, with
-- no parent reference to walk. The actor never holds a path that could be wrong.

CREATE TABLE capability (
  name             TEXT PRIMARY KEY,
  ctor             TEXT NOT NULL,        -- constructor in the frozen core
  envelope         TEXT NOT NULL,        -- outer bound, human-authored
  side_effecting   INTEGER NOT NULL DEFAULT 0,
  requires_booking INTEGER NOT NULL DEFAULT 0   -- 1 = a human approves each gig
);

CREATE TABLE c_capability (
  entity_id   INTEGER NOT NULL REFERENCES entity(id) ON DELETE CASCADE,
  capability  TEXT    NOT NULL REFERENCES capability(name),
  -- Constructor argument. Must narrow the envelope; the gate rejects widening
  -- BEFORE construction, because after construction there is nothing to widen.
  scope       TEXT,
  PRIMARY KEY (entity_id, capability)
);

-- ------------------------------------------------ kind 3: policy components

CREATE TABLE c_policy (
  entity_id   INTEGER NOT NULL REFERENCES entity(id) ON DELETE CASCADE,
  predicate   TEXT    NOT NULL,
  module      TEXT    NOT NULL CHECK (module IN ('elpi','swipl')),
  role        TEXT    NOT NULL CHECK (role IN ('booking','disposition','routing')),
  PRIMARY KEY (entity_id, predicate, role)
);

-- ------------------------------------------------------- write ownership
-- Encapsulation was never the point; exclusive write access was. One system per
-- component table. "No two systems declare write on the same component" is a
-- two-line Elpi check over this table.

CREATE TABLE component_owner (
  component  TEXT PRIMARY KEY,
  system     TEXT NOT NULL
);

INSERT INTO component_owner (component, system) VALUES
  ('c_inbox','delivery'), ('c_state','step'), ('c_budget','accountant'),
  ('c_capability','composer'), ('c_policy','composer');

-- --------------------------------------------------------------- the ledger
-- Prediction is a separate table from outcome, written earlier, and the schema
-- makes it awkward to do otherwise. A log of what happened without a log of
-- what was expected is history, not an error signal.

CREATE TABLE gig (
  id             INTEGER PRIMARY KEY,
  entity_id      INTEGER NOT NULL REFERENCES entity(id),
  composition_sig TEXT   NOT NULL,       -- hash of the claimed component set
  booked_at      INTEGER NOT NULL,
  started_at     INTEGER,
  ended_at       INTEGER,
  tier           TEXT NOT NULL CHECK (tier IN ('in_process','subprocess')),
  -- Which system prompt this ran under. Not decoration: a gig executed under
  -- one soul is not evidence about a system running another.
  soul_version   TEXT
);

CREATE TABLE gig_prediction (
  gig_id          INTEGER PRIMARY KEY REFERENCES gig(id) ON DELETE CASCADE,
  predicts        TEXT    NOT NULL,
  falsifiable_by  TEXT    NOT NULL,
  made_at         INTEGER NOT NULL
);

CREATE TABLE gig_outcome (
  gig_id      INTEGER PRIMARY KEY REFERENCES gig(id) ON DELETE CASCADE,
  outcome     TEXT    NOT NULL CHECK (outcome IN
                ('completed','failed','human_rejected','budget_exceeded','starved')),
  matched     TEXT    NOT NULL CHECK (matched IN ('yes','partial','no')),
  observed_at INTEGER NOT NULL,
  note        TEXT
);

-- Booking verdicts, including refusals. The refusals are the training signal
-- most systems throw away.
CREATE TABLE booking_verdict (
  id              INTEGER PRIMARY KEY,
  entity_id       INTEGER REFERENCES entity(id),
  composition_sig TEXT    NOT NULL,
  decision        TEXT    NOT NULL CHECK (decision IN ('book','queue','refuse')),
  reasons         TEXT    NOT NULL,
  decided_at      INTEGER NOT NULL,
  -- 'conditions' is the in-process structural evaluator (ocaml/lib/conditions.ml),
  -- which refuses malformed compositions before elpi is ever invoked. It gets its
  -- own value rather than borrowing 'elpi' because this column is provenance: a
  -- refusal attributed to an engine that never ran makes every later question
  -- about WHERE a rule lives unanswerable. Adding a value is cheap; a provenance
  -- column that lies is not recoverable.
  decided_by      TEXT    NOT NULL
                  CHECK (decided_by IN ('conditions','elpi','human')),
  -- WHAT IS THIS VERDICT A FACT ABOUT? Without this column the table does two
  -- incompatible jobs at once: it is the audit log of every refusal AND the dead
  -- set that `not_refused_before` reads. Those are different sets, and
  -- conflating them was a live bug -- refusing a proposal because the envelope
  -- the human authored this time did not cover the kit wrote a 'refuse' row
  -- against the FORM, and the form (whose identity deliberately ignores
  -- envelopes) could then never book again. A transient refusal killed a shape
  -- permanently.
  --
  --   composition  a property of the shape itself: a structural failure from
  --                conditions.ml. Belongs in the dead set, and permanence is
  --                correct -- fixing a structural problem changes cap_set,
  --                policy_set or state_shape, which makes it a different form.
  --   proposal     a property of THIS attempt: the envelope was too narrow,
  --                expired, exhausted, or left no wall clock. Says nothing
  --                about the shape.
  --   kit          a property of the kit: it is malformed and every composition
  --                assembled from it is affected, but the composition that
  --                happened to reach for it is not itself dead.
  attaches_to     TEXT    NOT NULL DEFAULT 'composition'
                  CHECK (attaches_to IN ('composition','proposal','kit'))
);

-- Crash facts. The disposition query cannot fire without these; a policy that
-- is a derivation instead of a field needs its inputs published.
CREATE TABLE crash (
  id          INTEGER PRIMARY KEY,
  entity_id   INTEGER NOT NULL REFERENCES entity(id),
  gig_id      INTEGER REFERENCES gig(id),
  fault_class TEXT    NOT NULL,
  retry_index INTEGER NOT NULL DEFAULT 0,
  chosen      TEXT,                       -- disposition actually applied
  recovered   INTEGER,                    -- did it hold? NULL until known
  at          INTEGER NOT NULL
);

-- ------------------------------------------------------------------- views

-- Archetype query. This is what a "system" iterates.
CREATE VIEW v_archetype AS
SELECT e.id, e.name, e.provenance,
       group_concat(cc.capability) AS caps,
       (c_state.entity_id IS NOT NULL) AS has_state,
       (c_inbox.entity_id IS NOT NULL) AS has_inbox
FROM entity e
LEFT JOIN c_capability cc ON cc.entity_id = e.id
LEFT JOIN c_state ON c_state.entity_id = e.id
LEFT JOIN c_inbox ON c_inbox.entity_id = e.id
WHERE e.retired_at IS NULL
GROUP BY e.id;

-- Flat facts for Aleph. One row per (composition, outcome) so ILP can search
-- for rules over SHAPE, not just over result.
CREATE VIEW v_aleph_facts AS
SELECT g.id                AS gig_id,
       e.name              AS entity,
       e.provenance        AS provenance,
       g.tier              AS tier,
       g.composition_sig   AS shape,
       (SELECT count(*) FROM c_capability WHERE entity_id = e.id) AS n_caps,
       (SELECT count(*) FROM c_capability cc JOIN capability c ON c.name = cc.capability
         WHERE cc.entity_id = e.id AND c.side_effecting = 1)      AS n_effectful,
       (SELECT count(*) FROM c_policy WHERE entity_id = e.id)     AS n_policies,
       gp.predicts IS NOT NULL AS had_prediction,
       go.matched          AS matched,
       go.outcome          AS outcome,
       (go.outcome = 'completed') AS good
FROM gig g
JOIN entity e ON e.id = g.entity_id
LEFT JOIN gig_prediction gp ON gp.gig_id = g.id
LEFT JOIN gig_outcome    go ON go.gig_id = g.id;

-- Acceptance rate, watched in BOTH directions. Under ~0.2 the composer is
-- thrashing. Over ~0.9 you have become a rubber stamp, which is how HITL
-- systems actually die -- approval fatigue, not bad proposals.
CREATE VIEW v_acceptance AS
SELECT decided_by,
       count(*)                                                   AS n,
       round(1.0 * sum(decision = 'book') / count(*), 3)          AS rate
FROM (SELECT * FROM booking_verdict ORDER BY decided_at DESC LIMIT 30)
GROUP BY decided_by;

-- ==========================================================================
-- FORM IDENTITY AND CONFIDENCE
--
-- Human review is the source of confidence, so confidence is measured per
-- FORM, not per entity or per gig.
--
-- Cold start uses a FIXED denominator of 15. Three-for-three reads as 0.20,
-- not 1.00, so the 0.80 auto-book threshold is unreachable until 12 matches
-- land. The prior IS the denominator -- no separate minimum-sample rule.
--
-- Past 15 it becomes a WINDOWED rate over the last 15. An unbounded lifetime
-- rate never recovers from drift: 95-of-100 that starts failing needs five
-- straight losses to reach 0.90 and keeps auto-booking the whole way down.
-- ==========================================================================

CREATE TABLE form (
  sig            TEXT PRIMARY KEY,   -- hash of capability set + policy set + state shape
  cap_set        TEXT NOT NULL,       -- sorted capability names, scope-independent
  policy_set     TEXT NOT NULL,
  state_shape    TEXT NOT NULL,
  -- Identity ignores NARROWED scopes and budget numbers. A WIDENED scope is a
  -- different form and starts cold: widening is the dangerous edit, and it is
  -- the one place accumulated confidence must not transfer.
  widen_epoch    INTEGER NOT NULL DEFAULT 0,
  first_seen     INTEGER NOT NULL
);

CREATE TABLE form_review (
  id          INTEGER PRIMARY KEY,
  form_sig    TEXT    NOT NULL REFERENCES form(sig),
  gig_id      INTEGER REFERENCES gig(id),
  -- matched = prediction held AND critic passed AND judge failed to refute.
  -- Any one of the three failing burns a slot. The judge can therefore spend
  -- confidence without spending the human's time, which is the point of it.
  prediction_held TEXT NOT NULL CHECK (prediction_held IN ('yes','partial','no')),
  critic_passed   INTEGER NOT NULL,
  judge_refuted   INTEGER NOT NULL,   -- adversarial: refuted-under-uncertainty
  human_reviewed  INTEGER NOT NULL DEFAULT 0,
  -- Confidence is scoped to the soul it was measured under. Editing the
  -- prompt resets forms to cold start, for the same reason widening a scope
  -- does: the bound changed, so the evidence is about a different system.
  soul_version    TEXT,
  at              INTEGER NOT NULL
);

CREATE VIEW v_form_review_scored AS
SELECT fr.*,
       CASE WHEN fr.critic_passed = 0 OR fr.judge_refuted = 1 THEN 0.0
            WHEN fr.prediction_held = 'yes'     THEN 1.0
            WHEN fr.prediction_held = 'partial' THEN 0.5
            ELSE 0.0 END AS score
FROM form_review fr;

CREATE VIEW v_form_confidence AS
WITH ranked AS (
  SELECT form_sig, score,
         row_number() OVER (PARTITION BY form_sig ORDER BY at DESC) AS recency
  FROM v_form_review_scored
), agg AS (
  SELECT form_sig,
         count(*)                                    AS n_total,
         sum(score)                                  AS life_matched,
         sum(CASE WHEN recency <= 15 THEN score END) AS win_matched,
         count(CASE WHEN recency <= 15 THEN 1 END)   AS win_n,
         min(CASE WHEN recency <= 15 THEN score END) AS win_worst
  FROM ranked GROUP BY form_sig
), rates AS (
  SELECT form_sig, n_total, win_matched, win_n, win_worst,
         -- cold start pins the denominator at 15 so a perfect short record
         -- cannot reach the threshold. the prior IS the denominator.
         win_matched / (CASE WHEN n_total < 15 THEN 15.0 ELSE win_n END) AS window_rate,
         life_matched / CASE WHEN n_total < 15 THEN 15.0 ELSE n_total END AS life_rate
  FROM agg
)
SELECT form_sig, n_total,
       round(life_rate, 3)   AS lifetime,
       round(window_rate, 3) AS window15,
       -- the conservative one always wins: a long mediocre record is not
       -- laundered by one clean window, and a long good record does not
       -- survive a broken one.
       round(min(life_rate, window_rate), 3) AS certainty,
       CASE
         WHEN n_total < 15                                THEN 'C_needs_review'
         WHEN win_worst >= 1.0 AND min(life_rate, window_rate) >= 0.80
                                                          THEN 'A_autopass'
         WHEN min(life_rate, window_rate) >= 0.80         THEN 'B_last_review'
         ELSE 'C_needs_review'
       END AS band
FROM rates;

-- ==========================================================================
-- TRACE
--
-- Spans are a ledger TABLE, not a log file. A trace that cannot be joined
-- against outcomes teaches you nothing -- you can see that a gig was slow and
-- not whether slow gigs fail more often.
--
-- Emitted by the runtime, never by behaviors. A behavior that wrote its own
-- trace could write a flattering one, and the trace is evidence.
-- ==========================================================================

CREATE TABLE span (
  id         INTEGER NOT NULL,
  gig_id     INTEGER NOT NULL REFERENCES gig(id) ON DELETE CASCADE,
  parent     INTEGER,                      -- NULL for the gig's root span
  name       TEXT    NOT NULL,
  phase      TEXT,                          -- the declared phase it sat in
  duration_ms INTEGER NOT NULL DEFAULT -1,  -- -1 = never closed
  outcome    TEXT,
  breach     TEXT,                          -- Terms or Phases breach, if any
  PRIMARY KEY (gig_id, id)
);

CREATE INDEX span_by_gig ON span(gig_id);

-- An unclosed span is a control-flow bug that a passing gig can hide.
CREATE VIEW v_unclosed_spans AS
SELECT s.gig_id, e.name AS entity, s.name AS span, s.phase
FROM span s JOIN gig g ON g.id = s.gig_id JOIN entity e ON e.id = g.entity_id
WHERE s.duration_ms < 0;

-- The join the trace exists for: does time spent in a phase predict outcome?
CREATE VIEW v_phase_cost AS
SELECT s.phase,
       count(*)                       AS spans,
       round(avg(s.duration_ms), 1)   AS avg_ms,
       max(s.duration_ms)             AS max_ms,
       sum(s.breach IS NOT NULL)      AS breaches,
       round(1.0 * sum(o.outcome = 'completed') / count(*), 3) AS completion_rate
FROM span s
JOIN gig g ON g.id = s.gig_id
LEFT JOIN gig_outcome o ON o.gig_id = g.id
WHERE s.phase IS NOT NULL
GROUP BY s.phase;

-- Confidence counted only under the CURRENT soul. Compare against
-- v_form_confidence to see how much of a form's record a prompt edit discards.
CREATE VIEW v_form_confidence_scoped AS
WITH cur AS (SELECT version FROM soul WHERE retired_at IS NULL LIMIT 1),
ranked AS (
  SELECT fr.form_sig,
         CASE WHEN fr.critic_passed = 0 OR fr.judge_refuted = 1 THEN 0.0
              WHEN fr.prediction_held = 'yes' THEN 1.0
              WHEN fr.prediction_held = 'partial' THEN 0.5
              ELSE 0.0 END AS score,
         row_number() OVER (PARTITION BY fr.form_sig ORDER BY fr.at DESC) AS recency
  FROM form_review fr, cur
  WHERE fr.soul_version IS NOT NULL AND fr.soul_version = cur.version
)
SELECT form_sig,
       count(*) AS n_under_current_soul,
       round(sum(CASE WHEN recency <= 15 THEN score END) /
             (CASE WHEN count(*) < 15 THEN 15.0
                   ELSE count(CASE WHEN recency <= 15 THEN 1 END) END), 3) AS certainty
FROM ranked GROUP BY form_sig;
