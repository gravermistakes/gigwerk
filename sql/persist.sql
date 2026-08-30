-- ==========================================================================
-- PERSISTENCE FOR THE FOUR IN-MEMORY MODULES
--
-- Embed, Reconstruct, Introspect and Trace all lose everything on exit today.
-- This file is their durable form. Load it with sqlite3 AFTER schema.sql --
-- it does not repeat schema.sql's PRAGMA lines, same convention as
-- memory.sql and soul.sql:
--
--   sqlite3 db.sqlite ".read sql/schema.sql" ".read sql/persist.sql"
--
-- Trace's rows go into schema.sql's own `span` table, not a new one -- see
-- lib/persist.ml for the gig_id mismatch that decision runs into.
-- ==========================================================================

-- ------------------------------------------------------------------ SARCASM
-- Semantic-Affectual Re-Construction Augmented System Memory (SARCASM.md).
-- One row per Reconstruct.doc. `links` is deliberately its own table, not a
-- column here -- see sarcasm_link below.

CREATE TABLE sarcasm_doc (
  id     TEXT PRIMARY KEY,   -- Reconstruct.doc.id -- caller-assigned, not ours to invent
  digest TEXT NOT NULL,      -- the contracted form; what is embedded and what recollect/strike search

  -- The original, when contraction kept one. NULL, never ''. `full = None` and
  -- `full = Some ""` are different facts (no original was retained, vs. an
  -- original that was retained and happens to be empty) and reconstruct.ml's
  -- own `expand`/`is_contracted` tell them apart by `<> None`, not by length.
  -- Collapsing the option to a NOT NULL column with '' for "absent" would
  -- silently turn every uncontracted doc into a doc that lied about having
  -- contracted to nothing.
  full   TEXT,

  -- Embed.to_string of doc.vec, and ONLY that encoding. Embed already owns a
  -- round-trip (to_string/of_string, tested in test_terms.ml); a second
  -- serialization here would be a second place for the vector format to
  -- drift out of sync with the code that reads it back.
  vec    TEXT NOT NULL,

  -- The six tones, stored as their own columns rather than one blob, for two
  -- reasons. First, Affect.t has `to_vector` but no inverse -- there is
  -- nothing to call to turn four floats back into a tone. Second, and the
  -- reason this store is relational at all (schema.sql's own opening
  -- comment): a column per tone is a column Aleph, or a plain SQL query, can
  -- filter and aggregate on directly -- "how many high-hazard docs resonate
  -- with X" is a WHERE clause against real columns, not a UDF that unpacks a
  -- blob first.
  --
  -- Five are magnitudes in 0..1; valence is signed in -1..1 (affect.ml's own
  -- words: "FIVE ARE MAGNITUDES. ONE IS SIGNED."). The CHECKs encode that
  -- distinction instead of letting all six drift into whatever a caller
  -- passes.
  affect_surprise   REAL NOT NULL CHECK (affect_surprise   BETWEEN 0.0 AND 1.0),
  affect_hazard     REAL NOT NULL CHECK (affect_hazard     BETWEEN 0.0 AND 1.0),
  affect_novelty    REAL NOT NULL CHECK (affect_novelty    BETWEEN 0.0 AND 1.0),
  affect_cost       REAL NOT NULL CHECK (affect_cost       BETWEEN 0.0 AND 1.0),
  affect_dissonance REAL NOT NULL CHECK (affect_dissonance BETWEEN 0.0 AND 1.0),
  affect_valence    REAL NOT NULL CHECK (affect_valence    BETWEEN -1.0 AND 1.0)
);

-- [[target]] references pulled out of `digest` by Reconstruct.links, kept as
-- their own rows so a query can walk the link graph without re-parsing
-- inline `[[...]]` markup in SQL. This table is a PROJECTION of `digest`, not
-- a second source of truth for it: persist.ml rebuilds a doc's rows from
-- Reconstruct.links every time that doc is saved, so it can never say
-- anything `digest` itself does not already say.
CREATE TABLE sarcasm_link (
  from_id  TEXT    NOT NULL REFERENCES sarcasm_doc(id) ON DELETE CASCADE,

  -- No REFERENCES sarcasm_doc(id) here, and not an oversight: reconstruct.ml
  -- resolves links with `List.filter_map (get s)` (see `candidates`), which
  -- silently drops a link whose target is not in the store instead of
  -- treating it as an error. A dangling link is normal in this model -- a
  -- doc can reference one that has not been added yet, or never will be.
  -- A hard foreign key would refuse to store exactly the links the walker
  -- is already built to tolerate.
  to_id    TEXT    NOT NULL,

  -- Position of this [[link]] in the scan of `digest`, left to right. Kept
  -- because the walk treats order as content (reconstruct.ml: "the ORDER IS
  -- THE CONTENT") and because a digest can name the same target twice --
  -- PRIMARY KEY (from_id, to_id) would silently collapse a repeated
  -- reference into one row.
  position INTEGER NOT NULL,
  PRIMARY KEY (from_id, position)
);

-- The direction a real query asks in: "what points at this memory" needs an
-- index on to_id, since it is not a prefix of the primary key.
CREATE INDEX sarcasm_link_to ON sarcasm_link(to_id);

-- --------------------------------------------------------------- INTROSPECT
-- Read and write solely for the AI (introspect.ml's own words). This table
-- holds entries ONLY. There is no column, view, or trigger here that exposes
-- a verdict, a score, or a write token -- see lib/persist.ml for why a load
-- path that minted one would defeat the module's entire point, and for the
-- honest limit of what loading can and cannot guarantee given introspect.ml
-- ships with no .mli.

CREATE TABLE introspect_entry (
  id    INTEGER PRIMARY KEY,      -- Introspect.entry.id -- the AI's own counter, not sqlite's rowid choice
  text  TEXT    NOT NULL,

  -- Comma-joined. introspect.ml is explicit that tags are "the AI's own
  -- vocabulary. nothing validates these" -- there is no closed set to make a
  -- child table's rows meaningful, and by the same token nothing here can
  -- promise a tag containing a comma survives intact. That is a real limit,
  -- not a rounding error, and it is documented instead of hidden because the
  -- module it serves would not want it hidden either.
  tags  TEXT    NOT NULL DEFAULT '',

  -- Comma-joined entry ids -- "its own structure" per introspect.ml, drawn by
  -- the AI, validated by nothing. Same reasoning as sarcasm_link.to_id: a
  -- link here to an id that no longer exists (forgotten since) is not an
  -- integrity violation to prevent, because Introspect.linked already
  -- handles it by filtering (`List.filter_map (peek_one t)`), not by
  -- refusing to store the link in the first place.
  links TEXT    NOT NULL DEFAULT '',

  at    REAL    NOT NULL          -- entry.at is a float; INTEGER would silently drop the fraction
);
