(* Structural recursion over a list parameter:
 *
 *     let rec f ... x ... = match x with [] -> B | h :: t -> S
 *
 * where S may use h, t, the other parameters, and r, the recursive result
 * f ... t ... . The examples rarely say what f returns on a tail (two
 * examples of `compress` show nothing about its suffixes), so r cannot be
 * looked up. Instead:
 *
 *   - S is enumerated bottom-up in a context whose points are the REAL
 *     suffixes of the example lists, each paired with a few sample values for
 *     r drawn from the example outputs; two bodies equal at every point are
 *     kept once;
 *   - each distinct (B, S), smallest first, is assembled into the recursive
 *     program and RUN on the examples. Only a program that reproduces every
 *     example is accepted.
 *
 * So sampling can lose a solution, never admit a wrong one; and recursion
 * never meets the examples except by running. *)

open Types
open Synth

let rec suffixes = function [] -> [] | (_ :: t) as l -> l :: suffixes t

let program ~self ~pnames ~x body_nil body_cons =
  let call_on_tail = Expr.App (Expr.Var self, List.map (fun p -> if p = x then Expr.Var "t" else Expr.Var p) pnames) in
  let rec subst_r (e : Expr.t) : Expr.t =
    match e with
    | Expr.Var "r" -> call_on_tail
    | Expr.Var _ | Expr.Lit _ | Expr.Poly (_, None) -> e
    | Expr.Call (n, a) -> Expr.Call (n, List.map subst_r a)
    | Expr.App (f, a) -> Expr.App (subst_r f, List.map subst_r a)
    | Expr.Lam (xs, b) -> if List.mem "r" xs then e else Expr.Lam (xs, subst_r b)
    | Expr.Con (c, a) -> Expr.Con (c, List.map subst_r a)
    | Expr.Poly (t, Some a) -> Expr.Poly (t, Some (subst_r a))
    | Expr.Tuple a -> Expr.Tuple (List.map subst_r a)
    | Expr.Record fs -> Expr.Record (List.map (fun (f, a) -> (f, subst_r a)) fs)
    | Expr.Field (a, f) -> Expr.Field (subst_r a, f)
    | Expr.If (c, a, b) -> Expr.If (subst_r c, subst_r a, subst_r b)
    | Expr.Match (s, bs) -> Expr.Match (subst_r s, List.map (fun (p, b) -> (p, subst_r b)) bs)
    | Expr.Let (r, v, a, b) -> Expr.Let (r, v, subst_r a, subst_r b)
  in
  (* bind r once, so the tail is recursed on once however often S uses it *)
  let s = if Expr.mentions "r" body_cons then Expr.Let (false, "r", call_on_tail, body_cons) else body_cons in
  ignore subst_r;
  Expr.Match (Expr.Var x, [ (Expr.PNil, body_nil); (Expr.PCons (Expr.PVar "h", Expr.PVar "t"), s) ])

let runs ~self ~pnames body (examples : Spec.example list) =
  let def = Expr.Lam (pnames, body) in
  List.for_all (fun ex ->
      let call = Expr.Let (true, self, def,
                           Expr.App (Expr.Var self, List.map (fun v -> Expr.Lit v) ex.Spec.args)) in
      match Eval.run ~budget:50_000 [] call with
      | Some v -> Value.equal v ex.Spec.out
      | None -> false) examples

