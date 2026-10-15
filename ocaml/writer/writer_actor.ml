(* The OCaml writer as GigWerk talent.
 *
 * Booked for an Exercism-shaped part whose material sits in the workspace
 * under the requirement's id: the interface (<module>.mli), the part's own
 * test file and its dune files. The ladder is the writer's own
 * (Phases.writer_machine): read the tests into examples, derive each value,
 * write the module, run the part's own check.
 *
 * Material holding a reference solution (.meta) is declined before the first
 * move: writing beside the answer would be filing someone else's work under
 * this actor's name. The Agency's verifier, which does read references, is not
 * part of this actor and never runs inside it. *)

open Gigwerk

type instruments = { env : string array; scratch : string }

module Make (I : sig val instruments : instruments end) : Code_actor.S = struct
  let name = "writer"
  let machine = Phases.writer_machine

  let cost = function
    | "read" -> [ Grants.Read; Grants.Spawn ]
    | "derive" -> [ Grants.Read ]
    | "lower" -> [ Grants.Write ]
    | "check" -> [ Grants.Spawn ]
    | _ -> []

  type state = {
    ws : Workspace.t;
    id : string;
    dir : string;
    m : string;
    mutable examples : (string * Spec.example) list;
    mutable written : Part.written option;
  }

  let prepare (r : Production.requirement) ws =
    let id = r.Production.id in
    let dir = Filename.concat ws.Workspace.root id in
    let m = Probe.module_name id in
    if Sys.file_exists (Filename.concat dir ".meta") then
      Error (Code_actor.Refused (Some "the material holds a reference solution; writing beside it would be filing someone else's answer"))
    else if not (Sys.file_exists (Filename.concat dir (m ^ ".mli")) && Sys.file_exists (Filename.concat dir "test.ml")) then
      Error (Code_actor.Workspace_error ("material missing: " ^ m ^ ".mli and test.ml"))
    else Ok { ws; id; dir; m; examples = []; written = None }

  let choose _ = function
    | "commissioned" -> Some "read"
    | "specified" -> Some "derive"
    | "derived" -> Some "lower"
    | "lowered" -> Some "check"
    | _ -> None

  let perform s = function
    | "read" ->
        let probe = Probe.run ~env:I.instruments.env ~scratch:I.instruments.scratch ~exercise_dir:s.dir ~slug:s.id in
        if probe.Probe.examples = [] then Error "no example could be read from the part's tests"
        else (s.examples <- probe.Probe.examples; Ok s)
    | "derive" ->
        let mli_src = Iface.read_file (Filename.concat s.dir (s.m ^ ".mli")) in
        let w = Part.derive_all ~slug:s.id ~mli_src s.examples in
        (match w.Part.w_source with
         | Some _ -> s.written <- Some w; Ok s
         | None ->
             Error (String.concat "; " (List.filter_map (function
                 | Part.Declined { name; why } -> Some (name ^ ": " ^ why) | _ -> None) w.Part.w_derivations)))
    | "lower" ->
        (match s.written with
         | Some { Part.w_source = Some src; _ } ->
             Workspace.write s.ws ~path:(Filename.concat s.id (s.m ^ ".ml")) ~contents:src
             |> Result.map (fun () -> s)
             |> Result.map_error (function
                 | Workspace.Invalid_root e | Workspace.Invalid_path e | Workspace.Io_error e -> e)
         | _ -> Error "nothing derived to write")
    | "check" ->
        (match s.written with
         | Some w ->
             (match Part.own_check ~env:I.instruments.env ~scratch:I.instruments.scratch ~exercise_dir:s.dir w with
              | `Passed -> Ok s
              | `Failed log -> Error ("the part's own check failed: " ^ String.sub log 0 (min 400 (String.length log)))
              | `Not_run why -> Error why)
         | None -> Error "nothing derived to check")
    | other -> Error ("no such move: " ^ other)

  let deliver s =
    { Production.requirement_id = s.id; paths = [ Filename.concat s.id (s.m ^ ".ml") ]; by = name }
end

let make instruments : (module Code_actor.S) =
  (module Make (struct let instruments = instruments end))
