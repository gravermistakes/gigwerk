(* One ocaml.org exercise, end to end: read the Statement, derive each
 * function it shows examples of, and check what was written two ways, both
 * through the real `ocaml` toplevel:
 *
 *   - replay: the Statement's own transcript, run against the written
 *     definitions, must print the values the Statement shows;
 *   - differential: written definitions and the Solution's, side by side on
 *     inputs neither has seen. Only this step reads the Solution. *)

open Types

type derivation = Part.derivation

type report = {
  slug : string;
  derivations : derivation list;
  source : string option;
  replay : [ `Passed | `Failed of string | `Not_run of string ];
  differential : (Verify.verdict, string) result option;
  unread : string list;
  examples : (string * Spec.example) list;
  library_used : Library.entry list;       (* the Agency's earlier work this part reached *)
}

let toplevel ~stdin_text =
  let dir = Filename.get_temp_dir_name () in
  let f = Filename.temp_file ~temp_dir:dir "gw_top" ".ml" in
  Probe.write f stdin_text;
  let o = Gigwerk.Proc.run ~root:dir ~timeout_s:120. [| "ocaml"; "-noinit"; "-color"; "never"; f |] in
  (try Sys.remove f with _ -> ());
  (o.Gigwerk.Proc.exit_status, o.Gigwerk.Proc.stdout ^ o.Gigwerk.Proc.stderr)

(* Derive one target under a type, falling back from the parametric reading
   to the concrete one. *)
let derive_target ?cfg (p : Transcript.part) (name, stated, examples) =
  let reasons = ref [] in
  let attempt ty =
    let args, out = unarrow ty in
    let params = Part.param_names args in
    match Part.bounded (fun () ->
        Topdown.solve_param ?cfg ~self:name ~decls:p.Transcript.decls
          ~params:(List.map (fun (n, _, t) -> (n, t)) params) ~out_ty:out examples) with
    | Topdown.Solved (body, n) ->
        Some (Part.Derived { name; params = List.map (fun (n, l, _) -> (n, l)) params; body; considered = n }, ty)
    | Topdown.Gave_up why -> reasons := (Types.to_string ty ^ ": " ^ why) :: !reasons; None
    | exception Out_of_memory -> reasons := (Types.to_string ty ^ ": memory bound reached") :: !reasons; None
  in
  let types = match stated with
    | Some t -> [ t ]
    | None ->
        List.filter_map Fun.id
          [ Transcript.infer_type p.Transcript.decls examples ~parametric:true;
            Transcript.infer_type p.Transcript.decls examples ~parametric:false ] in
  (* parametric reading first; drop a duplicate, keeping order *)
  let types = List.fold_left (fun acc t ->
      if List.exists (fun u -> Types.to_string u = Types.to_string t) acc then acc else acc @ [ t ]) [] types in
  if Sys.getenv_opt "GW_DEBUG" <> None then
    prerr_endline ("  types for " ^ name ^ ": " ^ String.concat " | " (List.map Types.to_string types));
  if types = [] then (Part.Declined { name; why = "its examples do not determine a type" }, None)
  else match List.find_map attempt types with
    | Some (d, ty) when !reasons <> [] ->
        prerr_endline ("  (" ^ name ^ ": " ^ String.concat "; " (List.rev !reasons) ^ ")"); (d, Some ty)
    | Some (d, ty) -> (d, Some ty)
    | None -> (Part.Declined { name; why = "no derivation within the search bounds ("
                                            ^ String.concat "; " (List.rev !reasons) ^ ")" }, None)

let replay (p : Transcript.part) md source =
  let st = Transcript.section "Statement" md in
  let exs = List.concat_map Transcript.exchanges (Transcript.code_blocks st) in
  let checks = List.filter_map (fun ex ->
      match Transcript.split_response ex.Transcript.response with
      | Some (None, _, v) -> Some (ex.Transcript.phrase, v)
      | _ -> None) exs in
  let lets = List.filter_map (fun ex ->
      match Transcript.split_response ex.Transcript.response with
      | Some (Some _, _, _) -> Some (ex.Transcript.phrase ^ ";;")
      | _ -> None) exs in
  ignore p;
  let checks = List.filter (fun (_, v) ->
      not (Str.string_match (Str.regexp ".*<\\(fun\\|abstr\\|poly\\)>") v 0)) checks in
  if checks = [] then `Not_run "the statement shows no value to replay"
  else
    (* the shown value, parsed by the compiler, compared structurally *)
    let script = source ^ "\n" ^ String.concat "\n" lets ^ "\n"
                 ^ String.concat "\n" (List.mapi (fun i (ph, want) ->
                     Printf.sprintf "let () = print_endline (\"__GW %d \" ^ (try if (%s) = (%s) then \"ok\" else \"no\" with _ -> \"raised\"));;"
                       i ph want) checks) in
    let _, out = toplevel ~stdin_text:script in
    let failures = List.filteri (fun i _ ->
        not (Str.string_match (Str.regexp (Printf.sprintf ".*__GW %d ok" i)) (String.map (fun c -> if c = '\n' then ' ' else c) out) 0)) checks in
    if failures = [] then `Passed
    else `Failed (String.concat "; " (List.map (fun (ph, w) -> ph ^ " should be " ^ w) failures)
                  ^ (if String.length out < 600 then " / " ^ out else ""))

(* Fresh inputs, the written definitions and the Solution side by side. *)
let differential ?(salt = "") ?(per_value = 200) (p : Transcript.part) ~examples ~source ~reference ~slug ~targets =
  Verify.state := Random.State.make [| 0x5eed; Hashtbl.hash slug; Hashtbl.hash salt |];
  let decls = p.Transcript.decls in
  let calls = List.concat_map (fun (name, ty) ->
      let exs = List.filter_map (fun (t, ex) -> if t = name then Some ex else None) examples in
      let args, _ = unarrow ty in
      let labels = List.map fst args in
      (* concrete argument types for generation: a rigid 'a draws ints *)
      List.map (fun inp -> (name, Verify.call_source ~name ~labels inp, inp))
        (Verify.inputs_for decls { Iface.vname = name; vty = ty } exs per_value)) targets in
  if calls = [] then Error "no input could be generated"
  else
    let iface = { Iface.decls; values = List.map (fun (n, t) -> { Iface.vname = n; vty = t }) targets;
                  unreadable = []; opens = [] } in
    let printers = Probe.result_printers iface in
    let body = String.concat "\n" (List.mapi (fun i (name, src, _) ->
        Printf.sprintf "let () = (try print_endline (\"%d\\t\" ^ __gw_print_%s %s) with e -> print_endline (\"%d\\t!\" ^ Printexc.to_string e));;"
          i name src i) calls) in
    let run impl =
      let _, out = toplevel ~stdin_text:(impl ^ "\n;;\n" ^ printers ^ "\n;;\n" ^ body) in
      List.filter_map (fun line -> match String.index_opt line '\t' with
          | Some i -> Some (String.sub line 0 i, String.sub line (i + 1) (String.length line - i - 1))
          | None -> None) (String.split_on_char '\n' out) in
    let decl_src = String.concat "\n" p.Transcript.decl_source in
    let wt = run (decl_src ^ "\n" ^ source) and rt = run (decl_src ^ "\n" ^ reference) in
    if rt = [] then Error "the Solution did not run beside the generated calls"
    else
      let compared = ref 0 and agreed = ref 0 and dis = ref [] and samples = ref [] and misses = ref [] in
      List.iteri (fun i (name, src, inp) ->
          let id = string_of_int i in
          match List.assoc_opt id rt, List.assoc_opt id wt with
          | Some rv, _ when String.length rv > 0 && rv.[0] = '!' -> ()
          | Some rv, w ->
              incr compared;
              let answer = Literal.of_string_opt rv in
             (match answer with
               | Some v -> samples := (name, inp, v) :: !samples | None -> ());
             let miss () = match answer with Some v -> misses := (name, inp, v) :: !misses | None -> () in
              (match w with
               | Some wv when Verify.close_enough wv rv -> incr agreed
               | Some wv -> miss (); dis := Printf.sprintf "%s = %s, reference %s" src wv rv :: !dis
               | None -> miss (); dis := Printf.sprintf "%s: no output, reference %s" src rv :: !dis)
          | None, _ -> ()) calls;
      Ok { Verify.compared = !compared; agreed = !agreed; disagreements = List.rev !dis; samples = List.rev !samples;
         misses = List.rev !misses }

let solve ?cfg ?library ~path () =
  let md = Iface.read_file path in
  let slug = Filename.remove_extension (Filename.basename path) in
  let context = Transcript.context_before ~dir:(Filename.dirname path) ~slug in
  let p = Transcript.read ?context ~slug md in
  Hashtbl.reset Components.siblings;
  let lib = match library with
    | None -> []
    | Some dir ->
        let entries = Library.before ~dir ~slug ~exclude:(List.map (fun (n, _, _) -> n) p.Transcript.targets)
            ~known_types:(List.map (fun d -> d.Types.name) p.Transcript.decls) in
        Library.register entries; entries in
  let typed =
    if p.Transcript.targets = [] then
      [ (Part.Declined { name = "(statement)"; why = "the statement shows no example of a function to write" }, None) ]
    else List.map (derive_target ?cfg p) p.Transcript.targets in
  let derivations = List.map fst typed in
  let all = List.for_all (function Part.Derived _ -> true | _ -> false) derivations in
  (* library entries the derived terms reach go first, in library order *)
  let used = Library.reached lib (List.filter_map (function Part.Derived { body; _ } -> Some body | _ -> None) derivations) in
  let source =
    if not all then None
    else Some (String.concat "\n" (List.map (fun (e : Library.entry) ->
        Lower_ocaml.definition ~name:e.name ~params:e.params e.body ^ ";;") used
        @ List.filter_map (function
        | Part.Derived { name; params; body; _ } -> Some (Lower_ocaml.definition ~name ~params body ^ ";;")
        | _ -> None) derivations)) in
  let decl_src = String.concat "\n" p.Transcript.decl_source in
  let replay_v = match source with
    | None -> `Not_run "not every function was derived"
    | Some s -> replay p md (decl_src ^ "\n" ^ s) in
  let differential = match source with
    | None -> None
    | Some s ->
        let types = List.filter_map (function
            | (Part.Derived { name; _ }, Some ty) -> Some (name, ty)
            | _ -> None) typed in
        let examples = List.concat_map (fun (n, _, exs) -> List.map (fun e -> (n, e)) exs) p.Transcript.targets in
        let reference = Transcript.reference_with_context ~dir:(Filename.dirname path) ~slug md in
        Some (differential p ~examples ~source:s ~reference ~slug ~targets:types) in
  (* the Agency keeps what passed the part's own check *)
  (match library, replay_v with
   | Some dir, `Passed ->
       Library.save ~dir ~slug (List.filter_map (function
           | (Part.Derived { name; params; body; _ }, Some ty) -> Some { Library.slug; name; params; ty; body }
           | _ -> None) typed)
   | _ -> ());
  { slug; derivations; source = Option.map (fun s -> decl_src ^ "\n" ^ s) source; replay = replay_v;
    differential; unread = p.Transcript.unread;
    examples = List.concat_map (fun (n, _, exs) -> List.map (fun e -> (n, e)) exs) p.Transcript.targets;
    library_used = used }
