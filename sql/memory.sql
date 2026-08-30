-- ==========================================================================
-- THREE MEMORIES
--
-- Three systems, not one table with a `kind` column. They are separate because
-- they differ in the two things that matter: WHO MAY WRITE, and WHO WINS WHEN
-- THEY DISAGREE. A store where a model's guess and a recorded outcome sit in
-- the same rows with the same authority is one store, however you label it.
--
--   RECORD   what happened      runtime-authored   append-only, immutable
--   RULING   what was decided   human-authored     versioned, supersedable
--   READING  what was inferred  model-authored     decaying, always attributed
--
-- All three make (subject, predicate, object) claims, which is what makes
-- contradiction mechanically detectable instead of a matter of opinion: same
-- subject and predicate, different object.
-- ==========================================================================

-- 1 ------------------------------------------------------------- RECORD
-- What happened. The runtime is the only writer, and there is no UPDATE path:
-- a record that can be edited is a record that can be edited to agree with a
-- belief. Correction happens by writing a later record, not by revising an
-- earlier one.

CREATE TABLE mem_record (
  id        INTEGER PRIMARY KEY,
  gig_id    INTEGER REFERENCES gig(id),
  subject   TEXT NOT NULL,
  predicate TEXT NOT NULL,
  object    TEXT NOT NULL,
  at        INTEGER NOT NULL,
  source    TEXT NOT NULL DEFAULT 'runtime' CHECK (source = 'runtime')
);

CREATE TRIGGER mem_record_immutable
BEFORE UPDATE ON mem_record
BEGIN
  SELECT RAISE(ABORT, 'mem_record is append-only; write a later record instead');
END;

CREATE TRIGGER mem_record_no_delete
BEFORE DELETE ON mem_record
BEGIN
  SELECT RAISE(ABORT, 'mem_record is append-only; records are not deleted');
END;

-- 2 ------------------------------------------------------------- RULING
-- What a human decided. Supersedable but not erasable: an overturned ruling
-- stays, because "we used to think X" is the context that explains half the
-- decisions in any system.

CREATE TABLE mem_ruling (
  id         INTEGER PRIMARY KEY,
  subject    TEXT NOT NULL,
  predicate  TEXT NOT NULL,
  object     TEXT NOT NULL,
  rationale  TEXT NOT NULL,          -- why, in the human's words. required.
  at         INTEGER NOT NULL,
  supersedes INTEGER REFERENCES mem_ruling(id),
  retired_at INTEGER,                 -- set when superseded; row stays
  decided_by TEXT NOT NULL DEFAULT 'human' CHECK (decided_by = 'human')
);

-- Superseding retires the old ruling rather than deleting it.
CREATE TRIGGER mem_ruling_supersede
AFTER INSERT ON mem_ruling
WHEN NEW.supersedes IS NOT NULL
BEGIN
  UPDATE mem_ruling SET retired_at = NEW.at
   WHERE id = NEW.supersedes AND retired_at IS NULL;
END;

-- 3 ------------------------------------------------------------ READING
-- What the model inferred. Decays, is always attributed, and is never
-- load-bearing on its own.
--
-- soul_version is not optional. A reading produced under one system prompt is
-- not evidence about a system running a different one.

CREATE TABLE mem_reading (
  id             INTEGER PRIMARY KEY,
  subject        TEXT NOT NULL,
  predicate      TEXT NOT NULL,
  object         TEXT NOT NULL,
  basis          TEXT NOT NULL,      -- what it was inferred FROM. required.
  confidence     REAL NOT NULL CHECK (confidence > 0.0 AND confidence <= 1.0),
  at             INTEGER NOT NULL,
  model          TEXT NOT NULL,
  soul_version   TEXT NOT NULL,
  half_life_days REAL NOT NULL DEFAULT 30.0,
  retired_at     INTEGER
);

-- Present confidence, decayed. A reading nobody has reconfirmed in a year
-- should not argue with the same force it did on the day it was written.
CREATE VIEW v_reading_now AS
SELECT r.*,
       r.confidence * exp( -1.0 * (strftime('%s','now') - r.at)
                           / (r.half_life_days * 86400.0) ) AS confidence_now
FROM mem_reading r
WHERE r.retired_at IS NULL;

-- ---------------------------------------------------------- PRECEDENCE
--
-- Resolution is by KIND, not by recency. This is the whole reason the three
-- are separate:
--
--   reading vs record   -> record wins, reading is stale or wrong
--   reading vs ruling   -> ruling wins, the reading was never authoritative
--   record  vs ruling   -> INCIDENT. the world diverged from policy, and that
--                          is the interesting case. It surfaces; it does not
--                          silently resolve.

CREATE VIEW v_belief_conflict AS
-- reading contradicted by a record
SELECT 'reading_vs_record' AS kind, rd.subject, rd.predicate,
       rd.object AS claimed, rc.object AS actual,
       'record' AS winner,
       'retire or rewrite the reading' AS action
FROM mem_reading rd
JOIN mem_record rc ON rc.subject = rd.subject AND rc.predicate = rd.predicate
WHERE rd.retired_at IS NULL AND rc.object <> rd.object

UNION ALL
-- reading contradicted by a live ruling
SELECT 'reading_vs_ruling', rd.subject, rd.predicate,
       rd.object, ru.object, 'ruling',
       'retire the reading; it was never authoritative'
FROM mem_reading rd
JOIN mem_ruling ru ON ru.subject = rd.subject AND ru.predicate = rd.predicate
WHERE rd.retired_at IS NULL AND ru.retired_at IS NULL AND ru.object <> rd.object

UNION ALL
-- the interesting one: what happened is not what was decided
SELECT 'record_vs_ruling', rc.subject, rc.predicate,
       rc.object, ru.object, 'INCIDENT',
       'the world diverged from policy -- decide which is wrong'
FROM mem_record rc
JOIN mem_ruling ru ON ru.subject = rc.subject AND ru.predicate = rc.predicate
WHERE ru.retired_at IS NULL AND rc.object <> ru.object;

-- What the harness actually believes, once precedence is applied.
CREATE VIEW v_belief AS
SELECT subject, predicate, object, 'ruling' AS basis, 1.0 AS weight
  FROM mem_ruling WHERE retired_at IS NULL
UNION ALL
SELECT subject, predicate, object, 'record', 1.0
  FROM mem_record
 WHERE (subject, predicate) NOT IN (SELECT subject, predicate FROM mem_ruling WHERE retired_at IS NULL)
UNION ALL
SELECT subject, predicate, object, 'reading', confidence_now
  FROM v_reading_now
 WHERE (subject, predicate) NOT IN (SELECT subject, predicate FROM mem_record)
   AND (subject, predicate) NOT IN (SELECT subject, predicate FROM mem_ruling WHERE retired_at IS NULL);
