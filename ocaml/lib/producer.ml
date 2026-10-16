type requirement_outcome =
  | Produced of Production.artifact * string list   (* artifact, phases walked *)
  | Production_failed of string
  | Production_refused of string option             (* the actor's words, if any *)

(* Refused and Over_budget are not kinds of Failed. A refusal is the actor's
   range, and the store keeps it as its own outcome so it never reads as a
   defect; running out of allowance is the booking's sizing, not the work. *)
type status =
  | Success
  | Failed of string
  | Over_budget of string
  | Refused of { requirement : string; words : string option }

type result = {
  outcomes : (string * requirement_outcome) list;
  verification : Verifier.Verification.t option;
  obligations : Obligations.t;
  status : status;
}

(* The commission_outcome.outcome word for a production. *)
let outcome_word r =
  match r.status with
  | Success -> "completed"
  | Failed _ -> "failed"
  | Over_budget _ -> "budget_exceeded"
  | Refused _ -> "refused"

let run ~(actor : (module Code_actor.S)) ~specification ~workspace ~obligations
    ~now =
  let failed ?(outcomes = []) ob detail =
    { outcomes = List.rev outcomes; verification = None; obligations = ob;
      status = Failed detail }
  in
  match Workspace.create workspace with
  | Error e ->
      let detail = match e with
        | Workspace.Invalid_root s | Workspace.Invalid_path s | Workspace.Io_error s -> s
      in
      failed obligations detail
  | Ok ws ->
      match Production_graph.build specification with
      | Error (Production_graph.Cycle ids) ->
          failed obligations ("cycle: " ^ String.concat " -> " ids)
      | Error (Production_graph.Unknown_requirement id) ->
          failed obligations ("unknown requirement: " ^ id)
      | Ok graph ->
          let module A = (val actor : Code_actor.S) in
          let rec produce completed outcomes ob =
            match Production_graph.ready graph ~completed with
            | [] ->
                if List.length completed = List.length (Specification.requirements specification) then
                  let verification = Verifier.verify ws specification in
                  { outcomes = List.rev outcomes; verification = Some verification;
                    obligations = ob;
                    status = if verification.Verifier.passed then Success
                             else Failed "verification failed" }
                else failed ~outcomes ob "production stalled"
            | requirement :: _ ->
                let fail why =
                  failed ~outcomes:((requirement.id, Production_failed why) :: outcomes) ob why
                in
                match A.prepare requirement ws with
                | Error (Code_actor.Workspace_error e) -> fail e
                | Error (Code_actor.Refused words) ->
                    { outcomes = List.rev ((requirement.id, Production_refused words) :: outcomes);
                      verification = None; obligations = ob;
                      status = Refused { requirement = requirement.id; words } }
                | Ok s0 ->
                    let p = Actor.run_machine A.machine ~obligations:ob ~now
                        ~cost:A.cost ~choose:A.choose ~perform:A.perform s0 in
                    let ob = p.Actor.obligations in
                    let fail why =
                      failed ~outcomes:((requirement.id, Production_failed why) :: outcomes) ob why
                    in
                    match p.Actor.halt with
                    | Actor.Arrived { state; _ } ->
                        let artifact = A.deliver state in
                        if artifact.Production.by <> A.name then
                          (* The booked Actor returned work signed by someone
                             else. Handling it would mean presenting another
                             party's output under this Actor's booking, which
                             is the one thing GigWerk does not do on its
                             talent's behalf. *)
                          fail (Printf.sprintf "artifact signed by %S, but %S was booked"
                                  artifact.Production.by A.name)
                        else
                          produce (requirement.id :: completed)
                            ((requirement.id, Produced (artifact, p.Actor.trail)) :: outcomes) ob
                    | Actor.Breached { breach = Obligations.(Exhausted _ | Expired _); _ } as halt ->
                        let why = Actor.halt_to_string halt in
                        { outcomes = List.rev ((requirement.id, Production_failed why) :: outcomes);
                          verification = None; obligations = ob; status = Over_budget why }
                    | halt -> fail (Actor.halt_to_string halt)
          in
          produce [] [] obligations
