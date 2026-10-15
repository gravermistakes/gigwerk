(* The synthesis Actor: Synquid derives the program, nobody hands it one.
 *
 * Booked for a requirement whose material sits in the workspace under the
 * requirement's id. The layout mirrors the exercise harness's test_cli.sh:
 *
 *   <id>/contract.sq        the refinement-typed contract, target left as ??
 *   <id>/constructors.tsv   lowering manifest: source arity family repr
 *   <id>/primitives.txt     lowering manifest: trusted primitives
 *   <id>/types.ml           OCaml declarations the contract's datatypes lower to
 *   <id>/interface.mli      the interface the result must satisfy
 *   <id>/test.ml            the production's own check
 *
 * All of that is material: what LaBute wrote. None of it is the program. The
 * program is `<id>/<id>.ml`, and the only things that write it are the engine
 * and the lowerer, run by this actor with no shell.
 *
 * A contract with no hole is refused before the first move. Material that
 * already contains the implementation is a line reading, and an actor cast to
 * read one would be filing someone else's output under its own name. *)

type instruments = {
  engine : string -> string array;   (* contract file -> argv *)
  lowerer : string;                  (* synquid-ocaml CLI *)
  timeout_s : float;
}

(* Synquid as the manus harness invoked it. *)
let synquid_engine contract =
  [| "synquid"; contract; "--output=Plain"; "--print-stats" |]

let has_hole s =
  let n = String.length s in
  let rec go i = i + 1 < n && ((s.[i] = '?' && s.[i + 1] = '?') || go (i + 1)) in
  go 0

let valid_module_name id =
  id <> ""
  && (match id.[0] with 'a' .. 'z' -> true | _ -> false)
  && String.for_all
       (function 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true | _ -> false)
       id

let material = [ "contract.sq"; "constructors.tsv"; "primitives.txt";
                 "types.ml"; "interface.mli"; "test.ml" ]

module Make (I : sig val instruments : instruments end) : Code_actor.S = struct
  let name = "synquid"
  let machine = Phases.synthesis_machine

  (* Each move pays for what it touches: the three that read material, run a
     tool and write a file pay three units; compile and test only run. *)
  let cost = function
    | "synthesize" | "lower" | "interface" -> [ Grants.Read; Grants.Spawn; Grants.Write ]
    | "compile" | "test" -> [ Grants.Spawn ]
    | _ -> []

  type state = { ws : Workspace.t; id : string; dir : string }

  let prepare (r : Production.requirement) ws =
    let id = r.Production.id in
    if not (valid_module_name id) then
      Error (Code_actor.Actor_error
               (Printf.sprintf "%S cannot name an OCaml module" id))
    else
      let missing =
        List.filter (fun f -> Result.is_error (Workspace.read ws ~path:(Filename.concat id f)))
          material
      in
      if missing <> [] then
        Error (Code_actor.Workspace_error
                 ("material missing: " ^ String.concat ", " missing))
      else
        match Workspace.read ws ~path:(Filename.concat id "contract.sq") with
        | Error _ -> Error (Code_actor.Workspace_error "contract.sq unreadable")
        | Ok c when not (has_hole c) ->
            Error (Code_actor.Actor_error
                     "contract leaves no hole: the implementation was supplied, \
                      so there is nothing here to perform")
        | Ok _ ->
            Ok { ws; id; dir = Filename.concat ws.Workspace.root id }

  (* The policy. The actor reads its own phase and picks the move that phase
     is for. It is the whole of "how the gig is done", and it lives here, not
     with whoever booked it. *)
  let choose _ = function
    | "commissioned" -> Some "synthesize"
    | "candidate" -> Some "lower"
    | "lowered" -> Some "interface"
    | "interface_checked" -> Some "compile"
    | "compiled" -> Some "test"
    | _ -> None

  let run s argv =
    let o = Proc.run ~root:s.dir ~timeout_s:I.instruments.timeout_s argv in
    match o.Proc.exit_status with
    | Some 0 -> Ok o.Proc.stdout
    | Some n ->
        Error (Printf.sprintf "%s exited %d: %s" argv.(0) n
                 (String.trim (o.Proc.stderr ^ "\n" ^ o.Proc.stdout)))
    | None -> Error (Printf.sprintf "%s timed out" argv.(0))

  let write s file contents =
    Workspace.write s.ws ~path:(Filename.concat s.id file) ~contents
    |> Result.map_error (function
         | Workspace.Invalid_root e | Workspace.Invalid_path e | Workspace.Io_error e -> e)

  let read s file =
    Workspace.read s.ws ~path:(Filename.concat s.id file)
    |> Result.map_error (function
         | Workspace.Invalid_root e | Workspace.Invalid_path e | Workspace.Io_error e -> e)

  let ( let* ) = Result.bind
  let ml s = s.id ^ ".ml"
  let mli s = s.id ^ ".mli"

  let perform s = function
    | "synthesize" ->
        let* out = run s (I.instruments.engine "contract.sq") in
        let* () = write s "candidate.out" out in
        Ok s
    | "lower" ->
        let* body = run s [| I.instruments.lowerer; "candidate.out";
                             "constructors.tsv"; "primitives.txt" |] in
        let* types = read s "types.ml" in
        let* () = write s (ml s) (types ^ body) in
        Ok s
    | "interface" ->
        let* iface = read s "interface.mli" in
        let* () = write s (mli s) iface in
        let* _ = run s [| "ocamlc"; "-c"; mli s |] in
        let* _ = run s [| "ocamlc"; "-c"; "-w"; "+8+11"; "-warn-error"; "+8+11"; ml s |] in
        Ok s
    | "compile" ->
        let* _ = run s [| "ocamlc"; "-c"; "test.ml" |] in
        let* _ = run s [| "ocamlc"; "-o"; "test.byte"; s.id ^ ".cmo"; "test.cmo" |] in
        Ok s
    | "test" ->
        let* _ = run s [| "./test.byte" |] in
        Ok s
    | other -> Error ("no such move: " ^ other)

  let deliver s =
    { Production.requirement_id = s.id;
      paths = [ Filename.concat s.id (ml s); Filename.concat s.id "candidate.out" ];
      by = name }
end

let make instruments : (module Code_actor.S) =
  (module Make (struct let instruments = instruments end))
