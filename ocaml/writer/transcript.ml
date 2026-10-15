(* An ocaml.org exercise, read from its Statement alone.
 *
 * The page has two sections. The Solution is the reference: only the verifier
 * reads it (`reference`). The Statement is the part: prose, and toplevel
 * transcripts like
 *
 *     # last ["a" ; "b" ; "c" ; "d"];;
 *     - : string option = Some "d"
 *
 * Each `# f args;;` followed by `- : t = v` is one example of f. Types and
 * values a transcript defines (`# type ...;;`, `# let t = ...;;` answered by
 * `val t : ... = v`) are kept so later examples can use them.
 *
 * The type of f is the one the prose states (`last : 'a list -> 'a option`)
 * when it states one. Otherwise it is inferred from the example values, and
 * then generalized where the data allows: a base type whose every value in
 * the outputs also occurs in the inputs is treated as a rigid 'a, because a
 * function that only moves such values around is the parametric one. This is
 * parametricity read off the examples; if the general type admits no
 * derivation, the caller retries with the concrete one. *)

open Types

type block = string list

let read_file = Iface.read_file

let section name md =
  let lines = String.split_on_char '\n' md in
  let rec find = function
    | [] -> []
    | l :: rest when String.trim l = "## " ^ name -> rest
    | _ :: rest -> find rest in
  let rec upto acc = function
    | [] -> List.rev acc
    | l :: _ when String.length l > 3 && String.sub l 0 3 = "## " -> List.rev acc
    | l :: rest -> upto (l :: acc) rest in
  upto [] (find lines)

let code_blocks lines : block list =
  let rec go acc cur = function
    | [] -> List.rev acc
    | l :: rest ->
        let t = String.trim l in
        (match cur with
         | None when String.length t >= 3 && String.sub t 0 3 = "```" -> go acc (Some []) rest
         | None -> go acc None rest
         | Some b when t = "```" -> go (List.rev b :: acc) None rest
         | Some b -> go acc (Some (l :: b)) rest)
  in
  go [] None lines

let prose lines = String.concat "\n" lines

(* A toplevel phrase and the response printed after it. *)
type exchange = { phrase : string; response : string }

let exchanges (b : block) =
  let is_prompt l = String.length l >= 2 && String.sub l 0 2 = "# " in
  let ends_phrase l = let t = String.trim l in
    String.length t >= 2 && String.sub t (String.length t - 2) 2 = ";;" in
  let rec go acc = function
    | [] -> List.rev acc
    | l :: rest when is_prompt l ->
        let rec phrase p = function
          | [] -> (List.rev p, [])
          | x :: xs when ends_phrase x -> (List.rev (x :: p), xs)
          | x :: xs -> phrase (x :: p) xs in
        let first = String.sub l 2 (String.length l - 2) in
        let lines, rest =
          if ends_phrase first then ([ first ], rest) else phrase [ first ] rest in
        let rec resp r = function
          | x :: xs when not (is_prompt x) -> resp (x :: r) xs
          | xs -> (List.rev r, xs) in
        let response, rest = resp [] rest in
        let ph = String.concat "\n" lines in
        let ph = String.sub ph 0 (String.rindex ph ';' - 1) in
        go ({ phrase = ph; response = String.concat "\n" response } :: acc) rest
    | _ :: rest -> go acc rest
  in
  go [] b

(* `- : t = v` or `val x : t = v`, to (type text, value text). *)
let split_response r =
  (* a long answer wraps: `- : string rle list =` then the value on the next
     line, so line breaks are spaces here *)
  let r = String.trim (String.map (fun c -> if c = '\n' || c = '\r' || c = '\t' then ' ' else c) r) in
  let after_colon s =
    match String.index_opt s ':' with
    | None -> None
    | Some i ->
        let rest = String.sub s (i + 1) (String.length s - i - 1) in
        (* the type ends at the first " = " not inside brackets *)
        let depth = ref 0 and cut = ref (-1) in
        String.iteri (fun k c ->
            if !cut < 0 then
              match c with
              | '(' | '[' | '{' -> incr depth
              | ')' | ']' | '}' -> decr depth
              | '=' when !depth = 0 && k > 0 && rest.[k - 1] = ' '
                         && k + 1 < String.length rest && rest.[k + 1] = ' ' -> cut := k
              | _ -> ()) rest;
        if !cut < 0 then None
        else Some (String.trim (String.sub rest 0 !cut),
                   String.trim (String.sub rest (!cut + 1) (String.length rest - !cut - 1)))
  in
  if String.length r >= 2 && String.sub r 0 2 = "- " then
    Option.map (fun (t, v) -> (None, t, v)) (after_colon r)
  else if String.length r >= 4 && String.sub r 0 4 = "val " then
    let name = String.trim (String.sub r 4 (String.index r ':' - 4)) in
    Option.map (fun (t, v) -> (Some name, t, v)) (after_colon r)
  else None

