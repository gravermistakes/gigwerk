(* The deductive half of the search: split a goal the bank cannot answer into
 * smaller goals it can, by running the components backwards.
 *
 * A goal is a type and the value wanted at each point, or nothing where any
 * value will do. A component with an inverse turns one goal into others:
 *
 *   - every output is the same constructor        -> one goal per argument
 *   - every output starts with what a term yields -> `term ^ rest`, solve rest
 *   - every output is as long as a known list      -> `List.map f l`, and f's
 *                                                     examples are the elements,
 *                                                     judged on REAL points
 *   - every output is a known list with some gone  -> `List.filter p l`
 *   - a string output                              -> the list of its chars
 *   - true exactly where a known test is true...   -> `a && b`, `a || b`
 *   - otherwise, a guard from the bank that splits the points, and a goal on
 *     each side
 *
 * The bank (Synth) supplies the leaves: every distinct small term. Deduction
 * never accepts a term on faith; a goal is met only by a term whose value at
 * each point it cares about is the one wanted. Every bound is a count. *)

open Types
open Synth

type goal = { gty : ty; outs : Value.t option array }

type st = {
  cfg : config;
  decls : decl list;
  examples : Spec.example list;
  mutable steps : int;                 (* deduction budget, a count *)
  banks : (string, search) Hashtbl.t;  (* per context *)
  bank_size : int;
  lambda_bank_size : int;
}

let step_limit = 6_000

exception Out_of_steps

let tick st =
  st.steps <- st.steps + 1;
  if st.steps > step_limit then raise Out_of_steps

let ctx_key (ctx : ctx) =
  String.concat ";" (List.map (fun (x, t) -> x ^ ":" ^ key t) ctx.vars)
  ^ "|" ^ String.concat "\n" (Array.to_list (Array.map (fun p ->
      String.concat "," (List.map (fun (x, v) -> x ^ "=" ^ (try Value.to_ocaml v with _ -> "?")) p)) ctx.points))

let search_for st ctx types size =
  let k = ctx_key ctx in
  match Hashtbl.find_opt st.banks k with
  | Some s -> s
  | None ->
      let s = build_search ~cfg:st.cfg ~decls:st.decls ~examples:st.examples ~ctx ~types size in
      Hashtbl.replace st.banks k s; s

let bank_for st ctx types size = (search_for st ctx types size).main

let meets (c : cand) g =
  let ok = ref true in
  Array.iteri (fun j o -> match o with
      | None -> ()
      | Some o -> (match c.vec.(j) with
          | Some v when Value.equal v o -> ()
          | _ -> ok := false)) g.outs;
  !ok

let cared g = List.filter (fun j -> g.outs.(j) <> None) (List.init (Array.length g.outs) Fun.id)

let lookup b g = List.find_opt (fun c -> meets c g) (terms_of b g.gty)

let take n l = List.filteri (fun i _ -> i < n) l

let first_some fs = List.fold_left (fun acc f -> match acc with Some _ -> acc | None -> f ()) None fs

let is_prefix p s = String.length p <= String.length s && String.sub s 0 (String.length p) = p

(* Argument types of a constructor at a goal type. *)
let ctor_arg_types decls gty c n =
  match repr gty, c with
  | TCon ("option", [ a ]), "Some" -> Some [ a ]
  | TCon ("result", [ a; _ ]), "Ok" -> Some [ a ]
  | TCon ("result", [ _; e ]), "Error" -> Some [ e ]
  | TCon (name, args), _ ->
      (match List.find_opt (fun d -> d.name = name) decls with
       | Some { kind = Variant ctors; params; _ } ->
           (match List.assoc_opt c ctors with
            | Some ts when List.length ts = n ->
                let sub = List.combine params args in
                let rec go t = match repr t with
                  | TVar v -> (match List.assoc_opt v sub with Some t -> t | None -> t)
                  | TCon (m, ts) -> TCon (m, List.map go ts)
                  | TTuple ts -> TTuple (List.map go ts)
                  | t -> t in
                Some (List.map go ts)
            | _ -> None)
       | _ -> None)
  | _ -> None

