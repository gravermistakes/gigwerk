(* Phases and completion.
 *
 * A completion signal means something only if whatever emits it cannot choose
 * to lie. An actor is deterministic code -- it emits its terminal phase exactly
 * where its source says, and nowhere else. So completion IS a condition, the
 * same kind as expiry, and not a self-report.
 *
 * Which is why the ladder is declared by the TOOL, not by the composer and not
 * per instance. The composer assigns tools; tools define phases. The model
 * chooses which behavior runs. It cannot choose what "done" means, any more
 * than deciding to backflip produces one.
 *
 * This closes a gap Terms cannot reach. Terms bounds FAILURE to finish --
 * budget spent, deadline passed. It has no way to express finished early and
 * correctly, so without this a gig that completes in 3 of 20 actions merely
 * stops being called. *)

type phase = { name : string; terminal : bool }

let phase ?(terminal = false) name = { name; terminal }

type ladder = phase list

type breach =
  | Undeclared of string        (* a phase not in this behavior's ladder *)
  | Regressed of string * string (* terminal reached, then non-terminal emitted *)

let breach_to_string = function
  | Undeclared p -> Printf.sprintf "phase %S is not declared by this behavior" p
  | Regressed (from_, to_) ->
      Printf.sprintf "emitted %S after terminal %S -- behavior does not settle" to_ from_

type progress = {
  ladder : ladder;
  seen   : string list;   (* most recent first *)
}

let start ladder = { ladder; seen = [] }

let declared l name = List.find_opt (fun p -> p.name = name) l

(* An undeclared phase is a breach, not an unknown state. A behavior that can
   emit an arbitrary string can emit "done" by accident, which is exactly the
   property that made the phrase untrustworthy in the first place. *)
let observe pr name =
  match declared pr.ladder name with
  | None -> Error (Undeclared name)
  | Some p ->
      (match pr.seen with
       | last :: _ ->
           (match declared pr.ladder last with
            | Some prev when prev.terminal && not p.terminal ->
                Error (Regressed (last, name))
            | _ -> Ok { pr with seen = name :: pr.seen })
       | [] -> Ok { pr with seen = name :: pr.seen })

(* Settled when the last `consecutive` emissions are all the SAME terminal
   phase. One is enough for a correct behavior; the default of 2 is cheap
   insurance against a buggy behavior that flip-flops, not against a lying one.
   Consecutive matters: done-work-done is a bug, not a completion. *)
let settled ?(consecutive = 2) pr =
  let rec take n = function
    | _ when n = 0 -> []
    | [] -> []
    | h :: t -> h :: take (n - 1) t
  in
  match take consecutive pr.seen with
  | [] -> false
  | first :: _ as recent ->
      List.length recent = consecutive
      && List.for_all (String.equal first) recent
      && (match declared pr.ladder first with
          | Some p -> p.terminal
          | None -> false)

let current pr = match pr.seen with [] -> None | h :: _ -> Some h
let emissions pr = List.length pr.seen

(* Ladders for the behaviors that exist. Terminal phases are the ONLY place a
   completion signal can come from, and they live here beside the code that
   emits them rather than in a composition file the composer could edit. *)
let echo_ladder    = [ phase "received"; phase ~terminal:true "echoed" ]
let critic_ladder  = [ phase "read"; phase "checked";
                       phase ~terminal:true "verdict_emitted" ]
let scribe_ladder  = [ phase "planned"; phase "drafted";
                       phase ~terminal:true "written" ]