let type_of_text s =
  try Some (Iface.ty_of_core (Parse.core_type (Lexing.from_string s))) with _ -> None

(* ------------------------------------------------- types of example values *)

let ctor_decl decls c =
  List.find_opt (fun d -> match d.kind with
      | Variant cs -> List.mem_assoc c cs | _ -> false) decls

let rec infer decls (v : Value.t) : ty =
  match v with
  | Value.Int _ -> t_int | Value.Int64 _ -> t_int64 | Value.Float _ -> t_float
  | Value.Bool _ -> t_bool | Value.Char _ -> t_char | Value.String _ -> t_string | Value.Unit -> t_unit
  | Value.List l ->
      let t = fresh () in
      List.iter (fun x -> (try unify t (infer decls x) with Mismatch -> ())) l; t_list t
  | Value.Array a ->
      let t = fresh () in Array.iter (fun x -> (try unify t (infer decls x) with Mismatch -> ())) a; t_array t
  | Value.Tuple xs -> TTuple (List.map (infer decls) xs)
  | Value.Con ("None", []) -> t_option (fresh ())
  | Value.Con ("Some", [ x ]) -> t_option (infer decls x)
  | Value.Con ("Ok", [ x ]) -> t_result (infer decls x) (fresh ())
  | Value.Con ("Error", [ x ]) -> t_result (fresh ()) (infer decls x)
  | Value.Con (c, args) ->
      (match ctor_decl decls c with
       | Some d ->
           let sub = List.map (fun p -> (p, fresh ())) d.params in
           let rec inst t = match repr t with
             | TVar v -> (match List.assoc_opt v sub with Some m -> m | None -> t)
             | TCon (n, ts) -> TCon (n, List.map inst ts)
             | TTuple ts -> TTuple (List.map inst ts) | t -> t in
           (match d.kind with
            | Variant cs ->
                let arg_tys = List.map inst (List.assoc c cs) in
                let args = if List.length arg_tys > 1 && List.length args = 1
                  then (match args with [ Value.Tuple xs ] -> xs | _ -> args) else args in
                (try List.iter2 (fun t a -> unify t (infer decls a)) arg_tys args with _ -> ())
            | _ -> ());
           TCon (d.name, List.map snd sub)
       | None -> fresh ())
  | Value.Poly _ -> fresh ()
  | Value.Record fs ->
      (match List.find_opt (fun d -> match d.kind with
           | Record fields -> List.map fst fields = List.map fst fs | _ -> false) decls with
       | Some d -> TCon (d.name, List.map (fun _ -> fresh ()) d.params)
       | None -> fresh ())
  | Value.Fun _ -> fresh ()

(* Metas left unbound become rigid variables 'a, 'b, ... *)
let generalize t =
  let names = ref [] and n = ref 0 in
  let rec go t = match repr t with
    | TMeta r ->
        (match List.assq_opt r !names with
         | Some v -> v
         | None ->
             let v = TVar (String.make 1 (Char.chr (Char.code 'a' + !n))) in
             incr n; names := (r, v) :: !names; v)
    | TCon (c, ts) -> TCon (c, List.map go ts)
    | TTuple ts -> TTuple (List.map go ts)
    | TArrow (l, a, b) -> TArrow (l, go a, go b)
    | t -> t in
  go t

(* ---------------------------------------------------------------- reading *)

