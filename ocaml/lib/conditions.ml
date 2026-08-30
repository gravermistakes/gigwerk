(* Conditions — what must hold for a composition to book.
 *
 * Three verdicts, because two throws information away. Refuse is structural:
 * the composition is malformed or unsafe and no human decision changes that.
 * Queue is a decision a human can actually make. Book is clean.
 *
 * Ordering is deliberate. Structural refusals are evaluated before anything
 * else, so a malformed composition never reaches a human queue and never
 * consumes review attention. Review attention is the scarce resource in this
 * whole design -- over ~0.9 approval rate the queue stops being read at all. *)

type verdict = Book | Queue | Refuse

let verdict_to_string = function
  | Book -> "book" | Queue -> "queue" | Refuse -> "refuse"

type evidence = {
  (* structural -- a false here is a refusal, not a question *)
  capabilities_exist  : bool;   (* every claimed grant names a real capability *)
  grants_narrow       : bool;   (* no scope widens its envelope *)
  shape_wellformed    : bool;   (* declared state shape resolves *)
  single_writer       : bool;   (* no component has two writing systems *)
  not_refused_before  : bool;   (* this composition shape is not in the dead set *)
  (* an actor claiming a composer-only grant. structural, not procedural: no
     human decision makes a nondeterministic actor deterministic. *)
  no_composer_grants  : bool;

  (* procedural -- a false here is a question for a human *)
  tier_matches        : bool;   (* agent provenance implies subprocess tier *)
  human_verdict       : bool;   (* present when any grant requires booking *)
  requires_human      : bool;   (* does any grant require booking at all *)

  (* adversarial -- the second model's weight against the proposer's
     support. Ties refuse: refuted-under-uncertainty is the whole point of
     having a judge that is not the composer. *)
  support_strength    : int;
  refutation_strength : int;
}

(* WHAT THE VERDICT IS A FACT ABOUT -- not the same question as what it was.
 *
 * Refuse fires for two kinds of reason and only one of them is about the shape:
 *
 *   Composition  a structural failure. The capability does not exist, the scope
 *                widens, the shape does not resolve, the actor claims a
 *                composer-only grant. Propose the same shape again and it fails
 *                again, because the shape is what is wrong. This is the dead set.
 *   Proposal     the adversarial judge outweighed the proposer THIS TIME. That
 *                is a fact about what a model call said about one attempt, not a
 *                property of the composition -- run it again with a better case
 *                and the answer can legitimately differ.
 *
 * Conditions is the layer that knows which of its own checks are which, so the
 * distinction is made here rather than reconstructed downstream by matching on
 * a reason string. Recovering it by string match was the alternative and it is
 * exactly one typo away from a shape being permanently killed by a single
 * skeptical judge. *)
type attachment = Composition | Proposal

let attachment_to_string = function
  | Composition -> "composition" | Proposal -> "proposal"

type result = {
  verdict : verdict;
  reasons : string list;
  attaches_to : attachment;
}

let structural_failures e =
  List.filter_map Fun.id [
    (if e.capabilities_exist  then None else Some "capability_does_not_exist");
    (if e.grants_narrow       then None else Some "grant_widens_envelope");
    (if e.shape_wellformed    then None else Some "state_shape_unresolved");
    (if e.single_writer       then None else Some "component_has_two_writers");
    (if e.not_refused_before  then None else Some "composition_previously_refused");
    (if e.no_composer_grants  then None else Some "actor_claims_composer_only_grant");
  ]

let procedural_failures e =
  List.filter_map Fun.id [
    (if e.tier_matches then None else Some "agent_provenance_requires_subprocess");
    (if (not e.requires_human) || e.human_verdict then None
     else Some "grant_requires_human_verdict");
  ]

let evaluate e =
  match structural_failures e with
  | _ :: _ as rs ->
      { verdict = Refuse; reasons = rs; attaches_to = Composition }
  | [] ->
      (* Ties refuse. An adversarial judge that loses ties is a rubber stamp
         with extra steps. *)
      if e.refutation_strength >= e.support_strength
         && e.refutation_strength > 0 then
        { verdict = Refuse;
          reasons = [ "refutation_at_least_as_strong_as_support" ];
          attaches_to = Proposal }
      else
        match procedural_failures e with
        (* A human being ASKED is not evidence against the shape. *)
        | _ :: _ as rs ->
            { verdict = Queue; reasons = rs; attaches_to = Proposal }
        | [] -> { verdict = Book; reasons = []; attaches_to = Composition }

(* Everything true, nothing refuted -- the starting point a caller narrows. *)
let clean = {
  capabilities_exist = true; grants_narrow = true; shape_wellformed = true;
  single_writer = true; not_refused_before = true; no_composer_grants = true;
  tier_matches = true; human_verdict = true; requires_human = false;
  support_strength = 1; refutation_strength = 0;
}
