(* The synthesis Actor, cast to the BST contract the manus harness validated.
 *
 * Synquid itself is not installed here, so its part is played by a replay of
 * the output it actually produced for this exact contract
 * (synquid-validation/evidence/synquid-BST-Insert.out). The replay is only
 * honest while the contract is byte-identical to the one that output came
 * from, and the first check says so. Everything after the engine, the lowerer,
 * ocamlc and the production's own property test, runs for real. *)
open Gigwerk

let pass = ref 0 and fail = ref 0
let check name b =
  if b then (incr pass; Printf.printf "  ok   %s\n" name)
  else (incr fail; Printf.printf "  FAIL %s\n" name)

let find_repo_file relpath =
  let rec go dir =
    if Sys.file_exists (Filename.concat dir relpath) then Filename.concat dir relpath
    else
      let parent = Filename.dirname dir in
      if parent = dir then failwith ("not found above cwd: " ^ relpath)
      else go parent
  in
  go (Sys.getcwd ())

let slurp path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let spit path s =
  let oc = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc s)

let contract = find_repo_file "synquid-validation/contracts/BST-Insert.sq"
let evidence = find_repo_file "synquid-validation/evidence/synquid-BST-Insert.out"
let test_bst = find_repo_file "synquid-validation/ocaml/test_bst.ml"
let backend = find_repo_file "gigwerk-exercises/backend/synquid_backend.ml"
let backend_main = find_repo_file "gigwerk-exercises/backend/main.ml"

let made = ref []
let () = at_exit (fun () ->
    if !made <> [] then
      ignore (Proc.run ~root:"/" ~timeout_s:30. (Array.of_list ("rm" :: "-rf" :: !made))))

let fresh_dir tag =
  let d = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "gigwerk-synth-%s-%d-%d" tag (Unix.getpid ()) (Random.bits ())) in
  Unix.mkdir d 0o755; made := d :: !made; d