(* `t mod k = 0` with k solved from the data: the gcd of t over the points
   where the goal is true, provided no false point is a multiple of it. The
   constant is read off the examples, not supplied; also its negation. A leaf,
   like a bank lookup: it costs no depth. *)
let divisibility b g =
  match repr g.gty with
  | TCon ("bool", []) ->
      let cs = cared g in
      let bools = List.map (fun j -> g.outs.(j) = Some (Value.Bool true)) cs in
      let rec gcd a b = if b = 0 then abs a else gcd b (a mod b) in
      List.find_map (fun c ->
          let vals = List.map (fun j -> match c.vec.(j) with Some (Value.Int n) -> Some n | _ -> None) cs in
          if cs = [] || List.exists Option.is_none vals then None
          else
            let vals = List.map Option.get vals in
            let solve_for want =
              let pairs = List.combine vals bools in
              let ts = List.filter_map (fun (v, o) -> if o = want then Some v else None) pairs in
              let fs = List.filter_map (fun (v, o) -> if o <> want then Some v else None) pairs in
              let k = List.fold_left gcd 0 ts in
              if ts <> [] && fs <> [] && k > 1 && List.for_all (fun v -> v mod k <> 0) fs then Some k else None in
            let mk k op = Expr.Call (op, [ Expr.Call ("mod", [ c.expr; Expr.Lit (Value.Int k) ]); Expr.Lit (Value.Int 0) ]) in
            match solve_for true with
            | Some k -> Some (mk k "=")
            | None -> Option.map (fun k -> mk k "<>") (solve_for false))
        (take 20 (List.filter (fun c -> key c.ty = "int") (all_terms b)))
  | _ -> None

let rec solve st (ctx : ctx) (b : bank) (g : goal) depth : Expr.t option =
  match (match lookup b g with Some c -> Some c.expr | None -> divisibility b g) with
  | Some e -> Some e
  | None when depth <= 0 -> None
  | None ->
      tick st;
      let cs = cared g in
      if cs = [] then None
      else
        let outs = List.map (fun j -> Option.get g.outs.(j)) cs in
        first_some [
          (fun () -> by_constructor st ctx b g cs outs depth);
          (fun () -> by_string st ctx b g cs outs depth);
          (fun () -> by_list st ctx b g cs outs depth);
          (fun () -> by_bool st ctx b g cs outs depth);
          (fun () -> by_int st ctx b g cs outs depth);
          (fun () -> by_cond st ctx b g cs depth);
        ]

(* Same goal type, values given at some points. *)
and sub g f = { g with outs = Array.mapi (fun j o -> match o with None -> None | Some v -> f j v) g.outs }

