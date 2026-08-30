-- Export the store as Prolog facts.
--
--   sqlite3 gigwerk.db ".read sql/export_facts.sql" > facts.pl
--   swipl -g "consult('facts.pl'), consult('prolog/confidence.pl')" ...
--
-- One door into the store, used by both readers: the booking path asks
-- confidence.pl for a band, and Aleph asks the same facts for rules. Neither
-- speaks SQL, so neither can drift from the other's view of the truth.

.mode list
.headers off
.separator ""

-- review(FormSig, PredictionHeld, CriticPassed, JudgeRefuted, At).
SELECT 'review(''' || form_sig || ''', ' || prediction_held || ', '
       || critic_passed || ', ' || judge_refuted || ', ' || at || ').'
FROM form_review;

-- form(Sig, CapSet, PolicySet, StateShape, WidenEpoch).
-- Identity ignores budget numbers and narrowed scopes. A widened scope bumps
-- widen_epoch, which makes it a different form and sends it back to cold start.
SELECT 'form(''' || sig || ''', ''' || cap_set || ''', ''' || policy_set
       || ''', ''' || state_shape || ''', ' || widen_epoch || ').'
FROM form;

-- gig_result(GigId, Entity, Tier, Shape, NCaps, NEffectful, Outcome, Good).
-- Flat and ILP-shaped, so Aleph can search over SHAPE rather than only result.
SELECT 'gig_result(' || gig_id || ', ''' || entity || ''', ' || tier || ', '''
       || shape || ''', ' || n_caps || ', ' || n_effectful || ', '
       || COALESCE(outcome, 'pending') || ', '
       || COALESCE(CAST(good AS TEXT), 'unknown') || ').'
FROM v_aleph_facts;

-- crash_fact(EntityId, FaultClass, RetryIndex, Chosen, Recovered).
-- The disposition query cannot fire without these. Restart policy is a
-- derivation, not a per-component field -- and a derivation needs inputs.
SELECT 'crash_fact(' || entity_id || ', ' || fault_class || ', '
       || retry_index || ', ' || COALESCE(chosen, 'none') || ', '
       || COALESCE(CAST(recovered AS TEXT), 'unknown') || ').'
FROM crash;
