(* The booking path: Conditions -> Terms -> Kit -> Actor booked to match.
 *
 * WHY THIS ORDER, since it is not the order the types suggest.
 *
 * My instinct was Kit -> Terms: the kit knows which actions it needs, so let it
 * hand those to Terms. That is backwards, and the way it is backwards is the
 * same failure this whole design exists to prevent. If the kit supplies the
 * budget, the thing that runs inside the bound is the thing that set the bound.
 * A kit author who wants more room writes a bigger number, and the number stops
 * being a bound and becomes a declaration.
 *
 * So the envelope is authored ABOVE the kit and the kit is then checked to see
 * whether it fits inside. Terms first, kit second, and a kit that needs an
 * action the envelope does not grant is refused rather than accommodated. This
 * is the same discipline Caps applies to space -- the dirfd has no parent --
 * applied to quantity: the allowance has no author downstream of itself.
 *
 * WHAT "BOOKED TO MATCH" MEANS HERE. Two things, and both are checked:
 *
 *   1. The actor's grants are the KIT's, not the envelope's. If the envelope
 *      permits Read and Write and the kit only reads, the booked actor holds
 *      Read. Least authority, computed at booking, not trusted at runtime.
 *   2. The actor's wall clock is min(what the kit asks, what the terms leave).
 *      Whichever is tighter, always, and resolved before the fork so no code
 *      inside the gig participates in the decision.
 *
 * THE FORK PROBLEM, stated rather than papered over.
 *
 * A gig runs in a forked child (actor.ml). Terms are an immutable OCaml value,
 * so `Terms.spend` inside the child mutates a copy that dies with the child --
 * the parent never learns what was consumed. A per-action counter therefore
 * CANNOT be a global bound across gigs, and pretending otherwise would be a
 * budget figure nobody reads.
 *
 * Two Terms values instead, each bounding what it can actually bound:
 *
 *   envelope   held by the parent, debited ONE unit per booking, before the
 *              fork. This is the across-gig bound and it cannot be evaded,
 *              because the child does not hold it.
 *   gig_terms  a narrowed copy handed to the child. Per-gig action allowance.
 *              Dying with the child is correct, not a leak: it was never a
 *              running total.
 *
 * The wall clock (SIGALRM) is the one bound the child cannot lie about at all,
 * which is why it is the backstop rather than the accountant.
 *
 * PHASES CROSS THE FORK, WHICH IS THE POINT. The child reports a phase name on
 * the pipe; the PARENT checks it against the kit's ladder. An undeclared phase
 * is a breach detected by the reader, not a self-report the reader trusts. That
 * is the only reason a completion signal means anything here: the child chooses
 * what to say and the parent chooses what counts. *)

