(* Admission: a talent joins the roster only if two performances of the same
 * material agree. Each actor below is wrong in exactly one way, and must be
 * caught for that way. *)
open Gigwerk

let pass = ref 0 and fail = ref 0
let check name b =
  if b then (incr pass; Printf.printf "  ok   %s\n" name)
  else (incr fail; Printf.printf "  FAIL %s\n" name)

let stage () =
  let d = Filename.temp_file "gigwerk_admission" "" in
  Sys.remove d; Unix.mkdir d 0o755;
  at_exit (fun () -> ignore (Proc.run ~root:"/" ~timeout_s:10. [| "rm"; "-rf"; d |]));
  d

let spec =
  match Specification.parse "req part : a part to perform" with
  | Ok s -> s | Error _ -> failwith "spec"

let obligations =
  Obligations.issue ~id:"admission"
    ~grants:(Grants.make ~entity:"e" ~snapshot:"s" ~actions:[ Grants.Read; Grants.Write ])
    ~budget:10 ~expires_at:1_000_000L

let now () = 0L

(* commissioned -left-> left -done-> delivered, or by way of right. Two routes
   to the same terminal, so a talent's choice of route is visible in its trail. *)
let forked =
  { Phases.states = [ Phases.phase "commissioned"; Phases.phase "left"; Phases.phase "right";
                      Phases.phase ~terminal:true "delivered" ];
    initial = "commissioned";
    delta = [ { Phases.from_ = "commissioned"; input = "left"; to_ = "left" };
              { Phases.from_ = "commissioned"; input = "right"; to_ = "right" };
              { Phases.from_ = "left"; input = "done"; to_ = "delivered" };
              { Phases.from_ = "right"; input = "done"; to_ = "delivered" } ] }

(* A talent parameterized by what it writes, where, and which route it takes.
   [n] counts performances, so a talent can differ from its previous self. *)
module Talent (P : sig
  val name : string
  val route : int -> string
  val files : int -> root:string -> (string * string) list
  val refuse : bool
  val phantom : string list   (* paths delivered but never written *)
end) : Code_actor.S = struct
  let name = P.name
  let machine = forked
  let cost _ = []
  let performances = ref 0
  type state = { ws : Workspace.t; n : int }
  let prepare _ ws =
    if P.refuse then Error (Code_actor.Refused None)
    else (incr performances; Ok { ws; n = !performances })
  let choose s = function
    | "commissioned" -> Some (P.route s.n)
    | "left" | "right" -> Some "done"
    | _ -> None
  let perform s = function
    | "done" ->
        List.fold_left (fun acc (path, contents) ->
            Result.bind acc (fun () ->
              Workspace.write s.ws ~path ~contents
              |> Result.map_error (fun _ -> "write " ^ path)))
          (Ok ()) (P.files s.n ~root:s.ws.Workspace.root)
        |> Result.map (fun () -> s)
    | _ -> Ok s
  let deliver s =
    { Production.requirement_id = "part";
      paths = List.map fst (P.files s.n ~root:s.ws.Workspace.root) @ P.phantom; by = name }
end

let admit (module A : Code_actor.S) =
  Admission.check ~actor:(module A) ~specification:spec ~stage ~obligations ~now

let talent ?(route = fun _ -> "left") ?(refuse = false) ?(phantom = []) name files =
  (module Talent (struct
     let name = name let route = route let files = files let refuse = refuse
     let phantom = phantom
   end) : Code_actor.S)

let () =
  print_endline "admission -- the same material, performed twice, comes out the same";

  (match admit (talent "steady" (fun _ ~root:_ -> [ ("out/a.ml", "let a = 1\n");
                                                    ("out/b.ml", "let b = 2\n") ])) with
   | Ok { Admission.talent = "steady"; artifacts = [ ("out/a.ml", da); ("out/b.ml", db) ] } ->
       check "a talent that delivers the same bytes twice is admitted, under its own name"
         (da = Digest.string "let a = 1\n" && db = Digest.string "let b = 2\n")
   | Ok _ -> check "steady: admitted with the wrong record" false
   | Error r -> check ("steady: " ^ Admission.rejection_to_string r) false);

  check "a talent whose bytes change between performances is rejected at that file"
    (match admit (talent "drifting" (fun n ~root:_ ->
              [ ("out/a.ml", "let a = 1\n"); ("out/b.ml", Printf.sprintf "let b = %d\n" n) ])) with
     | Error (Admission.Diverged { requirement = "part"; path = "out/b.ml" }) -> true
     | _ -> false);

  check "a talent that writes where it was performed into its work is rejected"
    (match admit (talent "stamped" (fun _ ~root -> [ ("out/a.ml", "(* " ^ root ^ " *)\n") ])) with
     | Error (Admission.Diverged { path = "out/a.ml"; _ }) -> true
     | _ -> false);

  check "a talent that delivers a different set of files is rejected before any byte is read"
    (match admit (talent "wandering" (fun n ~root:_ ->
              [ (Printf.sprintf "out/v%d.ml" n, "let a = 1\n") ])) with
     | Error (Admission.Different_paths { first = [ "out/v1.ml" ]; second = [ "out/v2.ml" ]; _ }) -> true
     | _ -> false);

  check "a talent that reaches the same work by a different route is rejected for the route"
    (match admit (talent "restless" ~route:(fun n -> if n = 1 then "left" else "right")
              (fun _ ~root:_ -> [ ("out/a.ml", "let a = 1\n") ])) with
     | Error (Admission.Different_trail { first = [ "commissioned"; "left"; "delivered" ];
                                          second = [ "commissioned"; "right"; "delivered" ]; _ }) -> true
     | _ -> false);

  check "a talent that declines the part is not admitted for it, and no performance is invented"
    (match admit (talent "absent" ~refuse:true (fun _ ~root:_ -> [])) with
     | Error (Admission.Did_not_perform { performance = 1; why }) ->
         why = "part: refused"
     | _ -> false);

  check "a production that never reached the part is not an empty admission"
    (match Admission.check ~actor:(talent "unstaged" (fun _ ~root:_ -> [])) ~specification:spec
             ~stage:(fun () -> "/dev/null/no-such-stage") ~obligations ~now with
     | Error (Admission.Did_not_perform { performance = 1; _ }) -> true
     | _ -> false);

  check "a delivered path that was never written is unreadable, not equal to itself"
    (match admit (talent "phantom" ~phantom:[ "out/ghost.ml" ]
              (fun _ ~root:_ -> [ ("out/a.ml", "let a = 1\n") ])) with
     | Error (Admission.Unreadable { path = "out/ghost.ml"; _ }) -> true
     | _ -> false);

  Printf.printf "admission: %d passed, %d failed\n" !pass !fail;
  if !fail <> 0 then exit 1
