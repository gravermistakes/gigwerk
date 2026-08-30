(* Kits — what an actor is assembled FROM.
 *
 * The AI reads the fact store, retrieves to work out what is needed, and then
 * assembles from kits. A kit is not a preset: a preset is a finished actor you
 * copy, a kit is a set of parts that go together and a statement of what they
 * cannot do.
 *
 * Every kit declares its grants, and no kit may declare a composer-only grant.
 * That is checked here rather than left to whoever writes the kit -- a kit is
 * the thing that gets reused, so a mistake in one propagates into every actor
 * built from it. *)

type t = {
  name        : string;
  purpose     : string;
  grants      : Grants.action list;
  state_shape : string;
  ladder      : Phases.ladder;      (* the tool declares its own phases *)
  budget_ms   : int;
  (* How many Terms-countable actions this behavior takes to reach its terminal
     phase. Declared by the TOOL, for the same reason the ladder is: the kit is
     the thing that knows its own shape. A composer that got to name this could
     name a number large enough that the per-gig bound stops bounding anything,
     and then `budget` is a figure in a record nobody reads. *)
  budget_actions : int;
}

type rejection =
  | Composer_only of Grants.action
  | No_terminal_phase
  | Empty_purpose
  | Cannot_act of { grants : int; budget_actions : int }

let rejection_to_string = function
  | Composer_only a ->
      Printf.sprintf "kit declares composer-only grant %s"
        (Grants.action_to_string a)
  | No_terminal_phase -> "kit's ladder has no terminal phase, so it can never finish"
  | Empty_purpose -> "kit has no stated purpose"
  | Cannot_act { grants; budget_actions } ->
      Printf.sprintf
        "kit claims %d grants but is allotted %d actions, so it can never use them"
        grants budget_actions

(* A kit that cannot finish is worse than one that fails: it consumes budget
   until Terms cuts it off, and the outcome reads as budget_exceeded rather
   than as the design error it is. *)
let validate k =
  match List.find_opt Grants.composer_only k.grants with
  | Some a -> Error (Composer_only a)
  | None ->
      if not (List.exists (fun (p : Phases.phase) -> p.Phases.terminal) k.ladder)
      then Error No_terminal_phase
      else if String.trim k.purpose = "" then Error Empty_purpose
      (* Same failure class as No_terminal_phase, one layer down: a kit that may
         act but has no allowance to act runs until Terms cuts it off, and the
         ledger reads budget_exceeded rather than the design error it is. A kit
         with no grants at all legitimately needs no allowance -- echo. *)
      else if k.grants <> [] && k.budget_actions < 1 then
        Error (Cannot_act { grants = List.length k.grants;
                            budget_actions = k.budget_actions })
      else Ok k

let make ~name ~purpose ~grants ~state_shape ~ladder ~budget_ms ~budget_actions =
  validate { name; purpose; grants; state_shape; ladder; budget_ms; budget_actions }

(* --------------------------------------------------------------- stock ---- *)

let critic = make ~name:"critic"
  ~purpose:"read an artifact and emit a deterministic verdict"
  ~grants:[ Grants.Read; Grants.Query ]
  ~state_shape:"verdict_log" ~ladder:Phases.critic_ladder ~budget_ms:5000
  (* read the artifact, query the ledger for the db name it reports. two. *)
  ~budget_actions:2

let echo = make ~name:"echo"
  ~purpose:"prove delivery, step and outcome with no capability at all"
  ~grants:[] ~state_shape:"last_message"
  ~ladder:Phases.echo_ladder ~budget_ms:250 ~budget_actions:0

(* Deliberately invalid, kept as a fixture: the mistake a kit author makes is
   granting the actor the retrieval the composer used to design it. *)
let bad_researcher = make ~name:"researcher"
  ~purpose:"look things up and summarise"
  ~grants:[ Grants.Read; Grants.Retrieve ]
  ~state_shape:"notes" ~ladder:Phases.critic_ladder ~budget_ms:60000
  ~budget_actions:20

(* Grants Write, whose capability is requires_booking=1 in the seed. Exists to
   exercise the QUEUE path: Conditions returns Queue before terms are issued, so
   this kit's own numbers never get consulted. There is deliberately no behavior
   wired for it -- a queued composition that also had a runner would let a
   mistake in the gate turn straight into a side effect. *)
let scribe = make ~name:"scribe"
  ~purpose:"write an artifact beneath the capability root"
  ~grants:[ Grants.Write ]
  ~state_shape:"notes" ~ladder:Phases.scribe_ladder
  ~budget_ms:10000 ~budget_actions:3