and by_constructor st ctx b g cs outs depth =
  let with_args ty_args mk extract =
    let goals = List.mapi (fun i t ->
        { gty = t; outs = Array.map (function None -> None | Some v -> Some (List.nth (extract v) i)) g.outs })
        ty_args in
    let rec all acc = function
      | [] -> Some (mk (List.rev acc))
      | sg :: rest -> (match solve st ctx b sg (depth - 1) with
          | Some e -> all (e :: acc) rest | None -> None) in
    all [] goals
  in
  ignore cs;
  match repr g.gty, outs with
  | TTuple ts, _ when List.for_all (function Value.Tuple _ -> true | _ -> false) outs ->
      with_args ts (fun es -> Expr.Tuple es) (function Value.Tuple vs -> vs | _ -> [])
  | _, Value.Con (c, args) :: _
    when List.for_all (function Value.Con (c', a) -> c' = c && List.length a = List.length args | _ -> false) outs ->
      (match ctor_arg_types st.decls g.gty c (List.length args) with
       | Some [] -> Some (Expr.Con (c, []))
       | Some ts -> with_args ts (fun es -> Expr.Con (c, es)) (function Value.Con (_, a) -> a | _ -> [])
       | None -> None)
  | _, Value.Record fs :: _ when List.for_all (function Value.Record _ -> true | _ -> false) outs ->
      (match repr g.gty with
       | TCon (name, _) ->
           (match List.find_opt (fun d -> d.name = name) st.decls with
            | Some { kind = Record fields; _ } ->
                with_args (List.map snd fields)
                  (fun es -> Expr.Record (List.combine (List.map fst fields) es))
                  (function Value.Record fs -> List.map snd fs | _ -> [])
            | _ -> ignore fs; None)
       | _ -> None)
  | _ -> None

and by_string st ctx b g cs outs depth =
  match repr g.gty with
  | TCon ("string", []) ->
      let strs = List.map (function Value.String s -> s | _ -> "") outs in
      first_some [
        (* term ^ rest *)
        (fun () ->
           let prefixes = List.filter (fun c ->
               let nonempty = ref false in
               List.for_all2 (fun j s -> match c.vec.(j) with
                   | Some (Value.String p) -> if p <> "" then nonempty := true; is_prefix p s
                   | _ -> false) cs strs && !nonempty) (terms_of b t_string) in
           List.fold_left (fun acc c -> match acc with
               | Some _ -> acc
               | None ->
                   let rest = sub g (fun j v -> match v, c.vec.(j) with
                       | Value.String s, Some (Value.String p) ->
                           Some (Value.String (String.sub s (String.length p) (String.length s - String.length p)))
                       | _ -> None) in
                   Option.map (fun e -> Expr.Call ("^", [ c.expr; e ])) (solve st ctx b rest (depth - 1)))
             None (take 12 prefixes));
        (* String.concat sep pieces, for a separator that occurs *)
        (fun () ->
           let seps = List.filter (fun sep -> List.exists (fun s -> List.length (split_on s sep) > 1) strs)
               [ " "; ", "; "\n"; "-"; ","; "; " ] in
           first_some (List.map (fun sep -> fun () ->
               let lg = sub g (fun _ v -> match v with
                   | Value.String s -> Some (Value.List (List.map (fun x -> Value.String x) (split_on s sep)))
                   | _ -> None) in
               let lg = { lg with gty = t_list t_string } in
               Option.map (fun e -> Expr.Call ("String.concat", [ Expr.Lit (Value.String sep); e ]))
                 (solve st ctx b lg (depth - 1))) seps));
        (* the string as its characters *)
        (fun () ->
           let lg = { gty = t_list t_char; outs = Array.map (function
               | Some (Value.String s) -> Some (Value.List (List.init (String.length s) (fun i -> Value.Char s.[i])))
               | _ -> None) g.outs } in
           Option.map (fun e -> Expr.Call ("implode", [ e ])) (solve st ctx b lg (depth - 1)));
      ]
  | _ -> None

and lambda_goal st ctx params (rows : (int * Value.t list * Value.t) list) out_ty depth =
  (* rows: outer point, parameter values, wanted output. Points that agree on
     everything are one point; points that agree on the inputs but not the
     output make the goal impossible. *)
  let names = List.mapi (fun i _ -> fresh_name ctx ("p" ^ string_of_int i)) params in
  let tbl = Hashtbl.create 16 in
  let rows = List.filter_map (fun (j, ps, o) ->
      let env = List.combine names ps @ ctx.points.(j) in
      let k = String.concat "," (List.map (fun (x, v) -> x ^ "=" ^ (try Value.to_ocaml v with _ -> "?")) env) in
      match Hashtbl.find_opt tbl k with
      | Some o' -> if Value.equal o o' then None else (Hashtbl.replace tbl k (Value.Con ("#conflict", [])); None)
      | None -> Hashtbl.replace tbl k o; Some (k, env)) rows in
  if Hashtbl.fold (fun _ v acc -> acc || (match v with Value.Con ("#conflict", _) -> true | _ -> false)) tbl false
  then None
  else if rows = [] || List.length rows > 400 then None
  else
    let points = Array.of_list (List.map snd rows) in
    let outs = Array.of_list (List.map (fun (k, _) -> Some (Hashtbl.find tbl k)) rows) in
    let ctx' = { vars = List.combine names params @ ctx.vars; points } in
    let b' = bank_for st ctx' [ out_ty ] st.lambda_bank_size in
    Option.map (fun body -> Expr.Lam (names, body))
      (solve st ctx' b' { gty = out_ty; outs } (depth - 1))

and by_list st ctx b g cs outs depth =
  match repr g.gty with
  | TCon ("list", [ te ]) ->
      let lists = List.map (function Value.List l -> l | _ -> []) outs in
      let list_terms = List.filter (fun c -> match repr c.ty with TCon ("list", [ _ ]) -> true | _ -> false)
          (all_terms b) in
      first_some [
        (* List.map f l *)
        (fun () ->
           let cands = List.filter (fun c ->
               List.for_all2 (fun j l -> match c.vec.(j) with
                   | Some (Value.List l') -> List.length l' = List.length l
                   | _ -> false) cs lists
               && List.exists (fun l -> l <> []) lists) list_terms in
           first_some (List.map (fun c -> fun () ->
               match repr c.ty with
               | TCon ("list", [ ta ]) ->
                   let rows = List.concat (List.map2 (fun j l -> match c.vec.(j) with
                       | Some (Value.List l') -> List.map2 (fun x o -> (j, [ x ], o)) l' l
                       | _ -> []) cs lists) in
                   (* not the identity, which the bank already had *)
                   if key ta = key te && List.for_all (fun (_, xs, o) -> Value.equal (List.hd xs) o) rows then None
                   else
                     Option.map (fun f -> Expr.Call ("List.map", [ f; c.expr ]))
                       (lambda_goal st ctx [ ta ] rows te depth)
               | _ -> None) (take 6 cands)));
        (* List.filter p l *)
        (fun () ->
           let subseq small big =
             let rec go acc s bg = match s, bg with
               | [], rest -> Some (List.rev acc @ List.map (fun x -> (x, false)) rest)
               | _, [] -> None
               | x :: s', y :: bg' ->
                   if Value.equal x y then go ((y, true) :: acc) s' bg' else go ((y, false) :: acc) s bg' in
             go [] small big in
           let cands = List.filter (fun c -> key c.ty = key g.gty
               && List.for_all2 (fun j l -> match c.vec.(j) with
                   | Some (Value.List l') -> subseq l l' <> None | _ -> false) cs lists
               && List.exists2 (fun j l -> match c.vec.(j) with
                   | Some (Value.List l') -> List.length l' > List.length l | _ -> false) cs lists) list_terms in
           first_some (List.map (fun c -> fun () ->
               let rows = List.concat (List.map2 (fun j l -> match c.vec.(j) with
                   | Some (Value.List l') ->
                       (match subseq l l' with
                        | Some flags -> List.map (fun (x, keep) -> (j, [ x ], Value.Bool keep)) flags
                        | None -> [])
                   | _ -> []) cs lists) in
               Option.map (fun p -> Expr.Call ("List.filter", [ p; c.expr ]))
                 (lambda_goal st ctx [ te ] rows t_bool depth)) (take 6 cands)));
        (* List.init n f, n the length *)
        (fun () ->
           let ints = List.filter (fun c -> key c.ty = "int"
               && List.for_all2 (fun j l -> c.vec.(j) = Some (Value.Int (List.length l))) cs lists) (all_terms b) in
           first_some (List.map (fun c -> fun () ->
               let rows = List.concat (List.map2 (fun j l ->
                   List.mapi (fun i o -> (j, [ Value.Int i ], o)) l) cs lists) in
               Option.map (fun f -> Expr.Call ("List.init", [ c.expr; f ]))
                 (lambda_goal st ctx [ t_int ] rows te depth)) (take 3 ints)));
        (* List.rev l *)
        (fun () ->
           if List.for_all (fun l -> List.rev l = l) lists then None
           else
             let rg = sub g (fun _ v -> match v with Value.List l -> Some (Value.List (List.rev l)) | _ -> None) in
             match lookup b rg with
             | Some c -> Some (Expr.Call ("List.rev", [ c.expr ]))
             | None -> None);
        (* x :: rest *)
        (fun () ->
           if List.for_all (fun l -> l <> []) lists then
             let hg = { gty = te; outs = Array.map (function Some (Value.List (h :: _)) -> Some h | _ -> None) g.outs } in
             let tg = sub g (fun _ v -> match v with Value.List (_ :: t) -> Some (Value.List t) | _ -> None) in
             match solve st ctx b hg (depth - 1) with
             | None -> None
             | Some h -> Option.map (fun t -> Expr.Call ("::", [ h; t ])) (solve st ctx b tg (depth - 1))
           else None);
      ]
  | _ -> None

and by_bool st ctx b g cs outs depth =
  match repr g.gty with
  | TCon ("bool", []) ->
      let bools = List.map (function Value.Bool v -> v | _ -> false) outs in
      let tests = List.filter (fun c -> key c.ty = "bool") (all_terms b) in
      let holds c j = c.vec.(j) = Some (Value.Bool true) in
      let defined c j = match c.vec.(j) with Some (Value.Bool _) -> true | _ -> false in
      first_some [
        (* a && b: a true wherever the goal is, false somewhere it is not *)
        (fun () ->
           let cands = List.filter (fun c ->
               List.for_all2 (fun j v -> defined c j && (not v || holds c j)) cs bools
               && List.exists2 (fun j v -> not v && not (holds c j)) cs bools) tests in
           first_some (List.map (fun c -> fun () ->
               let rest = sub g (fun j v -> if holds c j then Some v else None) in
               Option.map (fun e -> Expr.Call ("&&", [ c.expr; e ])) (solve st ctx b rest (depth - 1)))
               (take 8 cands)));
        (* a || b: a false wherever the goal is, true somewhere it is *)
        (fun () ->
           let cands = List.filter (fun c ->
               List.for_all2 (fun j v -> defined c j && (v || not (holds c j))) cs bools
               && List.exists2 (fun j v -> v && holds c j) cs bools) tests in
           first_some (List.map (fun c -> fun () ->
               let rest = sub g (fun j v -> if holds c j then None else Some v) in
               Option.map (fun e -> Expr.Call ("||", [ c.expr; e ])) (solve st ctx b rest (depth - 1)))
               (take 8 cands)));
      ]
  | _ -> None

and by_int st ctx b g cs outs _depth =
  match repr g.gty with
  | TCon ("int", []) ->
      let ns = List.map (function Value.Int n -> n | _ -> min_int) outs in
      let list_terms = List.filter (fun c -> match repr c.ty with TCon ("list", [ _ ]) -> true | _ -> false)
          (all_terms b) in
      (* the functions a lambda bank holds for one parameter of type t *)
      let memo = Hashtbl.create 8 in
      let lambdas t rty =
        let mk = key t ^ "->" ^ key rty in
        match Hashtbl.find_opt memo mk with Some l -> l | None ->
        let srch = search_for st ctx [] st.bank_size in
        let lb = lambdas_for srch b [ t ] in
        List.concat_map (fun n -> List.concat_map (fun (lt, cands) ->
            if key lt = key rty then List.map (fun c -> (lb, c)) cands else [])
            (try lambda_level srch lb n ~lambda_depth:1 with Exhausted -> []))
          (List.init st.lambda_bank_size (fun i -> i + 1))
        |> fun l -> Hashtbl.replace memo mk l; l in
      let run_lam (lb, lc) j v =
        Eval.run ~budget:st.cfg.fuel ((fst (List.hd lb.params), v) :: ctx.points.(j)) lc.expr in
      let elements c j = match c.vec.(j) with Some (Value.List l) -> Some l | _ -> None in
      first_some [
        (* List.length (List.filter p l) *)
        (fun () ->
           let cands = List.filter (fun c -> List.for_all2 (fun j n -> match elements c j with
               | Some l -> n >= 0 && n <= List.length l | None -> false) cs ns) list_terms in
           first_some (List.map (fun c -> fun () ->
               match repr c.ty with
               | TCon ("list", [ te ]) ->
                   List.find_map (fun (lb, lc) ->
                       let ok = List.for_all2 (fun j n -> match elements c j with
                           | Some l ->
                               let k = List.fold_left (fun k v -> match run_lam (lb, lc) j v with
                                   | Some (Value.Bool true) -> k + 1 | Some (Value.Bool false) -> k | _ -> -1000) 0 l in
                               k = n
                           | None -> false) cs ns in
                       if ok then Some (Expr.Call ("List.length", [ Expr.Call ("List.filter",
                                                                     [ Expr.Lam (List.map fst lb.params, lc.expr); c.expr ]) ]))
                       else None) (lambdas te t_bool)
               | _ -> None) (take 40 cands)));
        (* sum over a list of a function of each element *)
        (fun () ->
           first_some (List.map (fun c -> fun () ->
               match repr c.ty with
               | TCon ("list", [ te ]) ->
                   List.find_map (fun (lb, lc) ->
                       let ok = List.for_all2 (fun j n -> match elements c j with
                           | Some l ->
                               (try List.fold_left (fun acc v -> match run_lam (lb, lc) j v with
                                   | Some (Value.Int k) -> acc + k | _ -> raise Exit) 0 l = n
                                with Exit -> false)
                           | None -> false) cs ns in
                       if ok then
                         let f = Expr.Lam (List.map fst lb.params, lc.expr) in
                         Some (Expr.Call ("List.fold_left", [
                             Expr.Lam ([ "acc"; "e" ], Expr.Call ("+", [ Expr.Var "acc"; Expr.App (f, [ Expr.Var "e" ]) ]));
                             Expr.Lit (Value.Int 0); c.expr ]))
                       else None) (lambdas te t_int)
               | _ -> None) (take 40 list_terms)));
      ]
  | _ -> None

and by_cond st ctx b g cs depth =
  if List.length cs < 2 then None
  else
    let tests = List.filter (fun c -> key c.ty = "bool"
        && List.for_all (fun j -> match c.vec.(j) with Some (Value.Bool _) -> true | _ -> false) cs
        && List.exists (fun j -> c.vec.(j) = Some (Value.Bool true)) cs
        && List.exists (fun j -> c.vec.(j) = Some (Value.Bool false)) cs) (all_terms b) in
    (* A guard that splits the points exactly where the outputs change shape
       (Ok from Error, Some from None, one constructor from another) is the
       natural first question to ask; only after those, the rest by size. *)
    let shape j = match g.outs.(j) with
      | Some (Value.Con (c, _)) -> c
      | Some (Value.List []) -> "[]" | Some (Value.List _) -> "::"
      | Some (Value.Bool v) -> string_of_bool v
      | _ -> "" in
    let shapes = List.sort_uniq compare (List.map shape cs) in
    let separates c =
      List.length shapes = 2
      && List.for_all (fun j -> List.for_all (fun k ->
          (shape j = shape k) = (c.vec.(j) = c.vec.(k))) cs) cs in
    let tests = List.filter separates tests @ List.filter (fun c -> not (separates c)) tests in
    first_some (List.map (fun c -> fun () ->
        let yes = sub g (fun j v -> if c.vec.(j) = Some (Value.Bool true) then Some v else None) in
        let no = sub g (fun j v -> if c.vec.(j) = Some (Value.Bool false) then Some v else None) in
        (* a guard is a question the examples may answer by accident, so a
           conditional costs two levels where a decomposition costs one *)
        match solve st ctx b yes (depth - 2) with
        | None -> None
        | Some a -> Option.map (fun e -> Expr.If (c.expr, a, e)) (solve st ctx b no (depth - 2)))
        (take 10 tests))

type result = Solved of Expr.t * int | Gave_up of string

let solve_top ?(cfg = default) ?(bank_size = 6) ?(lambda_bank_size = 5) ?(depth = 4)
    ~decls ~params ~out_ty (examples : Spec.example list) =
  Synth.total := 0;
  Synth.pending := [];
  let st = { cfg; decls; examples; steps = 0; banks = Hashtbl.create 8; bank_size; lambda_bank_size } in
  let points = Array.of_list (List.map (fun ex -> List.combine (List.map fst params) ex.Spec.args) examples) in
  let ctx = { vars = params; points } in
  let b = bank_for st ctx [ out_ty ] bank_size in
  let g = { gty = out_ty; outs = Array.of_list (List.map (fun ex -> Some ex.Spec.out) examples) } in
  let rec deepen d =
    if d > depth then Gave_up (Printf.sprintf "no derivation within depth %d (%d steps)" depth st.steps)
    else match solve st ctx b g d with
      | Some e -> Solved (e, st.steps)
      | None -> deepen (d + 1)
  in
  try deepen 0 with
  | Out_of_steps -> Gave_up (Printf.sprintf "deduction bound reached: %d steps" st.steps)
  | Exhausted -> Gave_up (Printf.sprintf "term bound reached: %d terms kept" !Synth.total)
