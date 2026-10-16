-- ==========================================================================
-- THE SOUL FILE
--
-- The agent's system prompt. Frozen, versioned, content-addressed.
--
-- Three rules, and the third is the one people get wrong:
--
-- 1. A SOUL TAKES TWO SIGNATURES. The agent's and the human's, both, before
--    the version is live. Neither party can adopt one alone.
--
--    A soul the agent did not sign is imposed on it. A soul the human did not
--    sign is the machine rewriting its own obligations. Requiring both makes the
--    document what it claims to be -- obligations the two parties hold each other
--    to -- rather than an instruction one hands the other.
--
--    A version with ONE signature is a PROPOSAL, not a soul. It sits in
--    v_soul_pending and the running program never reads it, because
--    v_soul_current requires the pair. That is the mechanism, not a
--    convention: nothing has to remember to check.
--
-- 2. A SIGNATURE IS NOT RETRACTABLE. Once given it stands. Withdrawing assent
--    means adopting a new version, which the other party must also sign --
--    not quietly unsigning the one in force. Enforced by trigger.
--
-- 3. CHANGING THE SOUL INVALIDATES CONFIDENCE.
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
  version         TEXT PRIMARY KEY,   -- content hash of the body
  body            TEXT NOT NULL,
  parent          TEXT REFERENCES soul(version),
  proposed_at     INTEGER NOT NULL,
  rationale       TEXT NOT NULL,

  -- The two signatures. NULL until signed; a name, not a boolean, because
  -- "who" is the part worth keeping.
  agent_signature TEXT,
  agent_signed_at INTEGER,
  human_signature TEXT,
  human_signed_at INTEGER,

  retired_at      INTEGER,

  -- A signature is a name AND a time or it is neither. Half a signature is
  -- not a weaker signature, it is a malformed row.
  CHECK ((agent_signature IS NULL) = (agent_signed_at IS NULL)),
  CHECK ((human_signature IS NULL) = (human_signed_at IS NULL))
);

CREATE TRIGGER soul_immutable_body
BEFORE UPDATE OF body, version ON soul
BEGIN
  SELECT RAISE(ABORT, 'a soul version is content-addressed; adopt a new one');
END;

-- Rule 2, mechanically.
CREATE TRIGGER soul_signature_is_not_retractable
BEFORE UPDATE ON soul
WHEN (OLD.agent_signature IS NOT NULL AND NEW.agent_signature IS NULL)
  OR (OLD.human_signature IS NOT NULL AND NEW.human_signature IS NULL)
BEGIN
  SELECT RAISE(ABORT,
    'a signature is not retractable; adopt a new version instead');
END;

-- Adoption is the SECOND signature, not the insert.
--
-- The old trigger retired the parent on INSERT. Under two signatures that is
-- a hole: inserting a half-signed proposal would retire the soul in force and
-- leave the agency with no current soul at all, since the new one is not yet
-- adopted. So the parent retires when the pair completes -- whichever way the
-- row got there.
CREATE TRIGGER soul_retire_parent_on_countersign
AFTER UPDATE ON soul
WHEN NEW.parent IS NOT NULL
 AND NEW.agent_signature IS NOT NULL
 AND NEW.human_signature IS NOT NULL
 AND (OLD.agent_signature IS NULL OR OLD.human_signature IS NULL)
BEGIN
  UPDATE soul
     SET retired_at = max(NEW.agent_signed_at, NEW.human_signed_at)
   WHERE version = NEW.parent AND retired_at IS NULL;
END;

CREATE TRIGGER soul_retire_parent_on_signed_insert
AFTER INSERT ON soul
WHEN NEW.parent IS NOT NULL
 AND NEW.agent_signature IS NOT NULL
 AND NEW.human_signature IS NOT NULL
BEGIN
  UPDATE soul
     SET retired_at = max(NEW.agent_signed_at, NEW.human_signed_at)
   WHERE version = NEW.parent AND retired_at IS NULL;
END;

-- Proposed edits. Either party may open one; adoption still needs both names
-- on the soul row itself.
CREATE TABLE soul_proposal (
  id          INTEGER PRIMARY KEY,
  from_version TEXT NOT NULL REFERENCES soul(version),
  diff        TEXT NOT NULL,
  argument    TEXT NOT NULL,        -- why the proposer thinks this helps
  proposed_by TEXT NOT NULL CHECK (proposed_by IN ('agent','human')),
  proposed_at INTEGER NOT NULL,
  verdict     TEXT CHECK (verdict IN ('adopted','declined')),
  decided_at  INTEGER
);

-- THE live soul: both signatures, not retired. This is what the running
-- program reads, so a half-signed version cannot reach it.
CREATE VIEW v_soul_current AS
SELECT version, body, rationale,
       max(agent_signed_at, human_signed_at) AS adopted_at
  FROM soul
 WHERE retired_at IS NULL
   AND agent_signature IS NOT NULL
   AND human_signature IS NOT NULL;

-- Signed by one party, waiting on the other. Visible, and deliberately not
-- readable as the soul.
CREATE VIEW v_soul_pending AS
SELECT version, body, rationale, proposed_at,
       CASE WHEN agent_signature IS NULL THEN 'agent' ELSE 'human' END
         AS awaiting
  FROM soul
 WHERE retired_at IS NULL
   AND (agent_signature IS NULL) <> (human_signature IS NULL);