let list_recursion ?(cfg = default) ?(body_size = 7) ~self ~decls ~(params : (string * ty) list) ~out_ty
    (examples : Spec.example list) =
  let pnames = List.map fst params in
  let list_params = List.filter (fun (_, t) -> match repr t with TCon ("list", [ _ ]) -> true | _ -> false) params in
  List.find_map (fun (x, xty) ->
      let ety = match repr xty with TCon ("list", [ e ]) -> e | _ -> xty in
      let xi = let rec idx i = function [] -> 0 | p :: r -> if p = x then i else idx (i + 1) r in idx 0 pnames in
      (* samples for r: values of the output type in the examples *)
      let out_ctx = { vars = [ ("__o", out_ty) ];
                      points = Array.of_list (List.map (fun ex -> [ ("__o", ex.Spec.out) ]) examples) } in
      let rs = samples out_ctx out_ty in
      let rs = List.filteri (fun i _ -> i < 3) (rs @ (match repr out_ty with
          | TCon ("list", _) -> [ Value.List [] ] | TCon ("int", []) -> [ Value.Int 0 ] | _ -> [])) in
      let rs = dedupe rs in
      if rs = [] then None
      else
        let points = List.concat_map (fun ex ->
            let xv = match List.nth ex.Spec.args xi with Value.List l -> l | _ -> [] in
            List.concat_map (fun suf -> match suf with
                | h :: t ->
                    List.map (fun r ->
                        [ ("h", h); ("t", Value.List t); ("r", r) ]
                        @ List.combine pnames (List.mapi (fun k a -> if k = xi then Value.List suf else a) ex.Spec.args))
                      rs
                | [] -> []) (suffixes xv)) examples in
        let points = List.filteri (fun i _ -> i < 120) points in
        if points = [] then None
        else
          let step_ctx = { vars = [ ("h", ety); ("t", xty); ("r", out_ty) ] @ params; points = Array.of_list points } in
          let step = build_search ~cfg ~decls ~examples ~ctx:step_ctx ~types:[ out_ty ] body_size in
          let steps = List.filteri (fun i _ -> i < 4000) (terms_of step.main out_ty) in
          (* the base case, over the other parameters *)
          let others = List.filter (fun (p, _) -> p <> x) params in
          let base_ctx = { vars = others;
                           points = Array.of_list (List.map (fun ex ->
                               List.filter (fun (p, _) -> p <> x) (List.combine pnames ex.Spec.args)) examples) } in
          let base = build_search ~cfg ~decls ~examples ~ctx:base_ctx ~types:[ out_ty ] 3 in
          let nil_examples = List.filter (fun ex -> List.nth ex.Spec.args xi = Value.List []) examples in
          let bases = List.filter (fun c ->
              List.for_all (fun ex -> match Eval.run (List.combine pnames ex.Spec.args) c.expr with
                  | Some v -> Value.equal v ex.Spec.out | None -> false) nil_examples)
              (terms_of base.main out_ty) in
          let bases = List.filteri (fun i _ -> i < 6) bases in
          (* smallest program first *)
          let pairs = List.concat_map (fun b -> List.map (fun s -> (b, s)) steps) bases in
          let pairs = List.stable_sort (fun (b1, s1) (b2, s2) ->
              compare (b1.size + s1.size) (b2.size + s2.size)) pairs in
          List.find_map (fun (b, s) ->
              if not (Expr.mentions "r" s.expr) && not (Expr.mentions "t" s.expr) && not (Expr.mentions "h" s.expr)
              then None   (* a body that ignores the list is not recursion *)
              else
                let body = program ~self ~pnames ~x b.expr s.expr in
                if runs ~self ~pnames body examples then Some body else None) pairs)
    list_params

(* Recursion on a decreasing argument:
 *
 *     let rec f x = if G then B else S        where r = f (N x)
 *
 * For a candidate next-argument N (a term strictly smaller than the argument
 * in absolute value, wherever the argument is not zero) and a guard G, each
 * example's CHAIN is fixed: x, N x, N (N x), ... up to the first point where
 * G holds. Base and step are then judged by folding along those real chains:
 * the base at the last point, the step back up to the first. No value of r is
 * sampled or guessed; the chains are the recursion actually unrolled.
 *
 * Examples whose chain is a single step pin S down directly (out = S(x, B(N
 * x))), which prunes most step candidates before any full fold. *)
