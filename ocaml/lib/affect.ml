(* Affect — six tones, each with a named runtime signal.
 *
 * A tone with no signal behind it is a vibe. Every dimension here is derived
 * from something the ledger already records, so nothing has to introspect and
 * nothing has to be asked how it feels.
 *
 * FIVE ARE MAGNITUDES. ONE IS SIGNED.
 *
 * That distinction is the whole reason this is not a single "importance"
 * float. A catastrophe and a triumph are both high-magnitude; if you store
 * only magnitude you cannot tell them apart at retrieval, and you end up
 * weighting a disaster and a breakthrough identically because both "mattered".
 * Valence carries direction. The rest carry how much. *)

type t = {
  surprise  : float;   (* 0..1  prediction error: predicted vs observed *)
  hazard    : float;   (* 0..1  side-effecting caps, breaches, crashes *)
  novelty   : float;   (* 0..1  unseen shape -- NOT surprise; nothing was predicted *)
  cost      : float;   (* 0..1  budget and wall time consumed *)
  dissonance: float;   (* 0..1  contradicts a live belief (v_belief_conflict) *)
  valence   : float;   (* -1..1 SIGNED. human approved (+) or refused (-) *)
}

let zero = { surprise = 0.; hazard = 0.; novelty = 0.;
             cost = 0.; dissonance = 0.; valence = 0. }

let clamp lo hi x = if x < lo then lo else if x > hi then hi else x
let unit_ = clamp 0.0 1.0

(* --- each tone from its source, and only from its source ---------------- *)

(* prediction error. the ledger writes the prediction BEFORE the outcome, so
   this is a genuine violation of expectation rather than hindsight. *)
let surprise_of_match = function
  | "yes" -> 0.0 | "partial" -> 0.5 | _ -> 1.0

(* a gig that touched something irreversible, breached its terms, or crashed *)
let hazard_of ~side_effecting ~breached ~crashed =
  unit_ ((if side_effecting then 0.4 else 0.0)
         +. (if breached then 0.3 else 0.0)
         +. (if crashed then 0.5 else 0.0))

(* novelty is NOT surprise. A first-ever run cannot violate an expectation --
   there was none. It is salient for the opposite reason: nothing to compare. *)
let novelty_of ~prior_runs =
  if prior_runs <= 0 then 1.0 else unit_ (1.0 /. sqrt (float_of_int (prior_runs + 1)))

let cost_of ~consumed ~budget ~wall_ms ~wall_budget_ms =
  let f a b = if b <= 0 then 0.0 else float_of_int a /. float_of_int b in
  unit_ (0.5 *. f consumed budget +. 0.5 *. f wall_ms wall_budget_ms)

(* contradicting a live ruling is louder than contradicting a reading *)
let dissonance_of ~conflicts_ruling ~conflicts_record ~conflicts_reading =
  unit_ ((if conflicts_ruling then 1.0 else 0.0)
         +. (if conflicts_record then 0.6 else 0.0)
         +. (if conflicts_reading then 0.2 else 0.0))

(* the only externally grounded tone: a human said yes or no *)
let valence_of = function
  | "book" | "adopted" | "approved" -> 1.0
  | "refuse" | "declined" | "rejected" -> -1.0
  | "queue" -> -0.2                      (* mild: it cost review attention *)
  | _ -> 0.0

(* Magnitude for ranking. Valence contributes its ABSOLUTE value: a strongly
   negative memory is as retrievable as a strongly positive one, which is the
   point of keeping the sign separate rather than folding it in. *)
let magnitude a =
  unit_ ((a.surprise +. a.hazard +. a.novelty +. a.cost
          +. a.dissonance +. abs_float a.valence) /. 6.0)

let to_string a =
  Printf.sprintf "sur=%.2f haz=%.2f nov=%.2f cost=%.2f dis=%.2f val=%+.2f"
    a.surprise a.hazard a.novelty a.cost a.dissonance a.valence

(* Weights are a POLICY, reviewable, not baked into the ranker. A deployment
   that cares about safety weights hazard; one debugging a flaky form weights
   surprise. Neither is the library's call. *)
type weights = {
  w_surprise : float; w_hazard : float; w_novelty : float;
  w_cost : float; w_dissonance : float; w_valence : float;
}

let default_weights = { w_surprise = 0.30; w_hazard = 0.25; w_novelty = 0.15;
                        w_cost = 0.05; w_dissonance = 0.20; w_valence = 0.05 }

let weighted w a =
  unit_ (w.w_surprise *. a.surprise +. w.w_hazard *. a.hazard
         +. w.w_novelty *. a.novelty +. w.w_cost *. a.cost
         +. w.w_dissonance *. a.dissonance
         +. w.w_valence *. abs_float a.valence)

(* ---------------------------------------------------------- resonance ----
 *
 * The six tones ARE a vector, and that changes what affect is for.
 *
 * Treated as a scalar weight, affect can only break ties on relevance. Treated
 * as a vector, it becomes its own retrieval channel: two memories resonate
 * when their affective signatures align, whether or not they are about
 * anything similar.
 *
 * This is the smell case. A smell does not trigger a memory by being
 * semantically about it -- the semantic similarity is near zero. They share a
 * shape of feeling. Without a channel that can match on affect alone, a walk
 * can only ever continue on topic, and a walk that only continues on topic is
 * a search. *)

let to_vector a =
  [| a.surprise; a.hazard; a.novelty; a.cost; a.dissonance; a.valence |]

let norm v = sqrt (Array.fold_left (fun acc x -> acc +. (x *. x)) 0.0 v)

(* Cosine over the tone vector. Valence stays SIGNED here, which matters: two
   memories of opposite valence do not resonate however matched their
   magnitudes are. A triumph does not remind you of a disaster just because
   both were loud. *)
let resonance a b =
  let x = to_vector a and y = to_vector b in
  let na = norm x and nb = norm y in
  if na = 0.0 || nb = 0.0 then 0.0
  else begin
    let s = ref 0.0 in
    Array.iteri (fun i v -> s := !s +. (v *. y.(i))) x;
    !s /. (na *. nb)
  end

(* Flat affect resonates with nothing. Something that provoked no reaction is
   not a cue -- it is furniture. *)
let is_flat a = norm (to_vector a) < 0.15
