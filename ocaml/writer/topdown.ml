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

(* outs: the value wanted at each point, or None for any. defined: points
   with no particular value wanted, where the term must still have one; these
   are the edge inputs (an empty list, zero) the examples never showed, and
   they make a total program win over one that crashes there. *)
type goal = { gty : ty; outs : Value.t option array; defined : bool array }

let restrict g keep = { g with defined = Array.mapi (fun j d -> d && keep j) g.defined }
let nodef n = Array.make n false

type st = {
  cfg : config;
  decls : decl list;
  examples : Spec.example list;
  mutable steps : int;                 (* deduction budget, a count *)
  banks : (string, search) Hashtbl.t;  (* per context *)
  bank_size : int;
  lambda_bank_size : int;
  avoid_in_guards : string list;       (* variables a guard should not ask about first *)
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
  Array.iteri (fun j d -> if d && g.outs.(j) = None && c.vec.(j) = None then ok := false) g.defined;
  !ok

let cared g = List.filter (fun j -> g.outs.(j) <> None) (List.init (Array.length g.outs) Fun.id)

(* Solutions are lazy sequences: a strategy yields its answers one at a time,
   smallest first within it, so the top can turn one down (a parameter left
   unused) and draw the next without the search having been run twice. *)
type sols = Expr.t Seq.t

let lazy_seq (f : unit -> sols) : sols = fun () -> f () ()
let alts (fs : (unit -> sols) list) : sols = Seq.flat_map lazy_seq (List.to_seq fs)
let of_opt = function Some e -> Seq.return e | None -> Seq.empty
let take_seq n (s : 'a Seq.t) : 'a Seq.t = Seq.take n s
let alternatives = 3      (* answers kept per subgoal *)

let lookup b g = List.to_seq (List.filter (fun c -> meets c g) (terms_of b g.gty))
                 |> Seq.map (fun c -> c.expr) |> take_seq alternatives

let take n l = List.filteri (fun i _ -> i < n) l

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
        (* only numbers the part is given: `length mod 12 = 0` is a fit, not a rule *)
        (take 20 (List.filter (fun c -> key c.ty = "int" && (match c.expr with Expr.Var _ -> true | _ -> false))
                    (all_terms b)))
  | _ -> None

(* Every combination of one answer per goal, in order. *)
let rec product (seqs : sols list) : Expr.t list Seq.t =
  match seqs with
  | [] -> Seq.return []
  | s :: rest ->
      let rest = Seq.memoize (product rest) in
      Seq.flat_map (fun e -> Seq.map (fun es -> e :: es) rest) s

let rec solve st (ctx : ctx) (b : bank) (g : goal) depth : sols =
  let leaves = Seq.append (lookup b g) (lazy_seq (fun () -> of_opt (divisibility b g))) in
  if depth <= 0 then leaves
  else
    Seq.append leaves (lazy_seq (fun () ->
        tick st;
        let cs = cared g in
        if cs = [] then Seq.empty
        else
          let outs = List.map (fun j -> Option.get g.outs.(j)) cs in
          alts [
            (fun () -> by_constructor st ctx b g cs outs depth);
            (fun () -> by_string st ctx b g cs outs depth);
            (fun () -> by_list st ctx b g cs outs depth);
            (fun () -> by_bool st ctx b g cs outs depth);
            (fun () -> by_int st ctx b g cs outs depth);
            (fun () -> by_cond st ctx b g cs depth);
          ]))

and sub_solve st ctx b g depth = Seq.memoize (take_seq alternatives (solve st ctx b g depth))

(* Same goal type, values given at some points. *)
and sub g f = { g with outs = Array.mapi (fun j o -> match o with None -> None | Some v -> f j v) g.outs }

and by_constructor st ctx b g cs outs depth : sols =
  let with_args ty_args mk extract =
    let goals = List.mapi (fun i t ->
        { gty = t; outs = Array.map (function None -> None | Some v -> Some (List.nth (extract v) i)) g.outs;
          defined = g.defined })
        ty_args in
    Seq.map mk (product (List.map (fun sg -> sub_solve st ctx b sg (depth - 1)) goals))
  in
  ignore cs;
  match repr g.gty, outs with
  | TTuple ts, _ when List.for_all (function Value.Tuple _ -> true | _ -> false) outs ->
      with_args ts (fun es -> Expr.Tuple es) (function Value.Tuple vs -> vs | _ -> [])
  | _, Value.Con (c, args) :: _
    when List.for_all (function Value.Con (c', a) -> c' = c && List.length a = List.length args | _ -> false) outs ->
      (match ctor_arg_types st.decls g.gty c (List.length args) with
       | Some [] -> Seq.return (Expr.Con (c, []))
       | Some ts -> with_args ts (fun es -> Expr.Con (c, es)) (function Value.Con (_, a) -> a | _ -> [])
       | None -> Seq.empty)
  | _, Value.Record _ :: _ when List.for_all (function Value.Record _ -> true | _ -> false) outs ->
      (match repr g.gty with
       | TCon (name, _) ->
           (match List.find_opt (fun d -> d.name = name) st.decls with
            | Some { kind = Record fields; _ } ->
                with_args (List.map snd fields)
                  (fun es -> Expr.Record (List.combine (List.map fst fields) es))
                  (function Value.Record fs -> List.map snd fs | _ -> [])
            | _ -> Seq.empty)
       | _ -> Seq.empty)
  | _ -> Seq.empty

and by_string st ctx b g cs outs depth : sols =
  match repr g.gty with
  | TCon ("string", []) ->
      let strs = List.map (function Value.String s -> s | _ -> "") outs in
      alts [
        (* term ^ rest *)
        (fun () ->
           let prefixes = List.filter (fun c ->
               let nonempty = ref false in
               List.for_all2 (fun j s -> match c.vec.(j) with
                   | Some (Value.String p) -> if p <> "" then nonempty := true; is_prefix p s
                   | _ -> false) cs strs && !nonempty) (terms_of b t_string) in
           Seq.flat_map (fun c ->
               let rest = sub g (fun j v -> match v, c.vec.(j) with
                   | Value.String s, Some (Value.String p) ->
                       Some (Value.String (String.sub s (String.length p) (String.length s - String.length p)))
                   | _ -> None) in
               Seq.map (fun e -> Expr.Call ("^", [ c.expr; e ])) (sub_solve st ctx b rest (depth - 1)))
             (List.to_seq (take 12 prefixes)));
        (* Optional fragments in a fixed order: every output is some of the
           data's string fragments, concatenated in one order, or (at other
           points) something else. Each fragment's presence is a boolean
           goal; the other points, if any, are the goal for when none is
           present:  let s = (if g1 then F1 else "") ^ ... in
                     if s = "" then other else s *)
        (fun () ->
           let index f s =
             let n = String.length f and h = String.length s in
             let rec find i = if i + n > h then None else if String.sub s i n = f then Some i else find (i + 1) in
             find 0 in
           (* a fragment recurs: one example's whole answer is not vocabulary *)
           let frags = List.filter_map (fun c -> match c.expr with
               | Expr.Lit (Value.String f) when String.length f >= 2
                   && List.length (List.filter (fun s -> index f s <> None) strs) >= 2 -> Some f
               | _ -> None) (terms_of b t_string) in
           let frags = List.sort_uniq compare frags in
           (* the order the outputs themselves put fragments in: where two
              occur together, that order; otherwise first appearance *)
           let first f = let rec go i = function [] -> max_int | s :: r -> if index f s <> None then i else go (i + 1) r in go 0 strs in
           let before a b =
             match List.find_map (fun s -> match index a s, index b s with
                 | Some i, Some j -> Some (compare i j) | _ -> None) strs with
             | Some k -> k
             | None -> compare (first a) (first b) in
           let frags = List.stable_sort before frags in
           let rec parse s fs = (* which fragments, in order, make s *)
             if s = "" then Some []
             else match fs with
               | [] -> None
               | f :: rest ->
                   let n = String.length f in
                   (if String.length s >= n && String.sub s 0 n = f then
                      Option.map (fun l -> f :: l) (parse (String.sub s n (String.length s - n)) rest)
                    else None)
                   |> (function Some l -> Some l | None -> parse s rest) in
           if List.length frags < 2 then Seq.empty
           else
             let parsed = List.map (fun s -> parse s frags) strs in
             let others = List.filter_map (fun (j, p) -> if p = None then Some j else None) (List.combine cs parsed) in
             let present = List.filter_map (fun (j, p) -> match p with Some l -> Some (j, l) | None -> None) (List.combine cs parsed) in
             if List.length present < 2 then Seq.empty
             else
               let bool_goal f = { gty = t_bool;
                                   outs = Array.mapi (fun j _ -> match List.assoc_opt j present with
                                       | Some l -> Some (Value.Bool (List.mem f l))
                                       | None -> if List.mem j others then Some (Value.Bool false) else None) g.outs;
                                   defined = g.defined } in
               let used = List.filter (fun f -> List.exists (fun (_, l) -> List.mem f l) present) frags in
               let guards = List.map (fun f -> sub_solve st ctx b (bool_goal f) (depth - 1)) used in
               let concat gs = List.fold_left (fun acc (f, g) ->
                   let piece = Expr.If (g, Expr.Lit (Value.String f), Expr.Lit (Value.String "")) in
                   match acc with None -> Some piece | Some a -> Some (Expr.Call ("^", [ a; piece ]))) None
                   (List.combine used gs) |> Option.get in
               let og = { g with outs = Array.mapi (fun j o -> if List.mem j others then o else None) g.outs;
                                 defined = Array.map (fun _ -> false) g.defined } in
               let other_sols = if others = [] then Seq.empty else sub_solve st ctx b og (depth - 1) in
               Seq.flat_map (fun gs ->
                   let body = concat gs in
                   if others = [] then Seq.return body
                   else
                     Seq.map (fun e ->
                         Expr.Let (false, "s", body,
                                   Expr.If (Expr.Call ("=", [ Expr.Var "s"; Expr.Lit (Value.String "") ]), e, Expr.Var "s")))
                       other_sols)
                 (product guards));
        (* String.concat sep pieces, for a separator that occurs *)
        (fun () ->
           let seps = List.filter (fun sep -> List.exists (fun s -> List.length (split_on s sep) > 1) strs)
               [ " "; ", "; "\n"; "-"; ","; "; " ] in
           Seq.flat_map (fun sep ->
               let lg = sub g (fun _ v -> match v with
                   | Value.String s -> Some (Value.List (List.map (fun x -> Value.String x) (split_on s sep)))
                   | _ -> None) in
               let lg = { lg with gty = t_list t_string } in
               Seq.map (fun e -> Expr.Call ("String.concat", [ Expr.Lit (Value.String sep); e ]))
                 (sub_solve st ctx b lg (depth - 1))) (List.to_seq seps));
        (* the string as its characters *)
        (fun () ->
           let lg = { gty = t_list t_char; outs = Array.map (function
               | Some (Value.String s) -> Some (Value.List (List.init (String.length s) (fun i -> Value.Char s.[i])))
               | _ -> None) g.outs; defined = g.defined } in
           Seq.map (fun e -> Expr.Call ("implode", [ e ])) (sub_solve st ctx b lg (depth - 1)));
      ]
  | _ -> Seq.empty

and lambda_goal st ctx params (rows : (int * Value.t list * Value.t) list) out_ty depth : sols =
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
  then Seq.empty
  else if rows = [] || List.length rows > 400 then Seq.empty
  else
    let points = Array.of_list (List.map snd rows) in
    let outs = Array.of_list (List.map (fun (k, _) -> Some (Hashtbl.find tbl k)) rows) in
    let ctx' = { vars = List.combine names params @ ctx.vars; points } in
    let b' = bank_for st ctx' [ out_ty ] st.lambda_bank_size in
    Seq.map (fun body -> Expr.Lam (names, body))
      (sub_solve st ctx' b' { gty = out_ty; outs; defined = nodef (Array.length outs) } (depth - 1))

and by_list st ctx b g cs outs depth : sols =
  match repr g.gty with
  | TCon ("list", [ te ]) ->
      let lists = List.map (function Value.List l -> l | _ -> []) outs in
      let list_terms = List.filter (fun c -> match repr c.ty with TCon ("list", [ _ ]) -> true | _ -> false)
          (all_terms b) in
      alts [
        (* List.map f l *)
        (fun () ->
           let cands = List.filter (fun c ->
               List.for_all2 (fun j l -> match c.vec.(j) with
                   | Some (Value.List l') -> List.length l' = List.length l
                   | _ -> false) cs lists
               && List.exists (fun l -> l <> []) lists) list_terms in
           Seq.flat_map (fun c ->
               match repr c.ty with
               | TCon ("list", [ ta ]) ->
                   let rows = List.concat (List.map2 (fun j l -> match c.vec.(j) with
                       | Some (Value.List l') -> List.map2 (fun x o -> (j, [ x ], o)) l' l
                       | _ -> []) cs lists) in
                   (* not the identity, which the bank already had *)
                   if key ta = key te && List.for_all (fun (_, xs, o) -> Value.equal (List.hd xs) o) rows then Seq.empty
                   else
                     Seq.map (fun f -> Expr.Call ("List.map", [ f; c.expr ]))
                       (lambda_goal st ctx [ ta ] rows te depth)
               | _ -> Seq.empty) (List.to_seq (take 6 cands)));
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
           Seq.flat_map (fun c ->
               let rows = List.concat (List.map2 (fun j l -> match c.vec.(j) with
                   | Some (Value.List l') ->
                       (match subseq l l' with
                        | Some flags -> List.map (fun (x, keep) -> (j, [ x ], Value.Bool keep)) flags
                        | None -> [])
                   | _ -> []) cs lists) in
               Seq.map (fun p -> Expr.Call ("List.filter", [ p; c.expr ]))
                 (lambda_goal st ctx [ te ] rows t_bool depth)) (List.to_seq (take 6 cands)));
        (* List.concat_map f l, when every element of l accounts for an equal
           share of the output: the shares are f's examples *)
        (fun () ->
           let cands = List.filter (fun c ->
               List.for_all2 (fun j l -> match c.vec.(j) with
                   | Some (Value.List l') ->
                       (l' = [] && l = []) || (l' <> [] && List.length l mod List.length l' = 0)
                   | _ -> false) cs lists
               && List.exists2 (fun j l -> match c.vec.(j) with
                   | Some (Value.List l') -> l' <> [] && List.length l <> List.length l'
                   | _ -> false) cs lists) list_terms in
           Seq.flat_map (fun c ->
               match repr c.ty with
               | TCon ("list", [ ta ]) ->
                   let rows = List.concat (List.map2 (fun j l -> match c.vec.(j) with
                       | Some (Value.List l') when l' <> [] ->
                           let k = List.length l / List.length l' in
                           List.mapi (fun i x ->
                               (j, [ x ], Value.List (List.filteri (fun m _ -> m >= i * k && m < (i + 1) * k) l))) l'
                       | _ -> []) cs lists) in
                   Seq.map (fun f -> Expr.Call ("List.concat_map", [ f; c.expr ]))
                     (lambda_goal st ctx [ ta ] rows g.gty depth)
               | _ -> Seq.empty) (List.to_seq (take 6 cands)));
        (* List.init n f, n the length *)
        (fun () ->
           let ints = List.filter (fun c -> key c.ty = "int"
               && List.for_all2 (fun j l -> c.vec.(j) = Some (Value.Int (List.length l))) cs lists) (all_terms b) in
           Seq.flat_map (fun c ->
               let rows = List.concat (List.map2 (fun j l ->
                   List.mapi (fun i o -> (j, [ Value.Int i ], o)) l) cs lists) in
               Seq.map (fun f -> Expr.Call ("List.init", [ c.expr; f ]))
                 (lambda_goal st ctx [ t_int ] rows te depth)) (List.to_seq (take 3 ints)));
        (* List.rev l *)
        (fun () ->
           if List.for_all (fun l -> List.rev l = l) lists then Seq.empty
           else
             let rg = sub g (fun _ v -> match v with Value.List l -> Some (Value.List (List.rev l)) | _ -> None) in
             Seq.map (fun e -> Expr.Call ("List.rev", [ e ])) (lookup b rg));
        (* x :: rest *)
        (fun () ->
           if List.for_all (fun l -> l <> []) lists then
             let hg = { gty = te; outs = Array.map (function Some (Value.List (h :: _)) -> Some h | _ -> None) g.outs;
                        defined = g.defined } in
             let tg = sub g (fun _ v -> match v with Value.List (_ :: t) -> Some (Value.List t) | _ -> None) in
             Seq.map (function [ h; t ] -> Expr.Call ("::", [ h; t ]) | _ -> assert false)
               (product [ sub_solve st ctx b hg (depth - 1); sub_solve st ctx b tg (depth - 1) ])
           else Seq.empty);
      ]
  | _ -> Seq.empty

and by_bool st ctx b g cs outs depth : sols =
  match repr g.gty with
  | TCon ("bool", []) ->
      let bools = List.map (function Value.Bool v -> v | _ -> false) outs in
      let tests = List.filter (fun c -> key c.ty = "bool") (all_terms b) in
      let holds c j = c.vec.(j) = Some (Value.Bool true) in
      let defined c j = match c.vec.(j) with Some (Value.Bool _) -> true | _ -> false in
      alts [
        (* a && b: a true wherever the goal is, false somewhere it is not *)
        (fun () ->
           let cands = List.filter (fun c ->
               List.for_all2 (fun j v -> defined c j && (not v || holds c j)) cs bools
               && List.exists2 (fun j v -> not v && not (holds c j)) cs bools) tests in
           Seq.flat_map (fun c ->
               let rest = restrict (sub g (fun j v -> if holds c j then Some v else None)) (holds c) in
               Seq.map (fun e -> Expr.Call ("&&", [ c.expr; e ])) (sub_solve st ctx b rest (depth - 1)))
             (List.to_seq (take 8 cands)));
        (* a || b: a false wherever the goal is, true somewhere it is *)
        (fun () ->
           let cands = List.filter (fun c ->
               List.for_all2 (fun j v -> defined c j && (v || not (holds c j))) cs bools
               && List.exists2 (fun j v -> v && holds c j) cs bools) tests in
           Seq.flat_map (fun c ->
               let rest = restrict (sub g (fun j v -> if holds c j then None else Some v)) (fun j -> not (holds c j)) in
               Seq.map (fun e -> Expr.Call ("||", [ c.expr; e ])) (sub_solve st ctx b rest (depth - 1)))
             (List.to_seq (take 8 cands)));
      ]
  | _ -> Seq.empty

and by_int st ctx b g cs outs depth : sols =
  match repr g.gty with
  | TCon ("int", []) ->
      let ns = List.map (function Value.Int n -> n | _ -> min_int) outs in
      let small_ints = List.filteri (fun i _ -> i < 15)
          (List.filter (fun c -> key c.ty = "int" && not (closed c.expr)
                                 && List.for_all (fun j -> c.vec.(j) <> None) cs) (all_terms b)) in
      let ival c j = match c.vec.(j) with Some (Value.Int n) -> n | _ -> 0 in
      let isqrt n = if n < 0 then None else
          let r = int_of_float (Float.sqrt (float_of_int n)) in
          List.find_opt (fun k -> k >= 0 && k * k = n) [ r - 1; r; r + 1 ] in
      let arithmetic = [
        (* e * e, when every output is a perfect square *)
        (fun () ->
           if List.exists (fun n -> n > 1) ns && List.for_all (fun n -> isqrt n <> None) ns then
             let rg = sub g (fun _ v -> match v with
                 | Value.Int n -> Option.map (fun r -> Value.Int r) (isqrt n) | _ -> None) in
             Seq.map (fun e -> Expr.Call ("*", [ e; e ])) (sub_solve st ctx b rg (depth - 1))
           else Seq.empty);
        (* a * rest, a dividing every output *)
        (fun () ->
           Seq.flat_map (fun a ->
               if List.for_all2 (fun j n -> let k = ival a j in k <> 0 && n mod k = 0) cs ns
               && List.exists (fun j -> abs (ival a j) > 1) cs then
                 let rg = sub g (fun j v -> match v with Value.Int n -> Some (Value.Int (n / ival a j)) | _ -> None) in
                 Seq.map (fun e -> Expr.Call ("*", [ a.expr; e ])) (sub_solve st ctx b rg (depth - 1))
               else Seq.empty) (List.to_seq small_ints));
        (* a + rest *)
        (fun () ->
           Seq.flat_map (fun a ->
               let rg = sub g (fun j v -> match v with Value.Int n -> Some (Value.Int (n - ival a j)) | _ -> None) in
               Seq.map (fun e -> Expr.Call ("+", [ a.expr; e ])) (sub_solve st ctx b rg (depth - 1)))
             (List.to_seq small_ints));
      ] in
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
      [
        (* List.length (List.filter p l) *)
        (fun () ->
           let cands = List.filter (fun c -> List.for_all2 (fun j n -> match elements c j with
               | Some l -> n >= 0 && n <= List.length l | None -> false) cs ns) list_terms in
           Seq.flat_map (fun c ->
               match repr c.ty with
               | TCon ("list", [ te ]) ->
                   Seq.filter_map (fun (lb, lc) ->
                       let ok = List.for_all2 (fun j n -> match elements c j with
                           | Some l ->
                               let k = List.fold_left (fun k v -> match run_lam (lb, lc) j v with
                                   | Some (Value.Bool true) -> k + 1 | Some (Value.Bool false) -> k | _ -> -1000) 0 l in
                               k = n
                           | None -> false) cs ns in
                       if ok then Some (Expr.Call ("List.length", [ Expr.Call ("List.filter",
                                                                     [ Expr.Lam (List.map fst lb.params, lc.expr); c.expr ]) ]))
                       else None) (List.to_seq (lambdas te t_bool)) |> take_seq 1
               | _ -> Seq.empty) (List.to_seq (take 40 cands)));
        (* sum over a list of a function of each element *)
        (fun () ->
           Seq.flat_map (fun c ->
               match repr c.ty with
               | TCon ("list", [ te ]) ->
                   Seq.filter_map (fun (lb, lc) ->
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
                       else None) (List.to_seq (lambdas te t_int)) |> take_seq 1
               | _ -> Seq.empty) (List.to_seq (take 40 list_terms)));
      ] @ arithmetic |> fun l -> alts l
  | _ -> Seq.empty

and by_cond st ctx b g cs depth : sols =
  if List.length cs < 2 then Seq.empty
  else
    let tests = List.filter (fun c -> key c.ty = "bool"
        && List.for_all (fun j -> match c.vec.(j) with Some (Value.Bool _) -> true | _ -> false) cs
        && Array.for_all (fun x -> x) (Array.mapi (fun j d -> not d || c.vec.(j) <> None) g.defined)
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
    (* `if x = 5 then 225` is a lookup table, not a program: a guard that
       compares a parameter with a literal nothing explains is refused *)
    let memorizes (c : cand) = match c.expr with
      | Expr.Call (("=" | "<>"), [ Expr.Var _; Expr.Lit v ]) | Expr.Call (("=" | "<>"), [ Expr.Lit v; Expr.Var _ ]) ->
          (match v with
           | Value.Int (0 | 1) | Value.Bool _ | Value.List [] | Value.String "" | Value.Char ' ' -> false
           | _ -> true)
      | _ -> false in
    let tests = List.filter (fun c -> not (memorizes c)) tests in
    (* in a recursion step, ask about the input (h, t) before the result r *)
    let tests = let avoids c = List.exists (fun v -> Expr.mentions v c.expr) st.avoid_in_guards in
      List.filter (fun c -> not (avoids c)) tests @ List.filter avoids tests in
    Seq.flat_map (fun c ->
        let yes = restrict (sub g (fun j v -> if c.vec.(j) = Some (Value.Bool true) then Some v else None))
            (fun j -> c.vec.(j) = Some (Value.Bool true)) in
        let no = restrict (sub g (fun j v -> if c.vec.(j) = Some (Value.Bool false) then Some v else None))
            (fun j -> c.vec.(j) = Some (Value.Bool false)) in
        (* a guard is a question the examples may answer by accident, so a
           conditional costs two levels where a decomposition costs one *)
        Seq.map (function [ a; e ] -> Expr.If (c.expr, a, e) | _ -> assert false)
          (product [ sub_solve st ctx b yes (depth - 2); sub_solve st ctx b no (depth - 2) ]))
      (List.to_seq (take 10 tests))

type result = Solved of Expr.t * int | Gave_up of string

(* Inputs at the edge of each parameter's type, in the first example's
   context: the cases a total program handles and the examples often omit. *)
let edge_inputs (params : (string * ty) list) (points : (string * Value.t) list list) =
  match points with
  | [] -> []
  | p0 :: _ ->
      let edges t = match repr t with
        | TCon ("list", _) -> [ Value.List [] ]
        | TCon ("string", []) -> [ Value.String "" ]
        | TCon ("int", []) -> [ Value.Int 0 ]
        | TCon ("option", _) -> [ Value.Con ("None", []) ]
        | _ -> [] in
      let pts = List.concat_map (fun (x, t) ->
          List.filter_map (fun v ->
              let p = List.map (fun (y, w) -> if y = x then (y, v) else (y, w)) p0 in
              if List.exists (fun q -> List.for_all2 (fun (_, a) (_, b) -> Value.equal a b) q p) points then None
              else Some p) (edges t)) params in
      List.filteri (fun i _ -> i < 6) pts

let solve_top ?(cfg = default) ?(bank_size = 6) ?(lambda_bank_size = 5) ?(depth = 4) ?(self = "f") ?(edges = false)
    ?(recursion_allowed = true) ?(avoid_in_guards = [])
    ~decls ~params ~out_ty (examples : Spec.example list) =
  Synth.total := 0;
  Synth.pending := [];
  let st = { cfg; decls; examples; steps = 0; banks = Hashtbl.create 8; bank_size; lambda_bank_size; avoid_in_guards } in
  let base_points = List.map (fun ex -> List.combine (List.map fst params) ex.Spec.args) examples in
  let edge_points = if edges then edge_inputs params base_points else [] in
  let points = Array.of_list (base_points @ edge_points) in
  let ctx = { vars = params; points } in
  let b = bank_for st ctx [ out_ty ] bank_size in
  let n_ex = List.length examples in
  let g = { gty = out_ty;
            outs = Array.init (Array.length points) (fun j -> if j < n_ex then Some (List.nth examples j).Spec.out else None);
            defined = Array.init (Array.length points) (fun j -> j >= n_ex) } in
  (* Shallow deduction first, then structural recursion, then deeper
     deduction: a recursive program is preferred to a deep chain of guards. *)
  let recursion () =
    let attempt f = try f () with Exhausted -> None in
    match attempt (fun () -> Recur.list_recursion ~cfg ~self ~decls ~params ~out_ty examples) with
    | Some e -> Some e
    | None -> attempt (fun () -> Recur.int_recursion ~cfg ~self ~decls ~params ~out_ty examples) in
  (* Every parameter of a part matters, so a program that ignores one is
     probably fitting a coincidence (replicate's one example has a list of
     length 3 and a count of 3). The first solution that uses all of them is
     preferred; failing that, the first solution at all. *)
  (* Relevance is semantic: naming a parameter in dead code does not use it.
     Each parameter is varied over values drawn from the examples themselves
     (no reference, no oracle), and some variation must change the answer. *)
  let alternatives_for i =
    dedupe (List.filter_map (fun ex -> List.nth_opt ex.Spec.args i) examples
            @ List.concat_map (fun ex -> List.filter_map (fun v ->
                if List.length (dedupe [ v; List.nth ex.Spec.args i ]) = 2 then Some v else None)
                (List.filteri (fun k _ -> k < 6) (samples ctx (List.nth (List.map snd params) i)))) examples) in
  let uses_all e =
    List.for_all (fun (p, _) -> Expr.mentions p e) params
    && List.for_all (fun i ->
        let alts = alternatives_for i in
        List.exists (fun ex ->
            let run args = Eval.run ~budget:20_000 (List.combine (List.map fst params) args) e in
            let base = run ex.Spec.args in
            List.exists (fun a ->
                let args = List.mapi (fun k v -> if k = i then a else v) ex.Spec.args in
                match run args, base with
                | Some v, Some b -> not (Value.equal v b)
                | Some _, None | None, Some _ -> true
                | None, None -> false) alts) examples
        || List.length alts < 2) (List.init (List.length params) Fun.id) in
  let first = ref None and first_depth = ref None in
  let scan d =
    let seen = ref 0 in
    let rec go s = match s () with
      | Seq.Nil -> None
      | Seq.Cons (e, rest) ->
          if !first = None then first := Some e;
          incr seen;
          if uses_all e then Some e else if !seen >= 40 then None else go rest in
    go (solve st ctx b g d) in
  let rec deepen d =
    if d > depth then
      (match !first with
       | Some e -> Solved (e, st.steps)
       | None -> Gave_up (Printf.sprintf "no derivation within depth %d (%d steps)" depth st.steps))
    else if d = 3 && !first = None && recursion_allowed then
      (match recursion () with
       | Some e -> Solved (e, st.steps)
       | None -> (match scan d with Some e -> Solved (e, st.steps) | None -> deepen (d + 1)))
    else match scan d with
      | Some e -> Solved (e, st.steps)
      | None ->
          (* found something that ignores a parameter: one level deeper, then settle *)
          (match !first, !first_depth with
           | Some _, None -> first_depth := Some d; deepen (d + 1)
           | Some _, Some d0 when d > d0 -> deepen (depth + 1)
           | _ -> deepen (d + 1))
  in
  let debug r =
    if Sys.getenv_opt "GW_DEBUG" <> None then
      Printf.eprintf "  [solve_top %d examples, %d params: %d steps, %d terms kept, %d banks]\n%!"
        (List.length examples) (List.length params) st.steps !Synth.total (Hashtbl.length st.banks);
    r in
  debug @@ try deepen 0 with
  | Out_of_steps | Exhausted as ex ->
      (match !first with
       | Some e -> Solved (e, st.steps)
       | None -> Gave_up (match ex with
           | Out_of_steps -> Printf.sprintf "deduction bound reached: %d steps" st.steps
           | _ -> Printf.sprintf "term bound reached: %d terms kept" !Synth.total))

(* ------------------------------------------------------ traced recursion *)

(* What f returns on each suffix of x, under a hypothesis the example itself
   suggests. None when the hypothesis does not fit the example. *)
let suffix_outputs hyp (xs : Value.t list) (out : Value.t) : Value.t list option =
  let n = List.length xs in
  let drop k l = List.filteri (fun i _ -> i >= k) l in
  match hyp, out with
  | `Map, Value.List o when List.length o = n -> Some (List.init (n + 1) (fun i -> Value.List (drop i o)))
  | (`Sub_left | `Sub_right), Value.List o ->
      (* positions of out within xs, leftmost or rightmost greedy *)
      let xa = Array.of_list xs and oa = Array.of_list o in
      let m = Array.length oa in
      let pos = Array.make m (-1) in
      let ok =
        if hyp = `Sub_left then begin
          let j = ref 0 in
          Array.iteri (fun k v -> if !j < m && Value.equal v oa.(!j) then (pos.(!j) <- k; incr j)) xa; !j = m
        end else begin
          let j = ref (m - 1) in
          for k = n - 1 downto 0 do
            if !j >= 0 && Value.equal xa.(k) oa.(!j) then (pos.(!j) <- k; decr j)
          done; !j < 0
        end in
      if not ok || m = n then None
      else Some (List.init (n + 1) (fun i ->
          Value.List (List.filteri (fun k _ -> pos.(k) >= i) o)))
  | `Chunks, Value.List chunks ->
      let pieces = List.map (function Value.List l -> Some l | _ -> None) chunks in
      if List.exists Option.is_none pieces then None
      else
        let pieces = List.map Option.get pieces in
        if List.exists (( = ) []) pieces || not (List.for_all2 Value.equal (List.concat pieces) xs) then None
        else
          (* cut the chunk sequence at element i *)
          let cut i =
            let rec go k = function
              | [] -> []
              | p :: rest ->
                  let len = List.length p in
                  if k >= len then go (k - len) rest
                  else Value.List (drop k p) :: List.map (fun q -> Value.List q) rest in
            Value.List (go i pieces) in
          Some (List.init (n + 1) cut)
  | _ -> None

(* Structural recursion with its traces completed by hypothesis, the step
   solved by deduction on exact points, the whole program accepted only if
   running it reproduces the original examples. *)
let traced_recursion ?(cfg = default) ~self ~decls ~(params : (string * ty) list) ~out_ty
    (examples : Spec.example list) =
  let pnames = List.map fst params in
  match repr out_ty with
  | TCon ("list", _) ->
      List.find_map (fun (x, xty) ->
          match repr xty with
          | TCon ("list", [ te ]) ->
              let xi = let rec idx i = function [] -> 0 | p :: r -> if p = x then i else idx (i + 1) r in idx 0 pnames in
              List.find_map (fun hyp ->
                  let traces = List.map (fun ex ->
                      match List.nth ex.Spec.args xi with
                      | Value.List xs -> Option.map (fun outs -> (ex, xs, outs)) (suffix_outputs hyp xs ex.Spec.out)
                      | _ -> None) examples in
                  if List.exists Option.is_none traces then None
                  else
                    let traces = List.map Option.get traces in
                    let others = List.filter (fun (p, _) -> p <> x) params in
                    let step_examples = List.concat_map (fun (ex, xs, outs) ->
                        List.mapi (fun i h ->
                            let t = List.filteri (fun k _ -> k > i) xs in
                            let other_args = List.filteri (fun k _ -> k <> xi) ex.Spec.args in
                            { Spec.args = [ h; Value.List t; List.nth outs (i + 1) ] @ other_args;
                              out = List.nth outs i }) xs) traces in
                    (* one input, one output *)
                    let consistent = List.for_all (fun a -> List.for_all (fun b ->
                        not (List.for_all2 Value.equal a.Spec.args b.Spec.args) || Value.equal a.Spec.out b.Spec.out)
                        step_examples) step_examples in
                    let step_examples = List.fold_left (fun acc ex ->
                        if List.exists (fun e -> List.for_all2 Value.equal e.Spec.args ex.Spec.args) acc then acc
                        else acc @ [ ex ]) [] step_examples in
                    if not consistent || step_examples = [] then None
                    else
                      let sparams = [ ("h", te); ("t", xty); ("r", out_ty) ] @ others in
                      match solve_top ~cfg ~depth:6 ~recursion_allowed:false ~avoid_in_guards:[ "r" ]
                              ~decls ~params:sparams ~out_ty step_examples with
                      | Gave_up _ -> None
                      | Solved (s, _) ->
                          let body = Recur.program ~self ~pnames ~x (Expr.Lit (Value.List [])) s in
                          if Recur.runs ~self ~pnames body examples then Some body else None)
                [ `Map; `Sub_right; `Sub_left; `Chunks ]
          | _ -> None) params
  | _ -> None

(* Does a derived body reproduce an example? Run as the recursive
   definition it will be printed as. *)
let reproduces ~self ~params body (ex : Spec.example) =
  let names = List.map fst params in
  match Eval.run ~budget:200_000 []
          (Expr.Let (true, self, Expr.Lam (names, body),
                     Expr.App (Expr.Var self, List.map (fun v -> Expr.Lit v) ex.Spec.args))) with
  | Some v -> Value.equal v ex.Spec.out
  | None -> false

(* Counterexample-guided use of the part's own examples: derive from a small
   spread of them, run the result on all, add the first it gets wrong, and go
   again. Every judgement is still against all the examples; the search just
   stops paying for twenty points where four decide. *)
let rec solve_cegis ?cfg ?bank_size ?lambda_bank_size ?depth ?self ~decls ~params ~out_ty examples =
  let n = List.length examples in
  if n <= 6 then solve_param_all ?cfg ?bank_size ?lambda_bank_size ?depth ?self ~decls ~params ~out_ty examples
  else
    let spread k = List.sort_uniq compare (List.init k (fun i -> i * (n - 1) / (k - 1))) in
    let pick idx = List.filteri (fun i _ -> List.mem i idx) examples in
    let self_name = Option.value self ~default:"f" in
    let rec loop idx rounds =
      let subset = pick idx in
      match solve_param_all ?cfg ?bank_size ?lambda_bank_size ?depth ?self ~decls ~params ~out_ty subset with
      | Gave_up _ as g -> if List.length idx >= n then g else loop (List.init n Fun.id) (rounds + 1)
      | Solved (e, k) ->
          (match List.find_opt (fun i -> not (reproduces ~self:self_name ~params e (List.nth examples i)))
                   (List.init n Fun.id) with
           | None -> Solved (e, k)
           | Some i when rounds < 10 -> loop (List.sort_uniq compare (i :: idx)) (rounds + 1)
           | Some _ -> solve_param_all ?cfg ?bank_size ?lambda_bank_size ?depth ?self ~decls ~params ~out_ty examples)
    in
    loop (spread 5) 0

(* The strict parametric reading first (free-theorem examples, no comparison
   of a rigid 'a), then the ordinary one. *)
and solve_param_all ?cfg ?bank_size ?lambda_bank_size ?depth ?self ~decls ~params ~out_ty examples =
  let base = match cfg with Some c -> c | None -> default in
  let attempt cfg exs =
    match solve_top ~cfg ?bank_size ?lambda_bank_size ?depth ?self ~edges:true ~decls ~params ~out_ty exs with
    | Solved _ as r -> r
    | Gave_up _ -> solve_top ~cfg ?bank_size ?lambda_bank_size ?depth ?self ~decls ~params ~out_ty exs in
  let ordinary () =
    (* a recursion whose traces the examples themselves complete comes first:
       it is the structure the examples show, not a fit to their values *)
    match (try traced_recursion ~cfg:base ~self:(Option.value self ~default:"f") ~decls ~params ~out_ty examples
           with Exhausted | Out_of_steps -> None) with
    | Some e -> Solved (e, 0)
    | None -> attempt base examples in
  (* The collapsing theorem is only safe to lean on when the output carries
     a 'a: a function to a 'a-free type (a test, a count) that never looks
     at its elements depends on shape alone, which the parts asking for one
     rarely mean; is_palindrome compares, and collapsing would lie about it. *)
  match (if Parametric.has_var out_ty then Parametric.augment ~params ~out_ty examples else None) with
  | None -> ordinary ()
  | Some more ->
      (match attempt { base with strict = true } more with
       | Solved _ as r -> r
       | Gave_up why ->
           if Sys.getenv_opt "GW_DEBUG" <> None then prerr_endline ("  strict reading gave up: " ^ why);
           ordinary ())

let solve_param = solve_cegis
