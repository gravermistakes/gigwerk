(* One Exercism part, end to end: read it, derive each value it asks for, write
 * the module, and run the part's own test suite against what was written.
 *
 * A value with no examples is declined, in words: the writer does not guess
 * at a function nobody has shown it. A part with any declined value is not
 * delivered, since a module missing a value does not compile against its
 * interface, and stubbing one would be handing in work that is not there. *)

open Types

type derivation =
  | Derived of { name : string; params : (string * label) list; body : Expr.t; considered : int }
  | Declined of { name : string; why : string }

type report = {
  slug : string;
  derivations : derivation list;
  source : string option;          (* the module, when every value was derived *)
  tests : [ `Passed | `Failed of string | `Not_run of string ];
  differential : (Verify.verdict, string) result option;
  examples : (string * Spec.example) list;
}

let param_names args =
  let used = Hashtbl.create 8 in
  List.mapi (fun i (l, t) ->
      let base = match l with
        | Labelled s | Optional s -> s
        | Nolabel -> (match i with 0 -> "x" | 1 -> "y" | 2 -> "z" | n -> "a" ^ string_of_int n) in
      let name = if Hashtbl.mem used base then base ^ string_of_int i else base in
      Hashtbl.replace used name ();
      let t = match l with Optional _ -> t_option t | _ -> t in
      (name, l, t)) args

(* What one value's derivation may cost, all its searches together: terms
   built and evaluation steps taken. Counts, so a decline is reproducible. *)
let default_work = 6_000_000
let default_spend = 1_500_000_000

(* One derivation under the bounds, counted from zero. *)
let bounded f =
  let cap var d = match Option.bind (Sys.getenv_opt var) int_of_string_opt with Some n -> n | None -> d in
  Synth.work := 0; Eval.spent := 0;
  Synth.work_cap := cap "GW_WORK" default_work;
  Synth.spend_cap := cap "GW_SPEND" default_spend;
  match f () with
  | Topdown.Gave_up why when Synth.over_budget () ->
      Topdown.Gave_up (Printf.sprintf "work bound reached: %d terms built, %d evaluation steps (%s)"
                         !Synth.work !Eval.spent why)
  | r -> r

let derive ?cfg (iface : Iface.t) (examples : (string * Spec.example) list) (v : Iface.value_spec) =
  let decls = iface.Iface.decls in
  let exs = List.filter_map (fun (t, ex) -> if t = v.Iface.vname then Some ex else None) examples in
  (* the same call asked twice is one example *)
  let exs = List.fold_left (fun acc ex ->
      if List.exists (fun e -> List.for_all2 Value.equal e.Spec.args ex.Spec.args) acc then acc
      else acc @ [ ex ]) [] exs in
  if exs = [] then Declined { name = v.Iface.vname; why = "no example of it could be read from the tests" }
  else
    let ty = Iface.expand decls v.Iface.vty in
    let args, out = unarrow ty in
    let params = param_names args in
    let result = bounded (fun () ->
        try Topdown.solve_param ?cfg ~self:v.Iface.vname ~decls ~params:(List.map (fun (n, _, t) -> (n, t)) params) ~out_ty:out exs
        with Out_of_memory -> Topdown.Gave_up "memory bound reached") in
    if Sys.getenv_opt "GW_DEBUG" <> None then
      Printf.eprintf "  [%s: %d terms built, %d evaluation steps]\n%!" v.Iface.vname !Synth.work !Eval.spent;
    match result with
    | Topdown.Solved (body, considered) ->
        Derived { name = v.Iface.vname; params = List.map (fun (n, l, _) -> (n, l)) params; body; considered }
    | Topdown.Gave_up why -> Declined { name = v.Iface.vname; why }

(* A derived value becomes a component for the part's later values. *)
let register_sibling (iface : Iface.t) name params body =
  match List.find_opt (fun v -> v.Iface.vname = name) iface.Iface.values with
  | None -> ()
  | Some v when params <> [] ->
      let ty = Iface.expand iface.Iface.decls v.Iface.vty in
      let args, out = unarrow ty in
      let args = List.map (fun (l, t) -> match l with Optional _ -> t_option t | _ -> t) args in
      let rec gen t = match repr t with
        | TVar x -> TGen (Hashtbl.hash x land 0xff)
        | TCon (n, ts) -> TCon (n, List.map gen ts)
        | TTuple ts -> TTuple (List.map gen ts)
        | TArrow (l, a, b) -> TArrow (l, gen a, gen b)
        | t -> t in
      let names = List.map fst params in
      let impl vals =
        match Eval.run ~budget:!Eval.fuel (List.combine names vals)
                (Expr.Let (true, name, Expr.Lam (names, body), Expr.App (Expr.Var name, List.map (fun v -> Expr.Lit v) vals))) with
        | Some v -> v | None -> raise Components.Undefined in
      Hashtbl.replace Eval.components name
        { Components.name; scheme = gen (arrows args out); impl;
          ocaml = (fun a -> "(" ^ String.concat " " (name :: a) ^ ")") };
      Hashtbl.replace Components.siblings name (List.length params)
  | Some _ -> ()

let run_tests ~env ~scratch ~exercise_dir ~slug ~source =
  let dir = Filename.concat scratch (slug ^ "-accept") in
  Probe.stage_copy ~src:exercise_dir ~dst:dir;
  Probe.write (Filename.concat dir (Probe.module_name slug ^ ".ml")) source;
  match Probe.run_cmd ~cwd:dir (Array.append env [| "dune"; "runtest" |]) with
  | Some 0, _ -> `Passed
  | _, log -> `Failed log

(* The actor's work on a part: read it, derive, write the module. Nothing in
   here opens .meta; the material may not even contain it. *)
type written = {
  w_slug : string;
  w_iface : Iface.t;
  w_derivations : derivation list;
  w_source : string option;
  w_examples : (string * Spec.example) list;
}

let rec write ?cfg ~env ~scratch ~exercise_dir ~slug () =
  let m = Probe.module_name slug in
  let mli_src = Iface.read_file (Filename.concat exercise_dir (m ^ ".mli")) in
  let probe = Probe.run ~env ~scratch ~exercise_dir ~slug in
  derive_all ?cfg ~slug ~mli_src probe.Probe.examples

and derive_all ?cfg ~slug ~mli_src examples =
  let iface = Iface.parse_string mli_src in
  let probe = { Probe.examples; sites = 0; log = "" } in
  let derivations =
    if iface.Iface.unreadable <> [] then
      [ Declined { name = "(interface)"; why = "cannot represent: " ^ String.concat " / " iface.Iface.unreadable } ]
    else if List.exists (fun d -> d.kind = Abstract) iface.Iface.decls then
      [ Declined { name = "(interface)";
                   why = "an abstract type needs a representation the writer would have to invent" } ]
    else begin
      Hashtbl.reset Components.siblings;
      List.map (fun v ->
          let d = derive ?cfg iface probe.Probe.examples v in
          (match d with
           | Derived { name; params; body; _ } -> register_sibling iface name params body
           | Declined _ -> ());
          d) iface.Iface.values
    end in
  let all_derived = derivations <> [] && List.for_all (function Derived _ -> true | Declined _ -> false) derivations in
  let source =
    if not all_derived then None
    else
      let defs = List.filter_map (function
          | Derived { name; params; body; _ } -> Some (Lower_ocaml.definition ~name ~params body)
          | Declined _ -> None) derivations in
      Some (Lower_ocaml.module_source ~mli_src ~definitions:defs)
  in
  { w_slug = slug; w_iface = iface; w_derivations = derivations; w_source = source; w_examples = probe.Probe.examples }

(* The part's own check: its published test suite, against what was written. *)
let own_check ~env ~scratch ~exercise_dir (w : written) =
  match w.w_source with
  | None -> `Not_run "not every value was derived"
  | Some source -> run_tests ~env ~scratch ~exercise_dir ~slug:w.w_slug ~source

(* The Agency's verifier, separate from the actor: the only reader of the
   reference, after the module is written. *)
let verify ~env ~scratch ~exercise_dir (w : written) =
  match w.w_source with
  | None -> None
  | Some source ->
      let reference = Iface.read_file (Filename.concat exercise_dir ".meta/example.ml") in
      Some (Verify.differential ~env ~scratch ~exercise_dir ~slug:w.w_slug ~iface:w.w_iface
              ~examples:w.w_examples ~source ~reference ())

let solve ?cfg ~env ~scratch ~exercise_dir ~slug () =
  let w = write ?cfg ~env ~scratch ~exercise_dir ~slug () in
  let tests = own_check ~env ~scratch ~exercise_dir w in
  let differential = verify ~env ~scratch ~exercise_dir w in
  { slug; derivations = w.w_derivations; source = w.w_source; tests; differential; examples = w.w_examples }