type part = {
  slug : string;
  decls : decl list;
  decl_source : string list;             (* the statement's own type phrases *)
  bindings : (string * Value.t) list;    (* `# let x = ...` answered with a value *)
  targets : (string * ty option * Spec.example list) list;   (* stated type, if any *)
  unread : string list;                  (* phrases not read as examples *)
}

let rec flatten_app (e : Parsetree.expression) =
  match e.pexp_desc with
  | Pexp_apply (f, args) -> (f, args)
  | Pexp_constraint (e, _) -> flatten_app e
  | _ -> (e, [])

let arg_value bindings (e : Parsetree.expression) =
  match e.pexp_desc with
  | Pexp_ident { txt = Longident.Lident x; _ } when List.mem_assoc x bindings -> Some (List.assoc x bindings)
  | _ -> (try Some (Literal.value e) with _ -> None)

let stated_types text =
  (* `name : type` in backquotes *)
  let re = Str.regexp "`\\([a-z_][a-zA-Z0-9_']*\\) : \\([^`]+\\)`" in
  let rec go pos acc =
    match Str.search_forward re text pos with
    | exception Not_found -> List.rev acc
    | _ ->
        let name = Str.matched_group 1 text and t = Str.matched_group 2 text in
        go (Str.match_end ()) ((name, t) :: acc)
  in
  List.filter_map (fun (n, t) -> Option.map (fun t -> (n, t)) (type_of_text t)) (go 0 [])

let read ?(context : part option) ~slug md : part =
  let st = section "Statement" md in
  let blocks = code_blocks st in
  (* what earlier Statements declared and named, carried forward: the
     problems build on one another ("the tree t of the previous problem") *)
  let decls = ref (match context with Some c -> c.decls | None -> [])
  and decl_src = ref (match context with Some c -> c.decl_source | None -> [])
  and bindings = ref (match context with Some c -> c.bindings | None -> [])
  and unread = ref [] in
  let examples : (string * Spec.example) list ref = ref [] in
  List.iter (fun b ->
      (* a block of plain definitions, with no prompt, still declares types *)
      let exs = exchanges b in
      let phrases = if exs = [] then [ { phrase = String.concat "\n" b; response = "" } ] else exs in
      List.iter (fun ex ->
          match Parse.implementation (Lexing.from_string ex.phrase) with
          | exception _ -> unread := ex.phrase :: !unread
          | items ->
              List.iter (fun (item : Parsetree.structure_item) ->
                  match item.pstr_desc with
                  | Pstr_type (_, tds) ->
                      (try
                         decls := !decls @ List.map Iface.decl_of tds;
                         decl_src := !decl_src @ [ Format.asprintf "%a" Pprintast.structure [ item ] ]
                       with _ -> unread := ex.phrase :: !unread)
                  | Pstr_value (_, vbs) ->
                      List.iter (fun (vb : Parsetree.value_binding) ->
                          match vb.pvb_pat.ppat_desc, split_response ex.response with
                          | Parsetree.Ppat_var { txt; _ }, Some (Some _, _, v) ->
                              (match Literal.of_string_opt v with
                               | Some v -> bindings := (txt, v) :: !bindings
                               | None -> unread := ex.phrase :: !unread)
                          | Parsetree.Ppat_var { txt; _ }, _ ->
                              (* a definition with no toplevel answer is still a
                                 value when its right-hand side is a literal *)
                              (match arg_value !bindings vb.pvb_expr with
                               | Some v -> bindings := (txt, v) :: !bindings
                               | None -> unread := ex.phrase :: !unread)
                          | _ -> unread := ex.phrase :: !unread) vbs
                  | Pstr_eval (e, _) ->
                      (* `not (f args)` shown as true says f args is false *)
                      let e, negate = match e.pexp_desc with
                        | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Longident.Lident "not"; _ }; _ }, [ (_, inner) ]) -> (inner, true)
                        | _ -> (e, false) in
                      let f, args = flatten_app e in
                      (match f.pexp_desc, split_response ex.response with
                       | Pexp_ident { txt = Longident.Lident name; _ }, Some (None, _, v)
                         when args <> [] && List.for_all (fun (l, _) -> l = Asttypes.Nolabel) args ->
                           let vals = List.map (fun (_, a) -> arg_value !bindings a) args in
                           let lit = match Literal.of_string_opt v, negate with
                             | Some (Value.Bool b), true -> Some (Value.Bool (not b))
                             | _, true -> None
                             | l, false -> l in
                           (match lit with
                            | Some out when List.for_all Option.is_some vals ->
                                examples := !examples @ [ (name, { Spec.args = List.map Option.get vals; out }) ]
                            | _ -> unread := ex.phrase :: !unread)
                       | _ -> unread := ex.phrase :: !unread)
                  | _ -> unread := ex.phrase :: !unread) items) phrases) blocks;
  let stated = stated_types (prose st) in
  let names = List.sort_uniq compare (List.map fst !examples) in
  let names = List.filter (fun n -> not (List.mem_assoc n !bindings)) names in
  let targets = List.map (fun n ->
      (n, List.assoc_opt n stated,
       List.filter_map (fun (m, ex) -> if m = n then Some ex else None) !examples)) names in
  { slug; decls = !decls; decl_source = !decl_src; bindings = !bindings; targets; unread = List.rev !unread }