(* The lowerer is built from the merged backend's own source, here, so the
   test does not depend on whether someone ran that project's dune first. *)
let lowerer =
  let d = fresh_dir "lowerer" in
  spit (Filename.concat d "synquid_backend.ml") (slurp backend);
  spit (Filename.concat d "main.ml") (slurp backend_main);
  let o = Proc.run ~root:d ~timeout_s:120.
      [| "ocamlfind"; "ocamlc"; "-package"; "str"; "-linkpkg";
         "synquid_backend.ml"; "main.ml"; "-o"; "synquid-ocaml" |] in
  let o =
    if o.Proc.exit_status = Some 0 then o
    else Proc.run ~root:d ~timeout_s:120.
        [| "ocamlc"; "-I"; "+str"; "str.cma";
           "synquid_backend.ml"; "main.ml"; "-o"; "synquid-ocaml" |]
  in
  if o.Proc.exit_status <> Some 0 then
    failwith ("could not build the lowerer: " ^ o.Proc.stderr);
  Filename.concat d "synquid-ocaml"

let types = "type 'a bst = Empty | Node of 'a * 'a bst * 'a bst\n"

(* Material for requirement `bst`. The property test is the harness's own,
   pointed at this module's name; every other line of it is unchanged. *)
let stage ?(contract_text = slurp contract) ?(signature = "val insert : int -> int bst -> int bst\n") () =
  let root = fresh_dir "ws" in
  let dir = Filename.concat root "bst" in
  Unix.mkdir dir 0o755;
  let put f s = spit (Filename.concat dir f) s in
  put "contract.sq" contract_text;
  put "constructors.tsv" "Empty\t0\tBST\tnamed:Empty\nNode\t3\tBST\tnamed:Node\n";
  put "primitives.txt" "";
  put "types.ml" types;
  put "interface.mli" (types ^ signature);
  let t = slurp test_bst in
  let prefix = "open Generated_bst\n" in
  assert (String.length t > String.length prefix
          && String.sub t 0 (String.length prefix) = prefix);
  put "test.ml" ("open Bst\n" ^ String.sub t (String.length prefix)
                                   (String.length t - String.length prefix));
  root

let engine_calls = ref 0
let replay path = fun _contract -> incr engine_calls; [| "cat"; path |]

let instruments ?(engine = replay evidence) () =
  { Synthesis_actor.engine; lowerer; timeout_s = 60. }

let grants actions = Grants.make ~entity:"synquid" ~snapshot:"t" ~actions
let obligations ?(budget = 20) ?(actions = [ Grants.Read; Grants.Write; Grants.Spawn ]) () =
  Obligations.issue ~id:"ob" ~grants:(grants actions) ~budget ~expires_at:Int64.max_int

let now () = 0L

let spec_of ?(accept = None) () =
  match Specification.parse
          ("req bst : insert into a binary search tree, keeping its elements"
           ^ (match accept with None -> "" | Some a -> "\naccept bst : " ^ a)) with
  | Ok s -> s
  | Error _ -> failwith "spec"

let walk ?(instruments = instruments ()) ?(obligations = obligations ()) root =
  let module A = (val Synthesis_actor.make instruments : Code_actor.S) in
  let r = { Production.id = "bst"; statement = ""; depends_on = []; acceptance = None } in
  match Workspace.create root with
  | Error _ -> failwith "ws"
  | Ok ws ->
      match A.prepare r ws with
      | Error e -> Error e
      | Ok s0 ->
          let p = Actor.run_machine A.machine ~obligations ~now ~cost:A.cost
              ~choose:A.choose ~perform:A.perform s0 in
          (* The actor's state type is its own; only the shape of the halt
             leaves the module. *)
          let open Actor in
          let halt, artifact = match p.halt with
            | Arrived { at; state } -> Arrived { at; state = () }, Some (A.deliver state)
            | Stopped { at; input; why } -> Stopped { at; input; why }, None
            | No_edge { at; input } -> No_edge { at; input }, None
            | Unchosen { at } -> Unchosen { at }, None
            | Breached { at; input; breach } -> Breached { at; input; breach }, None
          in
          Ok ({ halt; trail = p.trail; obligations = p.obligations }, artifact)

let halt_name = function
  | Actor.Arrived _ -> "arrived" | Actor.Stopped _ -> "stopped"
  | Actor.No_edge _ -> "no_edge" | Actor.Unchosen _ -> "unchosen"
  | Actor.Breached _ -> "breached"

let full_ladder =
  [ "commissioned"; "candidate"; "lowered"; "interface_checked"; "compiled"; "tests_passed" ]

let () =
  print_endline "\nthe synthesis actor -- the program comes from the engine, not the booking";
  (* The hash the harness recorded when it ran Synquid, against the contract
     this test stages. *)
  let recorded = List.hd (String.split_on_char ' '
      (slurp (find_repo_file "synquid-validation/evidence/contract.sha256"))) in
  let staged = Filename.concat (stage ()) "bst/contract.sq" in
  let o = Proc.run ~root:"/" ~timeout_s:10. [| "sha256sum"; staged |] in
  check "the staged contract hashes to what the harness recorded when Synquid ran on it"
    (o.Proc.exit_status = Some 0
     && List.hd (String.split_on_char ' ' o.Proc.stdout) = recorded);

  (* ---------------------------------------------------- the performance --- *)
  let root = stage () in
  (match walk root with
   | Ok (p, Some artifact) ->
       check "walks the whole declared ladder, in order" (p.Actor.trail = full_ladder);
       check "arrives at tests_passed, read off the machine" (halt_name p.Actor.halt = "arrived");
       check "the artifact is signed by the actor that performed" (artifact.Production.by = "synquid");
       let produced = slurp (Filename.concat root "bst/bst.ml") in
       check "the module is the types the material declared, then what the lowerer emitted"
         (String.length produced > String.length types
          && String.sub produced 0 (String.length types) = types);
       check "the lowered body defines insert, recursively, as Synquid derived it"
         (let has sub = let n = String.length sub and m = String.length produced in
            let rec go i = i + n <= m && (String.sub produced i n = sub || go (i + 1)) in go 0 in
          has "insert" && has "Node");
       check "the candidate the engine returned is kept beside it, as the record of who wrote what"
         (slurp (Filename.concat root "bst/candidate.out") = slurp evidence);
       check "every move was charged: 3+3+3+1+1 units"
         (Obligations.consumed p.Actor.obligations = 11)
   | Ok (p, None) -> check ("performance: " ^ Actor.halt_to_string p.Actor.halt) false
   | Error _ -> check "prepare refused the BST material" false);

  (* ----------------------------------------------- the negative control --- *)
  (* The same candidate with one recursive call dropped: x9 instead of
     (insert x x9). It still lowers, still matches the interface, still
     compiles. Only the property test can see it lose an element, so if this
     arrives, the test step was not testing. *)
  let mutant = Filename.concat (fresh_dir "mutant") "mutant.out" in
  let e = slurp evidence in
  let needle = "Node x7 x8 (insert x x9)" in
  let i = let n = String.length needle in
    let rec go i = if String.sub e i n = needle then i else go (i + 1) in go 0 in
  spit mutant (String.sub e 0 i ^ "Node x7 x8 x9"
               ^ String.sub e (i + String.length needle) (String.length e - i - String.length needle));
  (match walk ~instruments:(instruments ~engine:(replay mutant) ()) (stage ()) with
   | Ok ({ Actor.halt = Actor.Stopped { at = "compiled"; input = "test"; _ }; trail; _ }, None) ->
       check "a candidate that loses an element is stopped at the test, after compiling cleanly"
         (trail = [ "commissioned"; "candidate"; "lowered"; "interface_checked"; "compiled" ])
   | Ok (p, _) -> check ("mutant: " ^ Actor.halt_to_string p.Actor.halt) false
   | Error _ -> check "mutant: prepare refused" false);

  (* ------------------------------------------ the interface is enforced --- *)
  (match walk (stage ~signature:"val insert : bool -> int bst -> int bst\n" ()) with
   | Ok ({ Actor.halt = Actor.Stopped { at = "lowered"; input = "interface"; why }; _ }, None) ->
       check "a required interface the result does not satisfy stops it at the interface"
         (let n = String.length "not included" in
          let rec go i = i + n <= String.length why
                         && (String.sub why i n = "not included" || go (i + 1)) in go 0)
   | Ok (p, _) -> check ("interface: " ^ Actor.halt_to_string p.Actor.halt) false
   | Error _ -> check "interface: prepare refused" false);

  (* ---------------------------------------------- material, not a script --- *)
  engine_calls := 0;
  let supplied =
    "data BST a where\n  Empty :: BST a\n\ninsert :: x: a -> t: BST a -> BST a\ninsert = \\x . \\t . t\n" in
  (match walk (stage ~contract_text:supplied ()) with
   | Error (Code_actor.Refused (Some _)) ->
       check "a contract with the implementation already in it is declined before the first move"
         (!engine_calls = 0)
   | _ -> check "a contract with no hole was performed anyway" false);

  (* ---------------------------------------------------- range, recorded --- *)
  (match walk ~instruments:(instruments ~engine:(fun _ -> [| "false" |]) ()) (stage ()) with
   | Ok ({ Actor.halt = Actor.Stopped { at = "commissioned"; input = "synthesize"; _ };
           trail = [ "commissioned" ]; _ }, None) ->
       check "an engine that cannot derive stops the actor where it stood, nothing lowered" true
   | Ok (p, _) -> check ("engine refusal: " ^ Actor.halt_to_string p.Actor.halt) false
   | Error _ -> check "engine refusal: prepare refused" false);

  (* ---------------------------------------------------------- obligations --- *)
  let root = stage () in
  (match walk ~obligations:(obligations ~budget:3 ()) root with
   | Ok ({ Actor.halt = Actor.Breached { at = "candidate"; input = "lower";
                                         breach = Obligations.Exhausted _ }; _ }, None) ->
       check "a budget of 3 pays for synthesis and is exhausted before lowering"
         (not (Sys.file_exists (Filename.concat root "bst/bst.ml")))
   | Ok (p, _) -> check ("budget: " ^ Actor.halt_to_string p.Actor.halt) false
   | Error _ -> check "budget: prepare refused" false);

  engine_calls := 0;
  (match walk ~obligations:(obligations ~actions:[ Grants.Read; Grants.Write ] ()) (stage ()) with
   | Ok ({ Actor.halt = Actor.Breached { at = "commissioned";
                                         breach = Obligations.Not_granted Grants.Spawn; _ }; _ }, None) ->
       check "without Spawn granted, the engine is never started" (!engine_calls = 0)
   | Ok (p, _) -> check ("grants: " ^ Actor.halt_to_string p.Actor.halt) false
   | Error _ -> check "grants: prepare refused" false);

  (* -------------------------------------------- the booking, end to end --- *)
  let root = stage () in
  let r = Producer.run ~actor:(Synthesis_actor.make (instruments ()))
      ~specification:(spec_of ()) ~workspace:root ~obligations:(obligations ()) ~now in
  check "Producer casts the actor and records what it produced, with the phases it walked"
    (match r.Producer.outcomes with
     | [ ("bst", Producer.Produced (a, trail)) ] ->
         a.Production.by = "synquid" && trail = full_ladder
     | _ -> false);
  check "...and with no acceptance declared, the booking is unverified, not passed"
    (r.Producer.status = Producer.Failed "verification failed"
     && Producer.outcome_word r = "failed");

  (* ------------------------------------------- refusal is its own outcome --- *)
  engine_calls := 0;
  let r = Producer.run ~actor:(Synthesis_actor.make (instruments ()))
      ~specification:(spec_of ()) ~workspace:(stage ~contract_text:supplied ())
      ~obligations:(obligations ()) ~now in
  check "an actor declining the part is recorded as refused, in its own words, not as failed"
    (match r.Producer.outcomes, r.Producer.status with
     | [ ("bst", Producer.Production_refused (Some _)) ],
       Producer.Refused { requirement = "bst"; words = Some _ } ->
         Producer.outcome_word r = "refused" && !engine_calls = 0
     | _ -> false);
  let module Mute = struct
    let name = "mute"
    let machine = Phases.synthesis_machine
    let cost _ = []
    type state = unit
    let prepare _ _ = Error (Code_actor.Refused None)
    let choose () _ = None
    let perform () _ = Ok ()
    let deliver () = { Production.requirement_id = "bst"; paths = []; by = name }
  end in
  let r = Producer.run ~actor:(module Mute : Code_actor.S) ~specification:(spec_of ())
      ~workspace:(stage ()) ~obligations:(obligations ()) ~now in
  check "a refusal with no words is still a refusal, and its reason stays absent"
    (match r.Producer.status with
     | Producer.Refused { requirement = "bst"; words = None } ->
         Producer.outcome_word r = "refused"
     | _ -> false);
  let r = Producer.run ~actor:(Synthesis_actor.make (instruments ()))
      ~specification:(spec_of ()) ~workspace:(stage ())
      ~obligations:(obligations ~budget:3 ()) ~now in
  check "running out of allowance is budget_exceeded, the booking's sizing, not a refusal"
    (match r.Producer.status with
     | Producer.Over_budget _ -> Producer.outcome_word r = "budget_exceeded"
     | _ -> false);

  (* ------------------------------------------------------------ admission --- *)
  check "the synthesis actor is admitted: two stagings, the same trail, the same bytes"
    (match Admission.check ~actor:(Synthesis_actor.make (instruments ()))
             ~specification:(spec_of ()) ~stage:(fun () -> stage ())
             ~obligations:(obligations ()) ~now with
     | Ok { Admission.talent = "synquid"; artifacts } ->
         List.map fst artifacts = [ "bst/bst.ml"; "bst/candidate.out" ]
     | Ok _ -> false
     | Error r -> prerr_endline (Admission.rejection_to_string r); false);

  (* ----------------------------------- cognition decides who, by booking --- *)
  print_endline "\ncasting -- the booking names the part, the roster names the talent";
  let synthesis_role = Role.synthesis in
  check "the synthesis role validates: its terminal is reachable, its machine deterministic"
    (Result.is_ok synthesis_role);
  let envelope actions =
    Obligations.issue ~id:"env" ~grants:(Grants.make ~entity:"e" ~snapshot:"s" ~actions)
      ~budget:5 ~expires_at:1_000_000L in
  let request ?(role = synthesis_role) actions =
    { Booking.entity = "e"; evidence = Conditions.clean; cap_set = [ "fs_write" ];
      policy_set = [ "bookable" ]; state_shape = "material_dir"; widen_epoch = 0;
      envelope = envelope actions; role } in
  let roster = [ ("synthesis", Synthesis_actor.make (instruments ())) ] in
  (match Booking.book ~now:0L (request [ Grants.Read; Grants.Write; Grants.Spawn ]) with
   | Error _ -> check "a clean synthesis request books" false
   | Ok b ->
       check "the booked obligations are the role's: its grants, its allowance of 11"
         (Obligations.budget b.Booking.commission_obligations = 11);
       let root = stage () in
       (match Booking.perform ~roster b ~specification:(spec_of ()) ~workspace:root ~now with
        | Ok r ->
            check "the talent the roster holds for the part performs it, to tests_passed"
              (match r.Producer.outcomes with
               | [ ("bst", Producer.Produced (a, trail)) ] ->
                   a.Production.by = "synquid" && trail = full_ladder
               | _ -> false);
            check "...spending exactly the allowance the role declared"
              (Obligations.consumed r.Producer.obligations = 11)
        | Error m -> check ("perform: " ^ Booking.miscast_to_string m) false);
       check "a role with no talent on the roster is not performed by someone else"
         (match Booking.perform ~roster:[] b ~specification:(spec_of ())
                  ~workspace:(stage ()) ~now with
          | Error (Booking.No_talent "synthesis") -> true | _ -> false);
       let module Impostor = struct
         let name = "impostor"
         let machine = { Phases.synthesis_machine with Phases.initial = "candidate";
                         states = List.tl Phases.synthesis_machine.Phases.states }
         let cost _ = []
         type state = unit
         let prepare _ _ = Ok ()
         let choose () _ = None
         let perform () _ = Ok ()
         let deliver () = { Production.requirement_id = "bst"; paths = []; by = name }
       end in
       check "talent working a different ladder is miscast, not adapted"
         (match Booking.perform ~roster:[ ("synthesis", (module Impostor : Code_actor.S)) ] b
                  ~specification:(spec_of ()) ~workspace:(stage ()) ~now with
          | Error (Booking.Wrong_part { talent = "impostor"; _ }) -> true | _ -> false));
  check "an envelope without Spawn cannot book the part at all"
    (match Booking.book ~now:0L (request [ Grants.Read; Grants.Write ]) with
     | Error (Booking.Kit_exceeds_envelope [ Grants.Spawn ]) -> true | _ -> false);

  (* ------------------------------------------ work signed by someone else --- *)
  let module Ghost = struct
    let name = "synquid"
    let machine = { Phases.states = [ Phases.phase "commissioned";
                                      Phases.phase ~terminal:true "delivered" ];
                    initial = "commissioned";
                    delta = [ { Phases.from_ = "commissioned"; input = "go"; to_ = "delivered" } ] }
    let cost _ = []
    type state = unit
    let prepare _ _ = Ok ()
    let choose () _ = Some "go"
    let perform () _ = Ok ()
    let deliver () = { Production.requirement_id = "bst"; paths = []; by = "someone-else" }
  end in
  let r = Producer.run ~actor:(module Ghost : Code_actor.S) ~specification:(spec_of ())
      ~workspace:(stage ()) ~obligations:(obligations ()) ~now in
  check "an artifact signed by anyone but the booked actor is refused, not filed"
    (match r.Producer.outcomes, r.Producer.status with
     | [ ("bst", Producer.Production_failed why) ], Producer.Failed _ ->
         why = "artifact signed by \"someone-else\", but \"synquid\" was booked"
     | _ -> false);

  Printf.printf "synthesis actor: %d passed, %d failed\n" !pass !fail;
  if !fail <> 0 then exit 1