let int_recursion ?(cfg = default) ?(body_size = 6) ~self ~decls ~(params : (string * ty) list) ~out_ty
    (examples : Spec.example list) =
  let pnames = List.map fst params in
  let points = List.map (fun ex -> List.combine pnames ex.Spec.args) examples in
  let ctx = { vars = params; points = Array.of_list points } in
  let srch = build_search ~cfg ~decls ~examples ~ctx ~types:(out_ty :: t_bool :: List.map snd params) 4 in
  let terms t = terms_of srch.main t in
  let ev env e = Eval.run ~budget:5_000 env e in
  let int_params = List.filter (fun (_, t) -> key t = "int") params in
  List.find_map (fun (x, _) ->
      let absv env = match List.assoc_opt x env with Some (Value.Int n) -> Some (abs n) | _ -> None in
      let nexts = List.filter (fun c ->
          c.size >= 2 && Expr.mentions x c.expr
          && List.for_all2 (fun p v -> match absv p, v with
              | Some 0, _ -> true
              | Some a, Some (Value.Int n) -> abs n < a
              | _ -> false) points (Array.to_list c.vec)) (terms t_int) in
      let nexts = List.filteri (fun i _ -> i < 10) nexts in
      List.find_map (fun n ->
          let step env = match ev env n.expr with
            | Some v -> Some (List.map (fun (y, w) -> if y = x then (y, v) else (y, w)) env)
            | None -> None in
          let guards = List.filteri (fun i _ -> i < 40) (terms t_bool) in
          List.find_map (fun g ->
              let rec chain env k acc =
                if k > 64 then None
                else match ev env g.expr with
                  | Some (Value.Bool true) -> Some (List.rev (env :: acc))
                  | Some (Value.Bool false) -> (match step env with Some e -> chain e (k + 1) (env :: acc) | None -> None)
                  | _ -> None in
              let chains = List.map (fun p -> chain p 0 []) points in
              if List.exists Option.is_none chains then None
              else
                let chains = List.map Option.get chains in
                (* the base, at each chain's end *)
                let bases = List.filteri (fun i _ -> i < 8) (List.filter (fun b ->
                    List.for_all (fun ch -> ev (List.nth ch (List.length ch - 1)) b.expr <> None) chains)
                    (List.filter (fun c -> c.size <= 3) (terms out_ty))) in
                (* step candidates, enumerated over the chain points with r sampled *)
                let rs = dedupe (List.map (fun ex -> ex.Spec.out) examples) in
                let rs = List.filteri (fun i _ -> i < 3) rs in
                let step_points = List.concat_map (fun ch ->
                    List.concat_map (fun env -> List.map (fun r -> ("r", r) :: env) rs)
                      (List.filteri (fun i _ -> i < List.length ch - 1) ch)) chains in
                let step_points = List.filteri (fun i _ -> i < 120) step_points in
                if step_points = [] then None
                else
                  let sctx = { vars = ("r", out_ty) :: params; points = Array.of_list step_points } in
                  let ssrch = build_search ~cfg ~decls ~examples ~ctx:sctx ~types:[ out_ty ] body_size in
                  let steps = List.filter (fun c -> Expr.mentions "r" c.expr)
                      (List.filteri (fun i _ -> i < 3000) (terms_of ssrch.main out_ty)) in
                  List.find_map (fun b ->
                      let fold s = List.for_all2 (fun ch ex ->
                          let rev = List.rev ch in
                          match ev (List.hd rev) b.expr with
                          | None -> false
                          | Some r0 ->
                              let r = List.fold_left (fun acc env -> match acc with
                                  | None -> None
                                  | Some r -> ev (("r", r) :: env) s.expr) (Some r0) (List.tl rev) in
                              (match r with Some v -> Value.equal v ex.Spec.out | None -> false)) chains examples in
                      match List.find_opt fold steps with
                      | None -> None
                      | Some s ->
                          let call = Expr.App (Expr.Var self, List.map (fun p -> if p = x then n.expr else Expr.Var p) pnames) in
                          Some (Expr.If (g.expr, b.expr, Expr.Let (false, "r", call, s.expr)))) bases) guards) nexts)
    int_params
