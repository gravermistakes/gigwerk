(* Popper, booked to write a part in Prolog.
 *
 * The part is stated as a Popper task (Popper_contract), Popper learns the
 * program, and acceptance is SWI-Prolog running it on the part's examples
 * and on fresh inputs whose answers the Agency's verifier took from the
 * reference solution. The talent never sees the reference. *)

type outcome =
  | Learned of { name : string; program : string; calls : (string * Value.t list * Value.t) list }
  | Declined of { name : string; why : string }

let popper () =
  match Sys.getenv_opt "GW_POPPER" with
  | Some p -> p
  | None -> "popper.py"

let python () =
  match Sys.getenv_opt "GW_POPPER_PYTHON" with
  | Some p -> p
  | None -> "python3"

let book ~scratch ~timeout_s ~name (exs, bk, bias) =
  let dir = Filename.concat scratch ("popper-" ^ name) in
  ignore (Probe.run_cmd ~cwd:"/" [| "rm"; "-rf"; dir |]);
  Unix.mkdir dir 0o755;
  Probe.write (Filename.concat dir "exs.pl") exs;
  Probe.write (Filename.concat dir "bk.pl") bk;
  Probe.write (Filename.concat dir "bias.pl") bias;
  let o = Gigwerk.Proc.run ~root:scratch ~timeout_s:(timeout_s +. 30.)
      [| python (); popper (); dir; "--timeout"; Printf.sprintf "%.0f" timeout_s |] in
  let lines = String.split_on_char '\n' o.Gigwerk.Proc.stdout in
  let rec after_banner = function
    | l :: rest when String.length l >= 10 && String.sub l 0 10 = "**********" && rest <> [] -> Some rest
    | _ :: rest -> after_banner rest
    | [] -> None in
  match after_banner lines with
  | None -> Error (if o.Gigwerk.Proc.exit_status = None then "Popper: no program within the timeout"
                   else "Popper: no solution")
  | Some rest ->
      let clauses = List.filter (fun l ->
          String.length l > 0 && l.[0] <> '*' && not (String.length l >= 9 && String.sub l 0 9 = "Precision"))
          (let rec upto acc = function
              | l :: _ when String.length l >= 10 && String.sub l 0 10 = "**********" -> List.rev acc
              | l :: r -> upto (l :: acc) r
              | [] -> List.rev acc in upto [] rest) in
      if clauses = [] then Error "Popper: an empty program" else Ok (String.concat "\n" clauses)

let learn ~scratch ~timeout_s ~name ~(params : (string * Types.ty) list) ~out_ty exs =
  match Popper_contract.task ~name ~params ~out_ty exs with
  | exception Popper_contract.Unrepresentable what -> Error ("Popper's bias cannot type " ^ what)
  | (pred, is_test, e, bk, bias) ->
      Result.map (fun clauses ->
          Popper_contract.program ~pred ~is_test ~arity:(List.length params) clauses)
        (book ~scratch ~timeout_s ~name (e, bk, bias))

(* Acceptance: the examples, and the reference's answers on fresh inputs. *)
let accept ~program ~calls =
  match Prolog_actor.run_source ~source:program ~calls with
  | Error e -> ("declined", e)
  | Ok v when v.Prolog_actor.passed = v.Prolog_actor.total ->
      ("verified", Printf.sprintf "%d/%d (examples and fresh inputs, against the reference's answers)"
                     v.Prolog_actor.passed v.Prolog_actor.total)
  | Ok v -> ("failed", Printf.sprintf "%d/%d; %s" v.Prolog_actor.passed v.Prolog_actor.total
                         (match v.Prolog_actor.failures with f :: _ -> f | [] -> ""))

let dedupe exs =
  List.fold_left (fun acc (ex : Spec.example) ->
      if List.exists (fun (e : Spec.example) ->
          List.length e.Spec.args = List.length ex.Spec.args && List.for_all2 Value.equal e.Spec.args ex.Spec.args) acc
      then acc else acc @ [ ex ]) [] exs

let solve ~env ~scratch ~exercise_dir ~slug ?(timeout_s = 120.) () =
  let m = Probe.module_name slug in
  let mli_src = Iface.read_file (Filename.concat exercise_dir (m ^ ".mli")) in
  let iface = Iface.parse_string mli_src in
  let probe = Probe.run ~env ~scratch ~exercise_dir ~slug in
  let reference = Iface.read_file (Filename.concat exercise_dir ".meta/example.ml") in
  (* the verifier's fresh inputs and the reference's answers to them *)
  let samples = match Verify.differential ~env ~scratch ~exercise_dir ~slug ~iface
                        ~examples:probe.Probe.examples ~source:reference ~reference () with
    | Ok v -> v.Verify.samples | Error _ -> [] in
  List.map (fun (v : Iface.value_spec) ->
      let name = v.Iface.vname in
      let exs = dedupe (List.filter_map (fun (t, ex) -> if t = name then Some ex else None) probe.Probe.examples) in
      if exs = [] then Declined { name; why = "no example of it could be read from the tests" }
      else
        let args, out = Types.unarrow (Iface.expand iface.Iface.decls v.Iface.vty) in
        let params = List.map (fun (n, _, t) -> (n, t)) (Part.param_names args) in
        match learn ~scratch ~timeout_s ~name ~params ~out_ty:out exs with
        | Error why -> Declined { name; why }
        | Ok program ->
            let calls = List.map (fun (ex : Spec.example) -> (name, ex.Spec.args, ex.Spec.out)) exs
                        @ List.filter (fun (n, _, _) -> n = name) samples in
            Learned { name; program; calls }) iface.Iface.values

let solve_org ~path ?(timeout_s = 120.) ~scratch () =
  let md = Iface.read_file path in
  let slug = Filename.remove_extension (Filename.basename path) in
  let context = Transcript.context_before ~dir:(Filename.dirname path) ~slug in
  let p = Transcript.read ?context ~slug md in
  let reference = Transcript.reference_with_context ~dir:(Filename.dirname path) ~slug md in
  ignore scratch;
  List.map (fun (name, stated, exs) ->
      let exs = dedupe exs in
      let ty = match stated with
        | Some t -> Some t
        | None -> (match Transcript.infer_type p.Transcript.decls exs ~parametric:true with
            | Some t -> Some t | None -> Transcript.infer_type p.Transcript.decls exs ~parametric:false) in
      match ty with
      | None -> Declined { name; why = "its examples do not determine a type" }
      | Some ty ->
          let args, out = Types.unarrow ty in
          let params = List.map (fun (n, _, t) -> (n, t)) (Part.param_names args) in
          (match learn ~scratch ~timeout_s ~name ~params ~out_ty:out exs with
           | Error why -> Declined { name; why }
           | Ok program ->
               let examples = List.map (fun e -> (name, e)) exs in
               let samples = match Ocamlorg.differential p ~examples ~source:reference ~reference ~slug
                                     ~targets:[ (name, ty) ] with
                 | Ok v -> v.Verify.samples | Error _ -> [] in
               let calls = List.map (fun (ex : Spec.example) -> (name, ex.Spec.args, ex.Spec.out)) exs
                           @ List.filter (fun (n, _, _) -> n = name) samples in
               Learned { name; program; calls }))
    (if p.Transcript.targets = [] then [] else p.Transcript.targets)
