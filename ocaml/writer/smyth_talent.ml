(* Smyth, booked for an Exercism part.
 *
 * The labor is Smyth's: the part is stated as a sketch (Smyth_contract), the
 * adapter in talents/smyth runs Smyth's own synthesizer on it and prints the
 * answer as OCaml, and the module is that answer under the part's interface.
 * Acceptance is the same as for any writer: the part's own test suite, then
 * the Agency's differential against the reference, which the talent never
 * sees. *)

type outcome =
  | Derived of { name : string; definition : string }
  | Declined of { name : string; why : string }

let adapter () =
  match Sys.getenv_opt "GW_SMYTH" with
  | Some p -> p
  | None -> "smyth_ocaml"

let book ~scratch ~timeout_s ~name sketch =
  let file = Filename.concat scratch (name ^ ".elm") in
  Probe.write file sketch;
  let o = Gigwerk.Proc.run ~root:scratch ~timeout_s [| adapter (); file |] in
  match o.Gigwerk.Proc.exit_status with
  | Some 0 ->
      (match List.rev (List.filter (fun l -> String.trim l <> "")
                         (String.split_on_char '\n' o.Gigwerk.Proc.stdout)) with
       | body :: _ -> Ok body
       | [] -> Error "Smyth printed nothing")
  | Some _ -> Error ("Smyth: " ^ String.trim o.Gigwerk.Proc.stderr)
  | None -> Error (Printf.sprintf "Smyth: no answer within %.0fs" timeout_s)

let derive ~scratch ~timeout_s (iface : Iface.t) examples (v : Iface.value_spec) =
  let name = v.Iface.vname in
  let exs = List.filter_map (fun (t, ex) -> if t = name then Some ex else None) examples in
  let exs = List.fold_left (fun acc (ex : Spec.example) ->
      if List.exists (fun (e : Spec.example) ->
          List.length e.Spec.args = List.length ex.Spec.args
          && List.for_all2 Value.equal e.Spec.args ex.Spec.args) acc then acc
      else acc @ [ ex ]) [] exs in
  if exs = [] then Declined { name; why = "no example of it could be read from the tests" }
  else
    let ty = Iface.expand iface.Iface.decls v.Iface.vty in
    let args, out = Types.unarrow ty in
    let params = Part.param_names args in
    match Smyth_contract.sketch ~decls:iface.Iface.decls ~name
            ~params:(List.map (fun (n, _, t) -> (n, t)) params) ~out_ty:out exs with
    | exception Smyth_contract.Unrepresentable what ->
        Declined { name; why = "Smyth's language cannot state " ^ what }
    | sketch ->
        (match book ~scratch ~timeout_s ~name sketch with
         | Ok body ->
             Derived { name; definition =
                         Smyth_contract.definition ~name ~params:(List.map (fun (n, l, _) -> (n, l)) params) body }
         | Error why -> Declined { name; why })