type refusal =
  (* Conditions said so. Refuse is structural, Queue is a human's decision --
     kept apart because collapsing them loses the only bit that says whether
     asking a human would even help. *)
  | Refused of { reasons : string list; attaches : Conditions.attachment }
  | Queued of string list
  (* An envelope carrying Retrieve would hand ranked retrieval to an actor the
     moment it is copied down. Kit.validate already refuses a kit that claims a
     composer-only grant, but nothing checked the ENVELOPE -- and the envelope
     is what gets narrowed into the actor's terms. Same hole, one layer up. *)
  | Envelope_carries_composer_grant of Grants.action
  | Envelope_dead of Terms.breach
  | Kit_rejected of Kit.rejection
  | Kit_exceeds_envelope of Grants.action list
  | No_wall_left of { kit_ms : int; terms_ms : int }

let refusal_to_string = function
  | Refused { reasons; _ } -> "refused: " ^ String.concat ", " reasons
  | Queued rs -> "queued: " ^ String.concat ", " rs
  | Envelope_carries_composer_grant a ->
      Printf.sprintf "envelope grants composer-only action %s"
        (Grants.action_to_string a)
  | Envelope_dead b -> "envelope not live: " ^ Terms.breach_to_string b
  | Kit_rejected r -> "kit rejected: " ^ Kit.rejection_to_string r
  | Kit_exceeds_envelope acts ->
      Printf.sprintf "kit needs actions the envelope does not grant: %s"
        (String.concat ", " (List.map Grants.action_to_string acts))
  | No_wall_left { kit_ms; terms_ms } ->
      Printf.sprintf "no wall clock left: kit asks %dms, envelope leaves %dms"
        kit_ms terms_ms

(* The decision recorded in booking_verdict. `Queued` and `Refused` are as much
   an output of this path as a booking is -- the schema's own comment says the
   refusals are the training signal most systems throw away. *)
let decision_of_refusal = function
  | Queued _ -> "queue"
  | Refused _ | Envelope_carries_composer_grant _ | Envelope_dead _
  | Kit_rejected _ | Kit_exceeds_envelope _ | No_wall_left _ -> "refuse"

(* What the verdict is a fact ABOUT, which is not the same question as what the
 * verdict was. Only a 'composition' refusal enters the dead set.
 *
 * This distinction was missing on the first wiring and the consequence was
 * immediate: `propose critic` with no --grant refused (the kit needs read and
 * query, the envelope granted nothing), that refusal was written against the
 * form, and `propose critic --grant read,query` then refused forever with
 * "composition_previously_refused". The form's identity ignores envelopes on
 * purpose -- a narrowed scope is the same form -- so an envelope-shaped refusal
 * must not be able to reach it. One column, and the whole class of transient
 * refusal stops being fatal.
 *
 * Queued is deliberately 'proposal': a human being asked is not evidence
 * against the shape. *)
let attaches_to = function
  (* Conditions already decided this; do not re-derive it. *)
  | Refused { attaches; _ } -> Conditions.attachment_to_string attaches
  | Kit_rejected _ -> "kit"
  | Queued _ | Envelope_carries_composer_grant _ | Envelope_dead _
  | Kit_exceeds_envelope _ | No_wall_left _ -> "proposal"

(* ------------------------------------------------------------ form identity *)

(* Identity ignores scopes and budget numbers, per the `form` table's comment:
   a NARROWED scope is the same form, a WIDENED one bumps widen_epoch and starts
   cold. Sorted, because identity must not depend on the order claims came back
   from the store -- an ORDER BY somewhere else would otherwise silently reset
   every form's accumulated confidence. *)
(* Length-prefixed, not delimiter-joined. Joining with commas makes the encoding
   non-injective: cap_set ["a,b"] and ["a";"b"] produce the same key, so one
   capability whose name contains the delimiter is indistinguishable from two
   capabilities -- a form collision, which means two different shapes sharing one
   confidence record. Capability names come from a TEXT primary key with no
   character restriction, so this is reachable, and a collision here is silent:
   the sigs simply match and nothing anywhere reports a problem. *)
(* Count-prefixed as well as length-prefixed, because length prefixes alone only
   make each FIELD injective, not the concatenation of fields: cap_set=["a"] with
   policy_set=["b"] and cap_set=["a";"b"] with policy_set=[] both render "1:a1:b".
   The count restores the field boundary. *)
let tagged xs =
  let sorted = List.sort String.compare xs in
  string_of_int (List.length sorted) ^ "/"
  ^ String.concat ""
      (List.map (fun x -> string_of_int (String.length x) ^ ":" ^ x) sorted)

let form_sig ~cap_set ~policy_set ~state_shape ~widen_epoch =
  let key =
    String.concat ""
      [ tagged cap_set; tagged policy_set; tagged [ state_shape ];
        string_of_int widen_epoch ]
  in
  String.sub (Digest.to_hex (Digest.string key)) 0 16

(* ------------------------------------------------------------------ request *)

type request = {
  entity : string;
  evidence : Conditions.evidence;
  cap_set : string list;    (* capability NAMES only -- scope-independent *)
  policy_set : string list;
  state_shape : string;
  widen_epoch : int;
  envelope : Terms.t;
  (* The result Kit.make returns, not a bare Kit.t, so a caller can pass
     `Kit.critic` straight through and an invalid kit refuses with the kit
     layer's own reason instead of a reason invented here. *)
  kit : (Kit.t, Kit.rejection) result;
}

type booked = {
  entity : string;
  form_sig : string;
  kit : Kit.t;
  envelope : Terms.t;      (* AFTER the per-booking debit *)
  gig_terms : Terms.t;     (* the child's copy: kit grants, envelope expiry *)
  wall_ms : int;
  ladder : Phases.ladder;
}

(* --------------------------------------------------------------- the path *)

let missing_grants ~envelope ~(needs : Grants.action list) =
  let g = Terms.grants envelope in
  List.filter (fun a -> not (Grants.allows g a)) needs

let book ~(now : int64) (r : request) : (booked, refusal) result =
  (* 1. CONDITIONS. Nothing else runs until the composition is allowed to exist.
        Deliberately first even though it is the most expensive check: issuing
        terms for a composition that is about to be refused means a refusal can
        consume budget, and then a malformed proposal costs the same as a real
        one. *)
  match Conditions.evaluate r.evidence with
  | { verdict = Conditions.Refuse; reasons; attaches_to = attaches } ->
      Error (Refused { reasons; attaches })
  | { verdict = Conditions.Queue; reasons; _ } -> Error (Queued reasons)
  | { verdict = Conditions.Book; _ } -> (
      (* 2. TERMS. The envelope is checked as an envelope -- is it live, and is
            it safe to narrow from -- before anything is allowed to fit in it. *)
      let env_actions = Grants.actions (Terms.grants r.envelope) in
      match List.find_opt Grants.composer_only env_actions with
      | Some a -> Error (Envelope_carries_composer_grant a)
      | None -> (
          match Terms.tick r.envelope ~now with
          | Error b -> Error (Envelope_dead b)
          | Ok envelope -> (
              (* 3. KIT. Validated, then FITTED. Re-validated even when the
                    caller passes an Ok: Kit.t has no signature hiding its
                    fields, so an Ok can carry a record that never went through
                    Kit.make. Trusting the constructor that was not necessarily
                    used is how a composer-only grant gets in. *)
              match r.kit with
              | Error rej -> Error (Kit_rejected rej)
              | Ok k -> (
                  match Kit.validate k with
                  | Error rej -> Error (Kit_rejected rej)
                  | Ok k -> (
                      match missing_grants ~envelope ~needs:k.Kit.grants with
                      | _ :: _ as excess -> Error (Kit_exceeds_envelope excess)
                      | [] ->
                          (* 4. BOOKED TO MATCH. Both bounds resolved here, in
                                the parent, before any child exists. *)
                          let terms_ms =
                            let secs =
                              Int64.sub (Terms.expires_at envelope) now
                            in
                            if Int64.compare secs 0L <= 0 then 0
                            else if Int64.compare secs 86400L > 0 then
                              86_400_000 (* a day is already past any kit ask *)
                            else Int64.to_int (Int64.mul secs 1000L)
                          in
                          let wall_ms = min k.Kit.budget_ms terms_ms in
                          if wall_ms < 1 then
                            Error
                              (No_wall_left
                                 { kit_ms = k.Kit.budget_ms; terms_ms })
                          else
                            let sig_ =
                              form_sig ~cap_set:r.cap_set
                                ~policy_set:r.policy_set
                                ~state_shape:r.state_shape
                                ~widen_epoch:r.widen_epoch
                            in
                            (* The narrowing. k.grants, never env_actions:
                               the actor gets what the kit needs and not what
                               the envelope happened to permit. *)
                            let gig_terms =
                              Terms.issue
                                ~id:(sig_ ^ "/" ^ r.entity)
                                ~grants:
                                  (Grants.make ~entity:r.entity ~snapshot:sig_
                                     ~actions:k.Kit.grants)
                                (* Exactly what the kit declared. An earlier
                                   `max 1` here was a lie in the direction that
                                   matters: it printed budget=1 for a kit that
                                   declared 0. Kit.validate already refuses a
                                   kit with grants and no allowance, so 0 only
                                   reaches here for a kit with no grants -- and
                                   dead terms are the CORRECT terms for an actor
                                   that has no action it is permitted to take. *)
                                ~budget:k.Kit.budget_actions
                                ~expires_at:(Terms.expires_at envelope)
                            in
                            Ok
                              { entity = r.entity;
                                form_sig = sig_;
                                kit = k;
                                envelope;
                                gig_terms;
                                wall_ms;
                                ladder = k.Kit.ladder })))))

(* --------------------------------------------------- running a booked gig *)

(* Wire format on the pipe: PHASE \x1f PAYLOAD. \x1f because the verdict
   encoding already owns '|' and a payload containing the separator would let a
   behavior forge a phase transition -- the one thing the parent is supposed to
   be the sole judge of. Only the FIRST separator splits, so a payload may
   contain more. *)
let sep = '\x1f'

(* `None` emits a bare payload with no separator at all, so the parent observes
   zero phases rather than observing an empty phase name -- an empty name is not
   in any ladder and would read as a BREACH, which is a much stronger claim
   about the behavior than "it did not finish a step". *)
let emit ~(phase : string option) payload =
  match phase with
  | None -> payload
  | Some p -> p ^ String.make 1 sep ^ payload

let split_emission s =
  match String.index_opt s sep with
  | None -> None
  | Some i ->
      Some
        ( String.sub s 0 i,
          String.sub s (i + 1) (String.length s - i - 1) )

type closed = {
  booked : booked;
  outcome : Actor.outcome;
  progress : Phases.progress;
  breach : Phases.breach option;
  settled : bool;
  payload : string;
}

(* `work` receives the gig's own terms. Behaviors today do not thread them --
   they take capabilities and return a verdict -- so for the stock kits this
   argument is unused and the wall clock is the only live bound inside the
   child. That is a real remaining gap, named here rather than hidden: the
   plumbing exists and the behaviors have not been rewritten to use it. *)
let run (b : booked) ~(work : Terms.t -> string) : closed =
  let outcome = Actor.run_gig ~wall_ms:b.wall_ms ~work:(fun () -> work b.gig_terms) in
  let pr0 = Phases.start b.ladder in
  match outcome with
  | Actor.Completed body -> (
      match split_emission body with
      | None ->
          (* Completed without naming a phase. Not a breach -- a behavior that
             emits nothing is silent, not lying -- but it settles nothing, and
             `matched` reads it as no. *)
          { booked = b; outcome; progress = pr0; breach = None;
            settled = false; payload = body }
      | Some (phase, payload) -> (
          match Phases.observe pr0 phase with
          | Error br ->
              { booked = b; outcome; progress = pr0; breach = Some br;
                settled = false; payload }
          | Ok pr ->
              (* One emission is enough for a deterministic behavior; the
                 default of 2 guards against a flip-flopping bug, and a single
                 fork produces exactly one report. *)
              { booked = b; outcome; progress = pr; breach = None;
                settled = Phases.settled ~consecutive:1 pr; payload }))
  | _ ->
      { booked = b; outcome; progress = pr0; breach = None;
        settled = false; payload = Actor.outcome_detail outcome }

(* `matched` answers "did the actor do its job", never "was the artifact good".
   A critic that correctly reports a bad artifact settled on verdict_emitted and
   is a MATCH; a critic that could not read produced no verdict and is not.
   Phase names mean the step COMPLETED, which is what makes the three cases
   separable at all:
     settled           reached its terminal phase        -> yes
     phases, unsettled did part of the work and stopped  -> partial
     no phase / breach produced nothing, or lied         -> no
   This feeds the confidence rule directly, so getting it wrong corrupts every
   band silently rather than failing loudly. *)
let matched (c : closed) =
  match c.outcome with
  | Actor.Completed _ ->
      (* The breach arm is currently REDUNDANT and stays deliberately: a breach
         means Phases.observe rejected the emission, so progress is empty and the
         emissions arm below already returns "no". It is kept because that is an
         invariant of ANOTHER module -- if phases.ml ever records an emission and
         flags it separately (a reasonable change, it would make breaches
         inspectable), the emissions arm would start awarding partial credit to a
         behavior that named a phase outside its own ladder. The invariant this
         depends on is pinned by a test, so it cannot rot silently. *)
      if c.breach <> None then "no"
      else if c.settled then "yes"
      else if Phases.emissions c.progress > 0 then "partial"
      else "no"
  | _ -> "no"

let outcome_word (c : closed) =
  match c.outcome with
  | Actor.Completed _ -> "completed"
  | Actor.Budget_exceeded _ -> "budget_exceeded"
  | Actor.Failed _ | Actor.Crashed _ -> "failed"

(* ---------------------------------------------------------------- the store *)

let record_refusal ~entity ~sig_ (r : refusal) =
  let reasons = refusal_to_string r in
  Store.exec_checked
    (Printf.sprintf
       "INSERT INTO booking_verdict \
        (entity_id, composition_sig, decision, reasons, decided_at, decided_by, \
         attaches_to) \
        SELECT id, '%s', '%s', '%s', strftime('%%s','now'), 'conditions', '%s' \
        FROM entity WHERE name = '%s';"
       (Store.esc sig_)
       (decision_of_refusal r)
       (Store.esc reasons) (attaches_to r) (Store.esc entity))

let record_booking (b : booked) =
  Store.exec_checked
    (Printf.sprintf
       "INSERT INTO booking_verdict \
        (entity_id, composition_sig, decision, reasons, decided_at, decided_by, \
         attaches_to) \
        SELECT id, '%s', 'book', '%s', strftime('%%s','now'), 'conditions', \
               'composition' \
        FROM entity WHERE name = '%s';"
       (Store.esc b.form_sig)
       (Store.esc
          (Printf.sprintf "kit=%s wall_ms=%d gig_actions=%d grants=[%s]"
             b.kit.Kit.name b.wall_ms (Terms.budget b.gig_terms)
             (String.concat "," (List.map Grants.action_to_string b.kit.Kit.grants))))
       (Store.esc b.entity))

(* A form row must exist before form_review can reference it -- the FK is the
   reason a review insert silently vanished once. Idempotent: the same
   composition books many times and the form is the same form. *)
let ensure_form (b : booked) ~cap_set ~policy_set ~widen_epoch =
  Store.exec_checked
    (Printf.sprintf
       "INSERT OR IGNORE INTO form \
        (sig, cap_set, policy_set, state_shape, widen_epoch, first_seen) \
        VALUES ('%s', '%s', '%s', '%s', %d, strftime('%%s','now'));"
       (Store.esc b.form_sig)
       (Store.esc (String.concat "," (List.sort String.compare cap_set)))
       (Store.esc (String.concat "," (List.sort String.compare policy_set)))
       (Store.esc b.kit.Kit.state_shape) widen_epoch)

(* ------------------------------------------------- evidence from the store *)

(* Conditions.evidence is a record of booleans, and a record of booleans is only
 * worth having if something computes it from facts. Until this existed, every
 * caller had to hand-assemble evidence, which means every caller could hand
 * itself a clean one.
 *
 * Two of the six structural flags are enforced by the schema and two are not,
 * and the difference is not obvious:
 *
 *   capabilities_exist  NOT enforced in practice. c_capability.capability
 *                       REFERENCES capability(name), but sqlite ships with
 *                       PRAGMA foreign_keys = OFF, so unless someone turned it
 *                       on the REFERENCES clause is a comment. Checked here.
 *   single_writer       enforced: component_owner's PRIMARY KEY on `component`
 *                       makes two owners unrepresentable. So the useful check
 *                       is the other direction -- a component with NO owner has
 *                       no system responsible for its writes.
 *
 * The adversarial strengths are not the store's business. They come from a
 * model call the store never sees, so they are arguments. *)

let split_segments s =
  String.split_on_char '/' s |> List.filter (fun seg -> seg <> "")

(* Narrow means "beneath": the envelope's segments must be a PREFIX of the
   claim's. Deeper is narrower. Equal is narrow enough -- claiming exactly the
   envelope is not widening it. An empty scope means "the envelope itself". *)
let rec is_prefix a b =
  match (a, b) with
  | [], _ -> true
  | _, [] -> false
  | x :: xs, y :: ys -> String.equal x y && is_prefix xs ys

let scope_narrows ~envelope ~scope =
  if String.trim scope = "" then true
  else is_prefix (split_segments envelope) (split_segments scope)

let one_int sql = match Store.query sql with
  | [ [ v ] ] -> (try int_of_string (String.trim v) with _ -> 0)
  | _ -> 0

let evidence_of_store ~entity ~sig_ ~tier ~(kit_grants : Grants.action list)
    ~support_strength ~refutation_strength : Conditions.evidence =
  let e = Store.esc entity in
  let claims = Store.claims ~entity in
  let cap_rows =
    Store.query
      "SELECT name, envelope, requires_booking FROM capability"
    |> List.filter_map (function
         | [ n; env; rb ] -> Some (n, (env, String.trim rb = "1"))
         | _ -> None)
  in
  let capabilities_exist =
    List.for_all (fun (n, _) -> List.mem_assoc n cap_rows) claims
  in
  let grants_narrow =
    List.for_all
      (fun (n, scope) ->
        match List.assoc_opt n cap_rows with
        | None -> false (* an unknown capability has no envelope to be inside *)
        | Some (env, _) -> scope_narrows ~envelope:env ~scope)
      claims
  in
  (* The kit says what shape it keeps; c_state says what shape the entity has.
     A composition where those disagree does not resolve, and the disagreement
     is invisible at runtime because each side is individually well-formed. *)
  let shape_wellformed =
    match
      Store.query
        (Printf.sprintf
           "SELECT s.shape FROM c_state s JOIN entity e ON e.id = s.entity_id \
            WHERE e.name = '%s'" e)
    with
    | [ [ shape ] ] -> String.trim shape <> ""
    | _ -> false
  in
  let single_writer =
    (* every component table this entity actually occupies has an owner *)
    0
    = one_int
        (Printf.sprintf
           "SELECT count(*) FROM (\
              SELECT 'c_inbox' AS c FROM c_inbox x JOIN entity e ON e.id = x.entity_id WHERE e.name='%s' \
              UNION SELECT 'c_state' FROM c_state x JOIN entity e ON e.id = x.entity_id WHERE e.name='%s' \
              UNION SELECT 'c_budget' FROM c_budget x JOIN entity e ON e.id = x.entity_id WHERE e.name='%s' \
              UNION SELECT 'c_capability' FROM c_capability x JOIN entity e ON e.id = x.entity_id WHERE e.name='%s' \
              UNION SELECT 'c_policy' FROM c_policy x JOIN entity e ON e.id = x.entity_id WHERE e.name='%s'\
            ) occupied \
            LEFT JOIN component_owner o ON o.component = occupied.c \
            WHERE o.component IS NULL"
           e e e e e)
  in
  let not_refused_before =
    0
    = one_int
        (Printf.sprintf
           "SELECT count(*) FROM booking_verdict \
            WHERE composition_sig = '%s' AND decision = 'refuse' \
              AND attaches_to = 'composition'"
           (Store.esc sig_))
  in
  let no_composer_grants =
    not (List.exists Grants.composer_only kit_grants)
  in
  let provenance = Store.provenance ~entity in
  let tier_matches =
    if provenance = "agent" then tier = "subprocess" else true
  in
  let requires_human =
    List.exists
      (fun (n, _) ->
        match List.assoc_opt n cap_rows with
        | Some (_, rb) -> rb
        | None -> false)
      claims
  in
  let human_verdict =
    0
    < one_int
        (Printf.sprintf
           "SELECT count(*) FROM booking_verdict \
            WHERE composition_sig = '%s' AND decision = 'book' \
              AND decided_by = 'human'"
           (Store.esc sig_))
  in
  { Conditions.capabilities_exist; grants_narrow; shape_wellformed;
    single_writer; not_refused_before; no_composer_grants; tier_matches;
    human_verdict; requires_human; support_strength; refutation_strength }
