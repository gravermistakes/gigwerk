-- Precedence, immutability, decay, and soul-scoped confidence.
-- Pure SQL. sqlite3 :memory: ".read sql/schema.sql" ".read sql/soul.sql" \
--                            ".read sql/memory.sql" ".read sql/test_memory.sql"

CREATE TEMP TABLE result (name TEXT, got TEXT, want TEXT);
CREATE TEMP TABLE t (dummy INTEGER);

INSERT INTO soul VALUES ('v1','be terse',NULL,1000,'human','initial',NULL);

-- three claims about the same subject/predicate, from three memories
INSERT INTO mem_record (subject,predicate,object,at)
  VALUES ('critic','max_wall_ms','5000',1100);
INSERT INTO mem_ruling (subject,predicate,object,rationale,at)
  VALUES ('critic','tier','in_process','critics are cheap and trusted',1050);
INSERT INTO mem_reading (subject,predicate,object,basis,confidence,at,model,soul_version)
  VALUES ('critic','max_wall_ms','30000','saw one slow run',0.7,1200,'composer','v1'),
         ('critic','tier','subprocess','felt safer',0.9,1200,'composer','v1'),
         ('critic','favourite_colour','blue','no basis at all',0.9,1200,'composer','v1');

INSERT INTO result
SELECT 'reading losing to record', winner, 'record'
  FROM v_belief_conflict WHERE kind='reading_vs_record';
INSERT INTO result
SELECT 'reading losing to ruling', winner, 'ruling'
  FROM v_belief_conflict WHERE kind='reading_vs_ruling';
INSERT INTO result
SELECT 'uncontested reading survives',
       (SELECT basis FROM v_belief WHERE predicate='favourite_colour'), 'reading';
INSERT INTO result
SELECT 'ruling beats record for the same key',
       (SELECT basis FROM v_belief WHERE subject='critic' AND predicate='tier'), 'ruling';
INSERT INTO result
SELECT 'record beats reading for the same key',
       (SELECT basis FROM v_belief WHERE subject='critic' AND predicate='max_wall_ms'), 'record';

-- record vs ruling is an INCIDENT, not a silent resolution
INSERT INTO mem_ruling (subject,predicate,object,rationale,at)
  VALUES ('fileworker','writes_outside_root','never','scoped by construction',1000);
INSERT INTO mem_record (subject,predicate,object,at)
  VALUES ('fileworker','writes_outside_root','observed_once',1300);
INSERT INTO result
SELECT 'world diverging from policy surfaces as INCIDENT', winner, 'INCIDENT'
  FROM v_belief_conflict WHERE kind='record_vs_ruling';

-- Immutability, tested by ATTEMPTING the operation and checking the row is
-- unchanged. The trigger raises; the CLI reports and continues; the row stands.
-- (An earlier version of this file asserted CASE WHEN 1 THEN 'blocked' on both
-- of these, which could not fail and tested nothing.)
UPDATE mem_record SET object = 'tampered' WHERE subject = 'critic';
INSERT INTO result
SELECT 'UPDATE on mem_record is refused by trigger',
       (SELECT object FROM mem_record WHERE subject='critic' AND predicate='max_wall_ms'),
       '5000';
DELETE FROM mem_record WHERE subject = 'critic';
INSERT INTO result
SELECT 'DELETE on mem_record is refused by trigger',
       CAST((SELECT count(*) FROM mem_record WHERE subject='critic') AS TEXT), '1';

-- Same for the soul body.
UPDATE soul SET body = 'be verbose' WHERE version = 'v1';
INSERT INTO result
SELECT 'UPDATE on a soul body is refused',
       (SELECT body FROM soul WHERE version='v1'), 'be terse';

-- superseding retires but does not erase
INSERT INTO mem_ruling (subject,predicate,object,rationale,at,supersedes)
  VALUES ('critic','tier','subprocess','changed my mind',1400,
          (SELECT id FROM mem_ruling WHERE subject='critic' AND predicate='tier'));
INSERT INTO result
SELECT 'superseded ruling is retired, not deleted',
       CAST(count(*) AS TEXT), '2' FROM mem_ruling WHERE subject='critic' AND predicate='tier';
INSERT INTO result
SELECT 'only the live ruling is believed',
       (SELECT object FROM v_belief WHERE subject='critic' AND predicate='tier'), 'subprocess';

-- decay
INSERT INTO mem_reading (subject,predicate,object,basis,confidence,at,model,soul_version,half_life_days)
  VALUES ('stale','claim','x','old inference',0.9,strftime('%s','now')-(90*86400),
          'composer','v1',30.0);
INSERT INTO result
SELECT 'a 3-half-life-old reading decays below 0.15',
       CASE WHEN confidence_now < 0.15 THEN 'decayed' ELSE 'still_loud' END, 'decayed'
  FROM v_reading_now WHERE subject='stale';

-- soul scoping
-- form_review.form_sig has an FK to form(sig). Without this row the inserts
-- below fail silently under the CLI, which is exactly what made the next three
-- assertions vacuous the first time.
INSERT INTO form VALUES ('F','fs_read','bookable/2','unit',0,0);
INSERT INTO form_review (form_sig,prediction_held,critic_passed,judge_refuted,soul_version,at)
  SELECT 'F','yes',1,0,'v1',value FROM (SELECT 1 value UNION SELECT 2 UNION SELECT 3
    UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8
    UNION SELECT 9 UNION SELECT 10 UNION SELECT 11 UNION SELECT 12 UNION SELECT 13
    UNION SELECT 14 UNION SELECT 15);
INSERT INTO result
SELECT 'confidence is full under the soul it was earned',
       CAST(n_under_current_soul AS TEXT), '15' FROM v_form_confidence_scoped WHERE form_sig='F';

INSERT INTO soul VALUES ('v2','be terse and cite sources','v1',1500,'human','tightened',NULL);
INSERT INTO result
SELECT 'adopting v2 retires v1',
       (SELECT version FROM v_soul_current), 'v2';
INSERT INTO result
SELECT 'a prompt edit resets the form to cold start',
       CAST((SELECT count(*) FROM v_form_confidence_scoped WHERE form_sig='F') AS TEXT),
       '0';
INSERT INTO result
SELECT 'the unscoped view still shows the old number -- the trap',
       CAST((SELECT n_total FROM v_form_confidence WHERE form_sig='F') AS TEXT), '15';

.mode column
.headers on
.width 52 12 12 6
SELECT name, got, want,
       CASE WHEN got IS want THEN 'PASS' ELSE 'FAIL' END AS result FROM result;
SELECT count(*) || ' cases, ' || sum(got IS want) || ' passed, '
       || sum(got IS NOT want) || ' failed' AS summary FROM result;
