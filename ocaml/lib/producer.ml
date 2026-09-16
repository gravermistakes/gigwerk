type requirement_outcome =
  | Produced of Production.artifact
  | Production_failed of string

type status =
  | Success
  | Failed of string

type result = {
  outcomes : (string * requirement_outcome) list;
  verification : Verification.t option;
  status : status;
}

let actor_error_string = function
  | Code_actor.Workspace_error s | Code_actor.Actor_error s -> s

let run ~(actor : (module Code_actor.S)) ~specification ~workspace =
  match Workspace.create workspace with
  | Error e ->
      let detail = match e with
        | Workspace.Invalid_root s | Workspace.Invalid_path s | Workspace.Io_error s -> s
      in
      { outcomes = []; verification = None; status = Failed detail }
  | Ok ws ->
      match Production_graph.build specification with
      | Error (Production_graph.Cycle ids) ->
          { outcomes = []; verification = None; status = Failed ("cycle: " ^ String.concat " -> " ids) }
      | Error (Production_graph.Unknown_requirement id) ->
          { outcomes = []; verification = None; status = Failed ("unknown requirement: " ^ id) }
      | Ok graph ->
          let module A = (val actor : Code_actor.S) in
          let rec produce completed outcomes =
            let ready = Production_graph.ready graph ~completed in
            if ready = [] then
              if List.length completed = List.length (Specification.requirements specification) then
                let verification = Verifier.verify ws specification in
                if verification.Verification.passed then
                  { outcomes = List.rev outcomes; verification = Some verification; status = Success }
                else
                  { outcomes = List.rev outcomes; verification = Some verification; status = Failed "verification failed" }
              else
                { outcomes = List.rev outcomes; verification = None; status = Failed "production stalled" }
            else
              match List.find_opt (fun _ -> true) ready with
              | None -> assert false
              | Some requirement ->
                  match A.produce [] requirement ws with
                  | Error e ->
                      { outcomes = List.rev ((requirement.id, Production_failed (actor_error_string e)) :: outcomes);
                        verification = None; status = Failed (actor_error_string e) }
                  | Ok artifact ->
                      produce (requirement.id :: completed)
                        ((requirement.id, Produced artifact) :: outcomes)
          in
          produce [] []
