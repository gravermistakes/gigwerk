(* Phases and completion.
 *
 * A completion signal means something only if whatever emits it cannot choose
 * to lie. An actor is deterministic code -- it emits its terminal phase exactly
 * where its source says, and nowhere else. So completion IS a condition, the
 * same kind as expiry, and not a self-report.
 *
 * Which is why the ladder is declared by the TOOL, not by the agent and not
 * per instance. The agent assigns tools; tools define phases. The model
 * chooses which script runs. It cannot choose what "done" means, any more
 * than deciding to backflip produces one.
 *
 * This closes a gap Obligations cannot reach. Obligations bounds FAILURE to finish --
 * budget spent, deadline passed. It has no way to express finished early and
 * correctly, so without this a commission that completes in 3 of 20 actions merely
 * stops being called. *)

type phase = { name : string; terminal : bool }

let phase ?(terminal = false) name = { name; terminal }

type ladder = phase list

(* ------------------------------------------------------------------------
 * THE TRANSITION RELATION.
 *
 * A ladder is a set of states with no edges, so nothing says which phase may
 * follow which, and `Role.validate` can only ask whether a terminal phase was
 * DECLARED, never whether one is REACHABLE. A role declaring a terminal it can
 * never arrive at passes that check and then burns its allowance until
 * Obligations cuts it off, which reads as budget_exceeded rather than the
 * design error it is.
 *
 * The shape is transcribed from the exercise harness's own classify(), which
 * is a linear chain of gates naming where a run fell off.
 * ------------------------------------------------------------------------ *)

type transition = { from_ : string; input : string; to_ : string }
type machine = { states : phase list; initial : string; delta : transition list }

let states_of m = m.states

(* Deterministic: no two transitions share a (from_, input). An actor is a DFA
   or it is an actor with an oracle, and the second breaks every claim resting
   on determinism. *)
let deterministic m =
  let keys = List.map (fun t -> (t.from_, t.input)) m.delta in
  List.length (List.sort_uniq compare keys) = List.length keys

let step m state input =
  List.find_opt (fun t -> t.from_ = state && t.input = input) m.delta
  |> Option.map (fun t -> t.to_)

(* Breadth-first from `initial`. Returns every state actually arrivable, which
   is what turns "a terminal is declared" into "a terminal is reachable". *)
let reachable m =
  let rec go seen = function
    | [] -> List.rev seen
    | s :: rest when List.mem s seen -> go seen rest
    | s :: rest ->
        let next = List.filter_map (fun t -> if t.from_ = s then Some t.to_ else None) m.delta in
        go (s :: seen) (rest @ next)
  in
  go [] [ m.initial ]

let terminal_reachable m =
  List.exists
    (fun name ->
      match List.find_opt (fun p -> p.name = name) m.states with
      | Some p -> p.terminal
      | None -> false)
    (reachable m)

(* A state nothing can arrive at is a role-authoring mistake, not a spare part. *)
let unreachable_states m =
  let live = reachable m in
  List.filter (fun p -> not (List.mem p.name live)) m.states |> List.map (fun p -> p.name)

type breach =
  | Undeclared of string        (* a phase not in this script's ladder *)
  | Regressed of string * string (* terminal reached, then non-terminal emitted *)

let breach_to_string = function
  | Undeclared p -> Printf.sprintf "phase %S is not declared by this script" p
  | Regressed (from_, to_) ->
      Printf.sprintf "emitted %S after terminal %S -- script does not settle" to_ from_

type progress = {
  ladder : ladder;
  seen   : string list;   (* most recent first *)
}

let start ladder = { ladder; seen = [] }

let declared l name = List.find_opt (fun p -> p.name = name) l

(* An undeclared phase is a breach, not an unknown state. A script that can
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
   phase. One is enough for a correct script; the default of 2 is cheap
   insurance against a buggy script that flip-flops, not against a lying one.
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

(* Ladders for the scripts that exist. Terminal phases are the ONLY place a
   completion signal can come from, and they live here beside the code that
   emits them rather than in a composition file the agent could edit. *)
let echo_ladder    = [ phase "received"; phase ~terminal:true "echoed" ]
let critic_ladder  = [ phase "read"; phase "checked";
                       phase ~terminal:true "verdict_emitted" ]
let scribe_ladder  = [ phase "planned"; phase "drafted";
                       phase ~terminal:true "written" ]

(* ---------------------------------------------------------- synthesis ----
 *
 * Transcribed from the exercise harness's status.classify. Its chain is
 *
 *   candidate -> lowered -> interface -> compiled -> tests -> fulfilled
 *
 * and the LAST link is not the actor's. classify withholds `fulfilled` from a
 * run whose tests passed when the contract was partial or unresolved, naming
 * it `tests_passed_partial_contract` instead. That is a judgement about the
 * MATERIAL, not the performance.
 *
 * So the actor's terminal is `tests_passed`. Reaching it is the whole of the
 * actor's job, done. Whether it becomes fulfillment depends on the quality of
 * the contract it was cast to, which belongs to whoever wrote the contract,
 * and an actor cannot emit a verdict on its own script. Cage does not decide
 * whether The Wicker Man was any good; he decides nothing but the performance,
 * and the performance was complete.
 *
 * That verdict lives where the agency's verdicts live: booking_verdict and
 * commission_outcome, reading this terminal phase alongside the contract's
 * own status. It is deliberately NOT a phase. *)
let synthesis_machine =
  { states =
      [ phase "commissioned"; phase "candidate"; phase "lowered";
        phase "interface_checked"; phase "compiled";
        phase ~terminal:true "tests_passed" ];
    initial = "commissioned";
    delta =
      [ { from_ = "commissioned";      input = "synthesize"; to_ = "candidate" };
        { from_ = "candidate";         input = "lower";      to_ = "lowered" };
        { from_ = "lowered";           input = "interface";  to_ = "interface_checked" };
        { from_ = "interface_checked"; input = "compile";    to_ = "compiled" };
        { from_ = "compiled";          input = "test";       to_ = "tests_passed" } ] }

let synthesis_ladder = synthesis_machine.states

(* The OCaml writer's ladder, declared by the writer as Synquid's is by its
   harness: read the part's own tests into examples, derive each value, write
   the module, run the part's own check. *)
let writer_machine =
  { states =
      [ phase "commissioned"; phase "specified"; phase "derived"; phase "lowered";
        phase ~terminal:true "checked" ];
    initial = "commissioned";
    delta =
      [ { from_ = "commissioned"; input = "read";   to_ = "specified" };
        { from_ = "specified";    input = "derive"; to_ = "derived" };
        { from_ = "derived";      input = "lower";  to_ = "lowered" };
        { from_ = "lowered";      input = "check";  to_ = "checked" } ] }
