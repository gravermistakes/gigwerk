-- ==========================================================================
-- THE SOUL FILE
--
-- The composer's system prompt. Frozen, versioned, content-addressed.
--
-- Two rules, and the second is the one people get wrong:
--
-- 1. The model may PROPOSE a diff. It may not apply one. Same shape as every
--    other mutable surface here -- propose, human approves, version lands.
--
-- 2. CHANGING THE SOUL INVALIDATES CONFIDENCE.
--
--    This follows from the rule already in force: widening a scope resets a
--    form to cold start, because confidence measured under one set of bounds
--    says nothing about another. The soul is a bound. Reviews collected under
--    soul v1 are evidence about a system that no longer exists.
--
--    Without this, you edit the prompt and every form's band silently becomes
--    a statement about a different machine -- while still reading 0.93 and
--    still auto-booking.
-- ==========================================================================

CREATE TABLE soul (
  version     TEXT PRIMARY KEY,      -- content hash of the body
  body        TEXT NOT NULL,
  parent      TEXT REFERENCES soul(version),
  adopted_at  INTEGER NOT NULL,
  adopted_by  TEXT NOT NULL DEFAULT 'human' CHECK (adopted_by = 'human'),
  rationale   TEXT NOT NULL,
  retired_at  INTEGER
);

CREATE TRIGGER soul_immutable_body
BEFORE UPDATE OF body, version ON soul
BEGIN
  SELECT RAISE(ABORT, 'a soul version is content-addressed; adopt a new one');
END;

CREATE TRIGGER soul_retire_parent
AFTER INSERT ON soul
WHEN NEW.parent IS NOT NULL
BEGIN
  UPDATE soul SET retired_at = NEW.adopted_at
   WHERE version = NEW.parent AND retired_at IS NULL;
END;

-- Proposed edits. The model writes here and nowhere else in this file.
CREATE TABLE soul_proposal (
  id          INTEGER PRIMARY KEY,
  from_version TEXT NOT NULL REFERENCES soul(version),
  diff        TEXT NOT NULL,
  argument    TEXT NOT NULL,        -- why the model thinks this helps
  proposed_at INTEGER NOT NULL,
  verdict     TEXT CHECK (verdict IN ('adopted','declined')),
  decided_at  INTEGER
);

CREATE VIEW v_soul_current AS
SELECT version, body, adopted_at, rationale FROM soul WHERE retired_at IS NULL;
