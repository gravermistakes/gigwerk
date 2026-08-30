-- Boundary tests for the three-band confidence rule.
-- Pure SQL. No host language.
--
--   sqlite3 :memory: ".read sql/schema.sql" ".read sql/test_confidence.sql"
--
-- Emits one row per case. `result` is PASS or FAIL; a clean run is all PASS.

-- ------------------------------------------------------------- fixtures

CREATE TEMP TABLE spec (
  sig      TEXT PRIMARY KEY,
  good     INTEGER NOT NULL,
  bad      INTEGER NOT NULL,
  bad_old  INTEGER NOT NULL,   -- 1 = failures are the OLD reviews, 0 = recent
  expect   TEXT    NOT NULL,
  why      TEXT    NOT NULL
);

INSERT INTO spec VALUES
  ('15of15',     15,  0, 0, 'A_autopass',     'clean full window'),
  ('14of15',     14,  1, 0, 'B_last_review',  'one recent failure blocks autopass'),
  ('13of15',     13,  2, 0, 'B_last_review',  'the gap your bands left open'),
  ('12of15',     12,  3, 0, 'B_last_review',  'exact 0.80 threshold'),
  ('11of15',     11,  4, 0, 'C_needs_review', 'just under'),
  ('79of100',    79, 21, 1, 'C_needs_review', 'clean recent window does NOT launder a 0.79 lifetime'),
  ('39of50',     39, 11, 1, 'C_needs_review', 'same, smaller n'),
  ('95then5bad', 95,  5, 0, 'C_needs_review', 'good lifetime does NOT survive a broken window'),
  ('3of3',        3,  0, 0, 'C_needs_review', 'cold start: perfect record still reads 0.20'),
  ('judged15',   15,  0, 0, 'A_autopass',     'baseline for the refutation case below');

-- Recursive counter, so the fixture needs no host loop.
WITH RECURSIVE seq(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM seq WHERE i < 200)
INSERT INTO form (sig, cap_set, policy_set, state_shape, widen_epoch, first_seen)
SELECT sig, 'fs_read', 'bookable/2', 'unit', 0, 0 FROM spec;

-- Successes and failures, ordered so `bad_old` controls recency.
WITH RECURSIVE seq(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM seq WHERE i < 200)
INSERT INTO form_review (form_sig, prediction_held, critic_passed, judge_refuted, at)
SELECT s.sig, 'yes', 1, 0,
       CASE WHEN s.bad_old = 1 THEN 1000 + seq.i ELSE seq.i END
FROM spec s JOIN seq ON seq.i <= s.good;

WITH RECURSIVE seq(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM seq WHERE i < 200)
INSERT INTO form_review (form_sig, prediction_held, critic_passed, judge_refuted, at)
SELECT s.sig, 'no', 1, 0,
       CASE WHEN s.bad_old = 1 THEN seq.i ELSE 1000 + seq.i END
FROM spec s JOIN seq ON seq.i <= s.bad;

-- One extra: predictions all held, critic all passed, judge refuted every one.
-- Scores must collapse to zero -- the adversarial model spends confidence
-- without spending the human's time.
UPDATE form_review SET judge_refuted = 1 WHERE form_sig = 'judged15';
UPDATE spec SET expect = 'C_needs_review',
       why = 'judge refuted all 15 despite held predictions'
 WHERE sig = 'judged15';

-- ---------------------------------------------------------------- results

.mode column
.headers on
.width 12 5 9 9 10 16 16 6

SELECT s.sig                AS form,
       c.n_total            AS n,
       c.lifetime           AS lifetime,
       c.window15           AS window15,
       c.certainty          AS certainty,
       c.band               AS actual,
       s.expect             AS expected,
       CASE WHEN c.band = s.expect THEN 'PASS' ELSE 'FAIL' END AS result
FROM spec s
JOIN v_form_confidence c ON c.form_sig = s.sig
ORDER BY c.certainty DESC, s.sig;

SELECT count(*) || ' cases, '
       || sum(CASE WHEN c.band = s.expect THEN 1 ELSE 0 END) || ' passed, '
       || sum(CASE WHEN c.band = s.expect THEN 0 ELSE 1 END) || ' failed'
         AS summary
FROM spec s JOIN v_form_confidence c ON c.form_sig = s.sig;