(* The type of a target: stated, or inferred from its examples and then the
   parametric generalization the data allows (see the head of this file). *)
let infer_type decls (examples : Spec.example list) ~parametric =
  match examples with
  | [] -> None
  | ex0 :: _ ->
      let arity = List.length ex0.Spec.args in
      if List.exists (fun ex -> List.length ex.Spec.args <> arity) examples then None
      else
        let args = List.init arity (fun _ -> fresh ()) and res = fresh () in
        let ok = List.for_all (fun ex ->
            try
              List.iter2 (fun t v -> unify t (infer decls v)) args ex.Spec.args;
              unify res (infer decls ex.Spec.out); true
            with Mismatch -> false) examples in
        if not ok then None
        else
          let t = arrows args res in
          let t = generalize t in
          if not parametric then Some t
          else
            (* base types whose output values all occur in the inputs *)
            let rec values_of_type ty v = match repr ty, v with
              | TCon (("int" | "string" | "char" | "float" | "bool"), []), _ -> [ v ]
              | TCon ("list", [ a ]), Value.List l -> List.concat_map (values_of_type a) l
              | TCon ("option", [ a ]), Value.Con ("Some", [ x ]) -> values_of_type a x
              | TTuple ts, Value.Tuple xs when List.length ts = List.length xs -> List.concat (List.map2 values_of_type ts xs)
              | _ -> [] in
            let base_in ty base = let rec go t = match repr t with
                | TCon (b, []) -> b = base
                | TCon (_, ts) | TTuple ts -> List.exists go ts
                | TArrow (_, a, r) -> go a || go r
                | _ -> false in go ty in
            (* ints and bools are left concrete: a count or a test result
               lands among the inputs by coincidence too easily (length
               [1;2;3] = 3), and calling that parametric would be false *)
            let candidates = List.filter (fun b -> base_in t b) [ "string"; "char"; "float" ] in
            let movable b =
              let of_base vs = List.filter (fun v -> match v, b with
                  | Value.String _, "string" | Value.Int _, "int" | Value.Char _, "char"
                  | Value.Float _, "float" | Value.Bool _, "bool" -> true | _ -> false) vs in
              let arg_tys = List.map snd (fst (unarrow t)) and out_ty = snd (unarrow t) in
              List.for_all (fun ex ->
                  let ins = of_base (List.concat (List.map2 values_of_type arg_tys ex.Spec.args)) in
                  let outs = of_base (values_of_type out_ty ex.Spec.out) in
                  List.for_all (fun o -> List.exists (Value.equal o) ins) outs) examples
              && List.exists (fun ex -> of_base (values_of_type out_ty ex.Spec.out) <> []
                                        || of_base (List.concat (List.map2 values_of_type arg_tys ex.Spec.args)) <> []) examples in
            let gen = List.filter movable candidates in
            let n = ref 0 in
            let sub = List.map (fun b -> incr n; (b, TVar ("p" ^ string_of_int !n))) gen in
            let rec go t = match repr t with
              | TCon (b, []) when List.mem_assoc b sub -> List.assoc b sub
              | TCon (c, ts) -> TCon (c, List.map go ts)
              | TTuple ts -> TTuple (List.map go ts)
              | TArrow (l, a, b) -> TArrow (l, go a, go b)
              | t -> t in
            Some (go t)

