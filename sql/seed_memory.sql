-- Seed for the active-context memory path (gigwerk context).
--
--   sqlite3 gigwerk.db ".read sql/schema.sql" ".read sql/persist.sql" \
--                      ".read sql/soul.sql"   ".read sql/memory.sql"  \
--                      ".read sql/seed_memory.sql"
--
-- Separate from seed.sql on purpose: seed.sql seeds the BOOKING path and loads
-- against schema.sql + persist.sql alone, so putting soul/ruling/SARCASM rows
-- there would make it error whenever soul.sql and memory.sql are not also
-- loaded. This file names its own dependencies and seeds the MEMORY path.
--
-- The rows are chosen so `gigwerk context` shows every band doing its job:
-- pinned material that never evicts, docs ranked by affect (the hazardous
-- incident out-ranks the routine note), and -- once the bands are shrunk with
-- --immediate/--working -- overflow that condenses to its stored digest rather
-- than being dropped.

-- ------------------------------------------------------------------- soul
-- One live version. Pinned into immediate, never contracted.
INSERT OR IGNORE INTO soul (version, body, parent, adopted_at, adopted_by, rationale)
VALUES ('v1',
        'You compose actors. You do not write tools or behavior. You are the only thing here that calls a model.',
        NULL, strftime('%s','now'), 'human', 'initial adoption');

-- ---------------------------------------------------------------- rulings
-- What the human has decided. Live rulings are pinned; a retired one is kept in
-- the ledger but stays OUT of the active window.
INSERT OR IGNORE INTO mem_ruling (subject, predicate, object, rationale, at)
VALUES
  ('scribe', 'requires', 'human_verdict_per_gig',
   'fs_write is side-effecting and booking-gated', strftime('%s','now')),
  ('actors', 'may_not_hold', 'retrieve',
   'a non-deterministic actor breaks every claim the design rests on', strftime('%s','now'));

-- ------------------------------------------------------------------ SARCASM
-- One row per Reconstruct.doc. `full` is the verbatim original; `digest` is the
-- contracted form SARCASM keeps, reused as the working-band condensation. vec is
-- a placeholder Embed.of_string parses cleanly; the context assembler ranks on
-- affect, not the vector, so a short vec is enough here.
--
-- affect columns: surprise, hazard, novelty, cost, dissonance, valence.

INSERT OR IGNORE INTO sarcasm_doc
  (id, digest, full, vec,
   affect_surprise, affect_hazard, affect_novelty, affect_cost, affect_dissonance, affect_valence)
VALUES
  -- The hazardous one: highest salience, so it survives into immediate first.
  ('incident-scribe',
   'Incident: [[scribe]] hit a budget kill mid-write.',
   'Incident: scribe hit a budget kill mid-write. The gig was booked with a 60s wall and a 1-action budget. The action spent its whole allowance before emitting a terminal phase, so the parent recorded budget_exceeded and matched=no. The full write never landed, and the partial file was left in the work root. This is the case the wall clock exists to bound.',
   '0.5,0.1,0.05',
   0.5, 0.9, 0.2, 0.6, 0.0, -1.0),

  -- The surprising, positive one: mid salience.
  ('onboarding-scope',
   'Onboarding: narrow [[fs-read-scope]] harder than the envelope needs.',
   'Onboarding: narrow the fs_read scope harder than the envelope needs. The envelope permits the whole work root, but a critic that only ever reads one artifact should be scoped to that artifact''s directory, not the root. Least authority is computed at booking, not hoped for at runtime. The refusals that come from this are the mechanism working, not friction to route around.',
   '0.3,0.2,0.1',
   0.8, 0.0, 0.5, 0.1, 0.0, 1.0),

  -- The routine one: low salience, first to spill and condense.
  ('routine-forms',
   'Routine: [[forms]] listing was quiet this week.',
   'Routine: the forms listing was quiet this week. No new shapes reached a-autopass, no form dropped out of its band, and the acceptance rate held around the middle of its range. Nothing here needs a decision; it is noted so a later week that is not quiet has something to be surprising against.',
   '0.02,0.01,0.4',
   0.0, 0.0, 0.1, 0.2, 0.0, 0.0),

  -- A plain, uncontracted doc (full IS NULL): its digest IS its full form, so
  -- on spill there is nothing to reuse and nothing to re-contract to.
  ('note-plain',
   'Plain note with no retained original and no links.',
   NULL,
   '0.1,0.1,0.1',
   0.1, 0.0, 0.3, 0.1, 0.0, 0.0);
