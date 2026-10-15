type result = {
  command : string;
  exit_status : int option;
  stdout : string;
  stderr : string;
  passed : bool;
}

type t = { results : result list; passed : bool }

(* Production.acceptance is a closed variant, so argv is built here and never
   parsed from text at this layer. Proc.run hands it to execvp; no shell. *)
let run_acceptance ~root ~timeout_s (accept : Production.acceptance) =
  let command = Production.acceptance_to_string accept in
  let o = Proc.run ~root ~timeout_s (Array.of_list (Production.acceptance_argv accept)) in
  match o.Proc.exit_status with
  | None ->
      { command; exit_status = None; stdout = o.Proc.stdout;
        stderr = o.Proc.stderr ^ "\nverification timeout"; passed = false }
  | Some code ->
      { command; exit_status = Some code; stdout = o.Proc.stdout;
        stderr = o.Proc.stderr; passed = code = 0 }

let verify workspace specification =
  let accepts =
    Specification.requirements specification
    |> List.filter_map (fun r ->
           Option.map (fun a -> (r.Production.id, a)) r.Production.acceptance)
  in
  let results =
    List.map
      (fun (_id, a) ->
        run_acceptance ~root:workspace.Workspace.root ~timeout_s:30. a)
      accepts
  in
  (* An empty list makes List.for_all vacuously true. A specification that
     declares no acceptance has not passed verification, it has not been
     verified, and those must not report the same. *)
  { results;
    passed = accepts <> [] && List.for_all (fun (r : result) -> r.passed) results }

module Verification = struct
  type nonrec t = t
end