(* The reference, for the verifier only: the Solution's phrases. *)
let reference md =
  let blocks = code_blocks (section "Solution" md) in
  String.concat "\n" (List.concat_map (fun b ->
      let exs = exchanges b in
      if exs = [] then [ String.concat "\n" b ^ "\n;;" ]
      else List.map (fun e -> e.phrase ^ ";;") exs) blocks)

(* Names an OCaml source text uses, and the top-level names it defines. *)
let uses_and_defines src =
  match Parse.implementation (Lexing.from_string src) with
  | exception _ -> ([], [])
  | items ->
      let used = ref [] in
      let it = { Ast_iterator.default_iterator with
                 expr = (fun self e ->
                     (match e.pexp_desc with
                      | Pexp_ident { txt = Longident.Lident x; _ } -> used := x :: !used
                      | _ -> ());
                     Ast_iterator.default_iterator.expr self e) } in
      List.iter (it.structure_item it) items;
      let defined = List.concat_map (fun (i : Parsetree.structure_item) -> match i.pstr_desc with
          | Pstr_value (_, vbs) -> List.filter_map (fun (vb : Parsetree.value_binding) -> match vb.pvb_pat.ppat_desc with
              | Ppat_var { txt; _ } -> Some txt | _ -> None) vbs
          | Pstr_type (_, tds) -> List.map (fun (td : Parsetree.type_declaration) -> td.ptype_name.txt) tds
          | _ -> []) items in
      (List.sort_uniq compare !used, defined)

(* The reference with what it borrows from earlier problems: the ocaml.org
   problems build on each other (coprime uses the previous problem's gcd).
   Only definitions the reference actually reaches are taken, transitively,
   so one broken phrase upstream cannot break this one. Verifier only. *)
let reference_with_context ~dir ~slug md =
  let own = reference md in
  let earlier = Sys.readdir dir |> Array.to_list |> List.filter (fun f ->
      Filename.check_suffix f ".md" && Filename.remove_extension f < slug) |> List.sort compare in
  let phrases = List.concat_map (fun f ->
      let src = reference (read_file (Filename.concat dir f)) in
      List.filter_map (fun ph ->
          let ph = String.trim ph in
          if ph = "" || ph = ";;" then None
          else let _, defs = uses_and_defines ph in if defs = [] then None else Some (ph, defs))
        (Str.split (Str.regexp ";;") src)) earlier in
  let own_defs = snd (uses_and_defines own) in
  let rec close needed acc =
    let fresh = List.filter (fun n -> not (List.mem n own_defs) && not (List.exists (fun (_, d) -> List.mem n d) acc)) needed in
    let found = List.filter_map (fun n ->
        (* the latest earlier definition of n *)
        List.fold_left (fun best (ph, d) -> if List.mem n d then Some (ph, d) else best) None phrases) fresh in
    let found = List.sort_uniq compare found in
    if found = [] then acc
    else close (List.concat_map (fun (ph, _) -> fst (uses_and_defines ph)) found) (found @ acc) in
  let deps = close (fst (uses_and_defines own)) [] in
  (* in the order they appeared *)
  let ordered = List.filter (fun p -> List.mem p deps) phrases in
  String.concat "\n" (List.map (fun (ph, _) -> ph ^ ";;") ordered) ^ "\n" ^ own

(* The context a problem inherits: every earlier Statement in its directory,
   read in order, Statements only. *)
let context_before ~dir ~slug =
  let earlier = Sys.readdir dir |> Array.to_list
                |> List.filter (fun f -> Filename.check_suffix f ".md" && Filename.remove_extension f < slug)
                |> List.sort compare in
  List.fold_left (fun ctx f ->
      let p = read ?context:ctx ~slug:(Filename.remove_extension f) (read_file (Filename.concat dir f)) in
      Some { p with targets = []; unread = [] }) None earlier