type report = {
  slug : string;
  outcomes : outcome list;
  source : string option;
  tests : [ `Passed | `Failed of string | `Not_run of string ];
  differential : (Verify.verdict, string) result option;
}

let solve ~env ~scratch ~exercise_dir ~slug ?(timeout_s = 60.) () =
  let m = Probe.module_name slug in
  let mli_src = Iface.read_file (Filename.concat exercise_dir (m ^ ".mli")) in
  let iface = Iface.parse_string mli_src in
  let probe = Probe.run ~env ~scratch ~exercise_dir ~slug in
  let outcomes =
    if iface.Iface.unreadable <> [] then
      [ Declined { name = "(interface)"; why = "cannot represent: " ^ String.concat " / " iface.Iface.unreadable } ]
    else if List.exists (fun (d : Types.decl) -> d.Types.kind = Types.Abstract) iface.Iface.decls then
      [ Declined { name = "(interface)"; why = "an abstract type has no representation to synthesize against" } ]
    else List.map (derive ~scratch ~timeout_s iface probe.Probe.examples) iface.Iface.values in
  let source =
    if outcomes <> [] && List.for_all (function Derived _ -> true | Declined _ -> false) outcomes then
      Some (Lower_ocaml.module_source ~mli_src
              ~definitions:(List.filter_map (function Derived d -> Some d.definition | Declined _ -> None) outcomes))
    else None in
  let tests = match source with
    | None -> `Not_run "not every value was derived"
    | Some source -> Part.run_tests ~env ~scratch ~exercise_dir ~slug ~source in
  let differential = match source, tests with
    | Some source, `Passed ->
        let reference = Iface.read_file (Filename.concat exercise_dir ".meta/example.ml") in
        Some (Verify.differential ~env ~scratch ~exercise_dir ~slug ~iface
                ~examples:probe.Probe.examples ~source ~reference ())
    | _ -> None in
  { slug; outcomes; source; tests; differential }

(* An ocaml.org problem: the statement's examples, its stated or inferred
   types (the parametric reading first), the same booking, and the
   statement's own replay and the Solution's differential as acceptance. *)
let solve_org ~path ?(timeout_s = 60.) ~scratch () =
  let md = Iface.read_file path in
  let slug = Filename.remove_extension (Filename.basename path) in
  let context = Transcript.context_before ~dir:(Filename.dirname path) ~slug in
  let p = Transcript.read ?context ~slug md in
  let decls = p.Transcript.decls in
  let target (name, stated, exs) =
    let types = match stated with
      | Some t -> [ t ]
      | None -> List.filter_map Fun.id
                  [ Transcript.infer_type decls exs ~parametric:true;
                    Transcript.infer_type decls exs ~parametric:false ] in
    let attempt ty =
      let args, out = Types.unarrow ty in
      let params = Part.param_names args in
      match Smyth_contract.sketch ~decls ~name ~params:(List.map (fun (n, _, t) -> (n, t)) params) ~out_ty:out exs with
      | exception Smyth_contract.Unrepresentable what -> Error ("Smyth's language cannot state " ^ what)
      | sketch ->
          Result.map (fun body ->
              (Smyth_contract.definition ~name ~params:(List.map (fun (n, l, _) -> (n, l)) params) body, ty))
            (book ~scratch ~timeout_s ~name sketch) in
    let rec first why = function
      | [] -> (Declined { name; why }, None)
      | ty :: rest -> (match attempt ty with
          | Ok (definition, ty) -> (Derived { name; definition }, Some ty)
          | Error w -> first (if why = "" then w else why ^ "; " ^ w) rest) in
    if types = [] then (Declined { name; why = "its examples do not determine a type" }, None)
    else first "" types in
  let typed =
    if p.Transcript.targets = [] then
      [ (Declined { name = "(statement)"; why = "the statement shows no example of a function to write" }, None) ]
    else List.map target p.Transcript.targets in
  let outcomes = List.map fst typed in
  let all = List.for_all (function Derived _ -> true | Declined _ -> false) outcomes in
  let decl_src = String.concat "\n" p.Transcript.decl_source in
  let source = if not all then None else
      Some (String.concat "\n" (List.filter_map (function
          | Derived d -> Some (d.definition ^ ";;") | Declined _ -> None) outcomes)) in
  let tests = match source with
    | None -> `Not_run "not every function was derived"
    | Some s -> Ocamlorg.replay p md (decl_src ^ "\n" ^ s) in
  let differential = match source, tests with
    | Some s, `Passed ->
        let types = List.filter_map (function
            | (Derived { name; _ }, Some ty) -> Some (name, ty) | _ -> None) typed in
        let examples = List.concat_map (fun (n, _, exs) -> List.map (fun e -> (n, e)) exs) p.Transcript.targets in
        let reference = Transcript.reference_with_context ~dir:(Filename.dirname path) ~slug md in
        Some (Ocamlorg.differential p ~examples ~source:s ~reference ~slug ~targets:types)
    | _ -> None in
  { slug; outcomes; source = Option.map (fun s -> decl_src ^ "\n" ^ s) source; tests; differential }
