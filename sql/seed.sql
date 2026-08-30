-- Minimum store contents for the booking path to run end to end.
--
--   sqlite3 gigwerk.db ".read sql/schema.sql" ".read sql/persist.sql" ".read sql/seed.sql"
--
-- Three entities, chosen so each demonstrates a DIFFERENT outcome of the path
-- rather than three variations on success:
--
--   echo    books with an empty envelope. The only actor for which claiming
--           nothing is correct, so it proves the path itself works without any
--           capability in it.
--   critic  needs read+query, so it REFUSES against an empty envelope and books
--           only when a human authors one that covers it. This is the fit check
--           being load-bearing rather than decorative.
--   scribe  claims a capability whose requires_booking is 1, so Conditions
--           returns Queue and no terms are ever issued. Agent provenance, so it
--           also exercises tier_matches.

INSERT OR IGNORE INTO capability (name, ctor, envelope, side_effecting, requires_booking)
VALUES
  -- Envelopes are human-authored outer bounds. A claim must be AT or BENEATH
  -- one of these; the segment-prefix check in booking.ml is what enforces it.
  ('fs_read',      'Caps.fs_read',   '/home/claude/gigwerk/work', 0, 0),
  ('sqlite_query', 'Caps.sqlite_ro', 'gigwerk.db',                0, 0),
  -- Side-effecting AND booking-gated: the one capability in the seed that a
  -- human has to approve per gig.
  ('fs_write',     'Caps.fs_write',  '/home/claude/gigwerk/work', 1, 1);

INSERT OR IGNORE INTO entity (name, preset, provenance, created_at)
VALUES
  ('echo',   'echo',    'human', strftime('%s','now')),
  ('critic', 'critic',  'human', strftime('%s','now')),
  ('scribe', 'scribe',  'agent', strftime('%s','now'));

-- c_state.shape must agree with the kit's state_shape or the composition does
-- not resolve; booking.ml's shape_wellformed reads this row.
INSERT OR IGNORE INTO c_state (entity_id, shape, initial)
SELECT id, 'last_message', '{}' FROM entity WHERE name = 'echo';
INSERT OR IGNORE INTO c_state (entity_id, shape, initial)
SELECT id, 'verdict_log', '{}'  FROM entity WHERE name = 'critic';
INSERT OR IGNORE INTO c_state (entity_id, shape, initial)
SELECT id, 'notes', '{}'        FROM entity WHERE name = 'scribe';

-- Wall clock is the bound the child cannot lie about, so it is per entity and
-- not per kit: booking takes min(kit ask, terms remaining) and the runner takes
-- min of that and this.
INSERT OR IGNORE INTO c_budget (entity_id, wall_ms)
SELECT id, 250   FROM entity WHERE name = 'echo';
INSERT OR IGNORE INTO c_budget (entity_id, wall_ms)
SELECT id, 5000  FROM entity WHERE name = 'critic';
INSERT OR IGNORE INTO c_budget (entity_id, wall_ms)
SELECT id, 60000 FROM entity WHERE name = 'scribe';

INSERT OR IGNORE INTO c_inbox (entity_id, capacity)
SELECT id, 64 FROM entity;

-- echo claims nothing. That row's absence IS the claim.
INSERT OR IGNORE INTO c_capability (entity_id, capability, scope)
SELECT id, 'fs_read', '/home/claude/gigwerk/work' FROM entity WHERE name = 'critic';
INSERT OR IGNORE INTO c_capability (entity_id, capability, scope)
SELECT id, 'sqlite_query', '' FROM entity WHERE name = 'critic';
INSERT OR IGNORE INTO c_capability (entity_id, capability, scope)
SELECT id, 'fs_write', '/home/claude/gigwerk/work/out' FROM entity WHERE name = 'scribe';

INSERT OR IGNORE INTO c_policy (entity_id, predicate, module, role)
SELECT id, 'bookable', 'elpi', 'booking' FROM entity;
