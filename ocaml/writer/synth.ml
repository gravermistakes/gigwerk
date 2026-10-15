(* The writer's search: the smallest term the examples cannot tell from the
 * part, found by enumeration.
 *
 * Terms are built bottom-up by size from the parameters, a few constants and
 * the Stdlib components. Each term is judged by its VECTOR: its value at every
 * point of the context (one point per example). Two terms with the same type
 * and the same vector are indistinguishable by everything the part has said,
 * so only the first (the smallest) is kept. That pruning, observational
 * equivalence, is what makes enumeration finite in practice.
 *
 * A function passed to a higher-order component (List.map's f) is enumerated
 * in its own context: its points are the outer examples crossed with sample
 * values for its parameters, drawn from the examples themselves. Two lambda
 * bodies equal at every sample are kept once. This can merge bodies that
 * differ somewhere unsampled, so the search may miss a solution; it cannot
 * accept a wrong one, because every candidate is judged in the main context
 * by actually running it.
 *
 * Every bound is a count, never a clock: the same part gets the same answer
 * on any machine, which is what admission checks. *)

open Types

type point = (string * Value.t) list

type cand = { expr : Expr.t; size : int; ty : ty; vec : Value.t option array }

type ctx = {
  vars : (string * ty) list;
  points : point array;
}

type bank = {
  ctx : ctx;
  by_size : (int, (string * ty * cand list ref) list ref) Hashtbl.t;
  seen : (string, unit) Hashtbl.t;
  mutable count : int;
}

type config = {
  strict : bool;                   (* no comparison may touch a rigid 'a *)
  max_size : int;
  max_lambda_size : int;
  max_cands : int;                 (* total terms kept, across all banks *)
  fuel : int;                      (* evaluation steps per application *)
}

let default = { strict = false; max_size = 9; max_lambda_size = 5; max_cands = 40_000; fuel = 2_000 }

(* Terms kept across every bank of one derivation. Banks are per context and
   a deduction opens many contexts; without a total they add up to whatever
   memory there is. *)
let global_cap = 300_000

exception Found of Expr.t
exception Exhausted

(* ------------------------------------------------------------ types, ground *)

let key t = Types.to_string t

let rec subst_apply s t =
  match repr t with
  | TGen i -> (match List.assoc_opt i s with Some t -> t | None -> t)
  | TCon (n, ts) -> TCon (n, List.map (subst_apply s) ts)
  | TTuple ts -> TTuple (List.map (subst_apply s) ts)
  | TArrow (l, a, b) -> TArrow (l, subst_apply s a, subst_apply s b)
  | t -> t

let rec has_gen t =
  match repr t with
  | TGen _ -> true
  | TCon (_, ts) | TTuple ts -> List.exists has_gen ts
  | TArrow (_, a, b) -> has_gen a || has_gen b
  | _ -> false

(* Match a component's scheme against a ground type. *)
let rec mtch s sch g =
  match repr sch, repr g with
  | TGen i, _ ->
      (match List.assoc_opt i s with
       | Some t -> if key t = key g then Some s else None
       | None -> Some ((i, g) :: s))
  | TCon (n, a), TCon (m, b) when n = m && List.length a = List.length b -> mtch_all s a b
  | TTuple a, TTuple b when List.length a = List.length b -> mtch_all s a b
  | TArrow (_, a, b), TArrow (_, c, d) -> Option.bind (mtch s a c) (fun s -> mtch s b d)
  | TVar x, TVar y when x = y -> Some s
  | _ -> None
and mtch_all s a b =
  match a, b with
  | [], [] -> Some s
  | x :: xs, y :: ys -> Option.bind (mtch s x y) (fun s -> mtch_all s xs ys)
  | _ -> None

(* ------------------------------------------------------------- the vectors *)

let vec_key v =
  String.concat "\x00" (Array.to_list (Array.map (function
      | None -> "_|_" | Some v -> (try Value.to_ocaml v with _ -> "<fun>")) v))

let first_order t =
  let rec go t = match repr t with
    | TArrow _ -> false
    | TCon (_, ts) | TTuple ts -> List.for_all go ts
    | _ -> true in
  go t

(* ------------------------------------------------------------------ banks *)

let new_bank ctx = { ctx; by_size = Hashtbl.create 16; seen = Hashtbl.create 1024; count = 0 }

let total = ref 0

let level b n =
  match Hashtbl.find_opt b.by_size n with
  | Some l -> l
  | None -> let l = ref [] in Hashtbl.replace b.by_size n l; l

(* A test on one integer variable that singles out one value of it (true at
   exactly one point, or false at exactly one) is a lookup of an example
   however it is spelled: x = 2, 1 = pred y. Detected by running it over a
   window; points at 0 and 1 are the natural boundaries and stay. *)
let int_vars = ref []
let all_vars : (string * ty) list ref = ref []

let point_test (c : cand) =
  key c.ty = "bool" && c.size <= 7
  && (match List.filter (fun x -> Expr.mentions x c.expr) !int_vars with
      | [ x ] when not (List.exists (fun (y : string) -> y <> x && Expr.mentions y c.expr)
                          (List.map fst !all_vars)) ->
          let trues = ref [] and falses = ref [] in
          for n = -20 to 220 do
            match Eval.run ~budget:200 [ (x, Value.Int n) ] c.expr with
            | Some (Value.Bool true) -> trues := n :: !trues
            | Some (Value.Bool false) -> falses := n :: !falses
            | _ -> ()
          done;
          (match !trues, !falses with
           | [ n ], _ :: _ :: _ -> n <> 0 && n <> 1
           | _ :: _ :: _, [ n ] -> n <> 0 && n <> 1
           | _ -> false)
      | _ -> false)

let add cfg b c =
  (* functions enter a bank only as the parameters that hold them *)
  if not (first_order c.ty) && (match c.expr with Expr.Var _ -> false | _ -> true) then false
  else if point_test c then false
  else
    let k = key c.ty ^ "\x01" ^ vec_key c.vec in
    if Hashtbl.mem b.seen k then false
    else begin
      Hashtbl.replace b.seen k ();
      b.count <- b.count + 1;
      incr total;
      if b.count > cfg.max_cands || !total > global_cap then raise Exhausted;
      let lv = level b c.size in
      let tk = key c.ty in
      (match List.find_opt (fun (k', _, _) -> k' = tk) !lv with
       | Some (_, _, l) -> l := c :: !l
       | None -> lv := !lv @ [ (tk, c.ty, ref [ c ]) ]);
      true
    end

(* Candidates of exactly size n, oldest first: enumeration order is part of
   the answer, so it must not depend on anything but the search itself. *)
let at b n =
  match Hashtbl.find_opt b.by_size n with
  | None -> []
  | Some l -> List.map (fun (_, t, cs) -> (t, List.rev !cs)) !l

(* ------------------------------------------------------------- components *)

type comp = {
  cname : string;
  scheme : ty;
  build : Expr.t list -> Expr.t;
  run : Value.t list -> Value.t;
}

let is_component comp = Hashtbl.mem Eval.components comp.cname

(* Components that compare values of their first type variable. *)
let comparing = [ "="; "<>"; "<"; ">"; "<="; ">="; "compare"; "max"; "min"; "List.mem";
                  "List.sort"; "List.sort_uniq"; "List.assoc_opt" ]

let sibling_comps () =
  Hashtbl.fold (fun name _ acc ->
      match Hashtbl.find_opt Eval.components name with
      | Some c -> { cname = c.Components.name; scheme = c.Components.scheme;
                    build = (fun args -> Expr.Call (name, args)); run = c.Components.impl } :: acc
      | None -> acc) Components.siblings []
  |> List.sort (fun a b -> compare a.cname b.cname)

let of_component (c : Components.t) =
  { cname = c.Components.name; scheme = c.Components.scheme;
    build = (fun args -> Expr.Call (c.Components.name, args)); run = c.Components.impl }

(* Constructors of the part's own declarations, and the builtin ones. *)
let ctor_comps (decls : decl list) =
  let gen_of params t =
    let rec go t = match repr t with
      | TVar v ->
          let rec idx i = function [] -> None | x :: r -> if x = v then Some i else idx (i + 1) r in
          (match idx 0 params with Some i -> TGen i | None -> t)
      | TCon (n, ts) -> TCon (n, List.map go ts)
      | TTuple ts -> TTuple (List.map go ts)
      | TArrow (l, a, b) -> TArrow (l, go a, go b)
      | t -> t in go t in
  let self d = TCon (d.name, List.mapi (fun i _ -> TGen i) d.params) in
  let builtin = [
    (* calling a function the part was given *)
    { cname = "__app1"; scheme = arrows [ arrow (TGen 0) (TGen 1); TGen 0 ] (TGen 1);
      build = (fun a -> match a with [ f; x ] -> Expr.App (f, [ x ]) | _ -> assert false);
      run = (function [ f; x ] -> Components.apply f x | _ -> raise Components.Undefined) };
    { cname = "__app2"; scheme = arrows [ arrows [ TGen 0; TGen 1 ] (TGen 2); TGen 0; TGen 1 ] (TGen 2);
      build = (fun a -> match a with [ f; x; y ] -> Expr.App (f, [ x; y ]) | _ -> assert false);
      run = (function [ f; x; y ] -> Components.apply2 f x y | _ -> raise Components.Undefined) };
    { cname = "Some"; scheme = arrow (TGen 0) (t_option (TGen 0));
      build = (fun a -> Expr.Con ("Some", a)); run = (fun a -> Value.Con ("Some", a)) };
    { cname = "Ok"; scheme = arrow (TGen 0) (t_result (TGen 0) (TGen 1));
      build = (fun a -> Expr.Con ("Ok", a)); run = (fun a -> Value.Con ("Ok", a)) };
    { cname = "Error"; scheme = arrow (TGen 1) (t_result (TGen 0) (TGen 1));
      build = (fun a -> Expr.Con ("Error", a)); run = (fun a -> Value.Con ("Error", a)) };
    { cname = "pair"; scheme = arrows [ TGen 0; TGen 1 ] (TTuple [ TGen 0; TGen 1 ]);
      build = (fun a -> Expr.Tuple a); run = (fun a -> Value.Tuple a) };
  ] in
  builtin @ List.concat_map (fun d ->
      match d.kind with
      | Variant ctors ->
          List.filter_map (fun (c, args) ->
              if args = [] then None
              else Some { cname = c; scheme = arrows (List.map (gen_of d.params) args) (self d);
                          build = (fun a -> Expr.Con (c, a));
                          run = (fun a -> Value.Con (c, a)) }) ctors
      | Poly rows ->
          List.filter_map (fun (tag, arg) -> match arg with
              | None -> None
              | Some t -> Some { cname = "`" ^ tag; scheme = arrow (gen_of d.params t) (self d);
                                 build = (fun a -> Expr.Poly (tag, Some (List.hd a)));
                                 run = (fun a -> Value.Poly (tag, Some (List.hd a))) }) rows
      | Record fields ->
          { cname = "{" ^ d.name ^ "}";
            scheme = arrows (List.map (fun (_, t) -> gen_of d.params t) fields) (self d);
            build = (fun a -> Expr.Record (List.combine (List.map fst fields) a));
            run = (fun a -> Value.Record (List.combine (List.map fst fields) a)) }
          :: List.map (fun (f, t) ->
              { cname = "." ^ f; scheme = arrow (self d) (gen_of d.params t);
                build = (fun a -> Expr.Field (List.hd a, f));
                run = (function [ Value.Record fs ] -> List.assoc f fs | _ -> raise Components.Undefined) })
            fields
      | _ -> []) decls

(* ---------------------------------------------------------------- constants *)

let rec subvalues (v : Value.t) : Value.t list =
  v :: (match v with
      | Value.List xs | Value.Tuple xs | Value.Con (_, xs) -> List.concat_map subvalues xs
      | Value.Array xs -> List.concat_map subvalues (Array.to_list xs)
      | Value.Poly (_, Some x) -> subvalues x
      | Value.Record fs -> List.concat_map (fun (_, x) -> subvalues x) fs
      | Value.String s -> List.init (String.length s) (fun i -> Value.Char s.[i])
      | _ -> [])

let dedupe vs =
  List.rev (List.fold_left (fun acc v -> if List.exists (Value.equal v) acc then acc else v :: acc) [] vs)

let rec split_on hay needle =
  if needle = "" then [ hay ]
  else
    let n = String.length needle and h = String.length hay in
    let rec find i = if i + n > h then None
      else if String.sub hay i n = needle then Some i else find (i + 1) in
    match find 0 with
    | None -> [ hay ]
    | Some i -> String.sub hay 0 i :: split_on (String.sub hay (i + n) (h - i - n)) needle

(* String constants the output needs but no input supplies: the fragments
   left when every input string is cut out of every output string, cut again
   by the fragments already found. This is how "One for " and ", one for me."
   come out of two-fer's examples, and "you" out of the one with no name. *)
let string_fragments (examples : Spec.example list) =
  let outs = List.concat_map (fun ex -> List.filter_map (function
      | Value.String s -> Some s | _ -> None) (subvalues ex.Spec.out)) examples in
  let ins = List.concat_map (fun ex -> List.concat_map (fun a -> List.filter_map (function
      | Value.String s when String.length s > 0 -> Some s | _ -> None) (subvalues a)) ex.Spec.args) examples in
  let cut pieces needles =
    List.concat_map (fun p -> List.fold_left (fun acc nd -> List.concat_map (fun x -> split_on x nd) acc) [ p ] needles) pieces in
  let first = List.filter (fun s -> s <> "") (cut outs (List.sort_uniq compare ins)) in
  (* an output untouched by any cut is that example's whole answer *)
  let first = List.filter (fun f -> not (List.mem f outs) || List.length (List.filter (( = ) f) outs) >= 2) first in
  let frags = List.sort_uniq compare first in
  let second = List.filter (fun s -> s <> "") (cut outs frags) in
  let all = List.sort_uniq compare (frags @ second) in
  List.filter (fun s -> String.length s <= 60) all

(* Divisibility shows in the inputs before it shows in any output: 2000 and
     2400 share 400, 1900 and 2100 share 100. Pairwise common divisors of the
     example integers are offered as constants, read off the data rather than
     supplied for any part. *)
let inferred_divisors (spec_examples : Spec.example list) =
  let in_ints = List.sort_uniq compare (List.concat_map (fun ex -> List.concat_map (fun a ->
      List.filter_map (function Value.Int n when n > 0 && n <= 100_000 -> Some n | _ -> None)
        (subvalues a)) ex.Spec.args) spec_examples) in
  let rec gcd a b = if b = 0 then a else gcd b (a mod b) in
  let pairs = List.concat_map (fun a -> List.filter_map (fun b ->
      if a < b then (let g = gcd a b in if g > 2 && g <> a && g <> b then Some g else None) else None) in_ints) in_ints in
  (* most often shared first, then larger *)
  let counted = List.map (fun g -> (List.length (List.filter (( = ) g) pairs), g)) (List.sort_uniq compare pairs) in
  let gcds = List.map snd (List.filteri (fun i _ -> i < 4)
      (List.sort (fun (c1, g1) (c2, g2) -> if c1 <> c2 then compare c2 c1 else compare g2 g1) counted)) in
  gcds

let constants (spec_examples : Spec.example list) (target_out : ty) (decls : decl list) =
  let ints = [ 0; 1; 2; 3; 4; 5; 10; 100; 1000 ] in
  (* A value that is one example's answer is not vocabulary: offering it back
     lets the search memorize that example. Only what recurs across answers
     is offered. *)
  let recurring vs = List.filter (fun v -> List.length (List.filter (( = ) v) vs) >= 2) vs in
  let out_ints = recurring (List.filter_map (fun ex -> match ex.Spec.out with Value.Int n -> Some n | _ -> None) spec_examples) in
  let deep_ints = recurring (List.concat_map (fun ex -> List.sort_uniq compare (List.filter_map (function
      | Value.Int n when abs n <= 1000 -> Some n | _ -> None) (subvalues ex.Spec.out))) spec_examples) in
  let gcds = inferred_divisors spec_examples in
  let ints = List.sort_uniq compare (ints @ out_ints @ deep_ints @ gcds) in
  let chars = List.sort_uniq compare (List.concat_map (fun ex ->
      List.filter_map (function Value.Char c -> Some c | _ -> None)
        (subvalues ex.Spec.out @ List.concat_map subvalues ex.Spec.args)) spec_examples) in
  let chars = List.sort_uniq compare (' ' :: chars) in
  (* punctuation the inputs use, as one-character strings: "?" is how a
     question ends, and nothing else would offer it *)
  let punct = List.sort_uniq compare (List.concat_map (fun ex -> List.concat_map (fun a ->
      List.filter_map (function
          | Value.Char c when (c >= '!' && c <= '/') || (c >= ':' && c <= '@') -> Some (String.make 1 c)
          | _ -> None) (subvalues a)) ex.Spec.args) spec_examples) in
  let strings = "" :: string_fragments spec_examples @ punct in
  let strings = List.sort_uniq compare (strings
      @ recurring (List.filter_map (fun ex -> match ex.Spec.out with
          | Value.String s when String.length s <= 60 -> Some s | _ -> None) spec_examples)) in
  let ctor_consts = List.concat_map (fun d -> match d.kind with
      | Variant ctors -> List.filter_map (fun (c, args) ->
          if args = [] && d.params = [] then Some (Expr.Con (c, []), Value.Con (c, []), TCon (d.name, []))
          else None) ctors
      | Poly rows when d.params = [] -> List.filter_map (fun (tag, a) ->
          if a = None then Some (Expr.Poly (tag, None), Value.Poly (tag, None), TCon (d.name, [])) else None) rows
      | _ -> []) decls in
  let lit v t = (Expr.Lit v, v, t) in
  List.map (fun n -> lit (Value.Int n) t_int) ints
  @ [ lit (Value.Bool true) t_bool; lit (Value.Bool false) t_bool ]
  @ List.map (fun c -> lit (Value.Char c) t_char) chars
  @ List.map (fun s -> lit (Value.String s) t_string) strings
  @ ctor_consts
  @ (let _ = target_out in [])

(* The literals that occur in the examples themselves. *)
let data_constants (examples : Spec.example list) =
  let vs = List.concat_map (fun ex -> List.concat_map subvalues (ex.Spec.out :: ex.Spec.args)) examples in
  let frags = List.map (fun s -> Value.String s) (string_fragments examples) in
  let frags = frags @ List.map (fun n -> Value.Int n) (inferred_divisors examples) in
  let punct = List.sort_uniq compare (List.concat_map (fun ex -> List.concat_map (fun a ->
      List.filter_map (function
          | Value.Char c when (c >= '!' && c <= '/') || (c >= ':' && c <= '@') -> Some (Value.String (String.make 1 c))
          | _ -> None) (subvalues a)) ex.Spec.args) examples) in
  let frags = frags @ punct in
  List.map (fun v -> (Expr.Lit v, v, t_unit)) (dedupe (vs @ frags))

(* Empty containers and None at each type the search may need. *)
let empties (types : ty list) =
  List.concat_map (fun t -> match repr t with
      | TCon ("list", [ _ ]) -> [ (Expr.Lit (Value.List []), Value.List [], t) ]
      | TCon ("option", [ _ ]) -> [ (Expr.Con ("None", []), Value.Con ("None", []), t) ]
      | TCon ("unit", []) -> [ (Expr.Lit Value.Unit, Value.Unit, t) ]
      | _ -> []) types

(* Every type mentioned by the signature and its components, so the empties
   cover the element types the search will meet. *)
let rec types_in t =
  t :: (match repr t with
      | TCon (_, ts) | TTuple ts -> List.concat_map types_in ts
      | TArrow (_, a, b) -> types_in a @ types_in b
      | _ -> [])

(* ------------------------------------------------------------- enumeration *)

let rec closed (e : Expr.t) =
  match e with
  | Expr.Var _ -> false
  | Expr.Lit _ | Expr.Poly (_, None) -> true
  | Expr.Call (_, args) | Expr.Con (_, args) | Expr.Tuple args -> List.for_all closed args
  | Expr.App (f, args) -> closed f && List.for_all closed args
  | Expr.Lam _ -> false
  | Expr.Poly (_, Some a) | Expr.Field (a, _) -> closed a
  | Expr.Record fs -> List.for_all (fun (_, a) -> closed a) fs
  | Expr.If (c, a, b) -> closed c && closed a && closed b
  | Expr.Match _ | Expr.Let _ -> false

let compositions n k =
  (* all ways to write n as an ordered sum of k positive parts *)
  let rec go n k =
    if k = 0 then (if n = 0 then [ [] ] else [])
    else if n < k then []
    else List.concat_map (fun first -> List.map (fun rest -> first :: rest) (go (n - first) (k - 1)))
        (List.init (n - k + 1) (fun i -> i + 1))
  in
  go n k

let apply_at cfg (run : Value.t list -> Value.t) (args : Value.t option array list) npoints =
  Array.init npoints (fun j ->
      let vs = List.map (fun a -> a.(j)) args in
      if List.exists Option.is_none vs then None
      else
        try Eval.fuel := cfg.fuel; Some (run (List.map Option.get vs)) with
        | Components.Undefined | Eval.Stuck | Eval.Out_of_fuel | Division_by_zero
        | Invalid_argument _ | Failure _ | Not_found | Stack_overflow | Value.Not_comparable -> None)

type lambdas = {
  lam_bank : bank;
  params : (string * ty) list;
  lam_points : int array;          (* lambda point -> outer point it extends *)
}

type search = {
  data_consts : (Expr.t * Value.t * ty) list;   (* read off the examples *)
  cfg : config;
  comps : comp list;
  decls : decl list;
  consts : (Expr.t * Value.t * ty) list;
  all_types : ty list;
  mutable lambda_banks : (string * lambdas) list;
  main : bank;
  goal : (ty * Value.t array) option;    (* main context only *)
}

let fresh_name ctx base =
  let rec go i = let n = base ^ string_of_int i in
    if List.mem_assoc n ctx.vars then go (i + 1) else n in go 0

(* Sample values of a type, drawn from the main context's points. *)
let rec samples (ctx : ctx) (t : ty) =
  let vals = Array.to_list ctx.points |> List.concat_map (fun p -> List.concat_map (fun (_, v) -> subvalues v) p) in
  let fits v = match repr t, v with
    | TCon ("int", []), Value.Int _ | TCon ("char", []), Value.Char _
    | TCon ("string", []), Value.String _ | TCon ("bool", []), Value.Bool _
    | TCon ("float", []), Value.Float _ | TCon ("int64", []), Value.Int64 _ -> true
    | TCon ("list", _), Value.List _ | TTuple _, Value.Tuple _ -> true
    | TCon ("option", _), Value.Con (("None" | "Some"), _) -> true
    | TCon (n, _), Value.Con (c, _) -> n <> "option" && n <> "result" && c <> "None" && c <> "Some" && c <> "Ok" && c <> "Error"
    | TCon (_, _), Value.Poly _ -> true
    | TCon (_, _), Value.Record _ -> true
    | TVar _, _ -> true
    | _ -> false in
  let vs = dedupe (List.filter fits vals) in
  let vs = match repr t with
    | TCon ("int", []) -> dedupe (vs @ [ Value.Int 0; Value.Int 1 ])
    | TCon ("bool", []) -> [ Value.Bool true; Value.Bool false ]
    | _ -> vs in
  let vs = List.filteri (fun i _ -> i < 6) vs in
  (* A tuple the examples never hold whole is still made of parts they do:
     pairs for List.combine's elements come from samples of each side. *)
  match repr t, vs with
  | TTuple ts, [] ->
      let parts = List.map (fun t -> List.filteri (fun i _ -> i < 3) (samples ctx t)) ts in
      List.filteri (fun i _ -> i < 6) (List.map (fun vs -> Value.Tuple vs) (product parts))
  | _ -> vs

and product = function
  | [] -> [ [] ]
  | xs :: rest -> List.concat_map (fun x -> List.map (fun r -> x :: r) (product rest)) xs

(* The context a lambda body is enumerated in. *)
let lambda_ctx (outer : ctx) (ptys : ty list) =
  let names = List.mapi (fun i _ -> "p" ^ string_of_int i) ptys in
  let names = List.map (fun n -> fresh_name outer n) names in
  let tuples = product (List.map (samples outer) ptys) in
  let tuples = List.filteri (fun i _ -> i < 12) tuples in
  let outer_ids = List.filteri (fun i _ -> i < 4) (List.init (Array.length outer.points) Fun.id) in
  let pts = List.concat_map (fun oi -> List.map (fun tup -> (oi, tup)) tuples) outer_ids in
  let points = Array.of_list (List.map (fun (oi, tup) ->
      List.combine names tup @ outer.points.(oi)) pts) in
  let back = Array.of_list (List.map fst pts) in
  ({ vars = List.combine names ptys @ outer.vars; points }, names, back)

(* Description length of a literal, as extra size. 0, 1, true, false, empty
   containers and constructors are free; a value read off the examples is
   cheap; any other number is a choice nobody justified and costs more. This
   is what keeps `List.nth_opt x 3` from beating `List.nth_opt (List.rev x) 0`
   on a single example of length four. *)
let literal_cost s (v : Value.t) =
  let from_data = List.exists (fun (_, v', _) -> Value.equal v v') s.data_consts in
  match v with
  | Value.Int (0 | 1) | Value.Bool _ | Value.List [] | Value.Unit | Value.Con (_, []) | Value.Poly (_, None) -> 0
  | Value.Char ' ' | Value.String "" -> 0
  | _ when from_data -> 1
  | Value.Int 2 -> 1
  | Value.Int n when abs n <= 10 -> 2
  | Value.Int _ -> 3
  | _ -> 1

let pending : (bank * cand) list ref = ref []

let rec seed s b =
  let ctx = b.ctx in
  int_vars := List.filter_map (fun (x, t) -> if key t = "int" then Some x else None) ctx.vars;
  all_vars := ctx.vars;
  List.iter (fun (x, t) ->
      let vec = Array.map (fun p -> List.assoc_opt x p) ctx.points in
      ignore (add s.cfg b { expr = Expr.Var x; size = 1; ty = t; vec })) ctx.vars;
  List.iter (fun (e, v, t) ->
      let size = 1 + literal_cost s v in
      if size = 1 then
        ignore (add s.cfg b { expr = e; size; ty = t; vec = Array.map (fun _ -> Some v) ctx.points })
      else pending := (b, { expr = e; size; ty = t; vec = Array.map (fun _ -> Some v) ctx.points }) :: !pending)
    (s.consts @ empties s.all_types)

(* Grow bank b by one size level. *)
and grow s b n ~lambda_depth =
  let npoints = Array.length b.ctx.points in
  let now, later = List.partition (fun (b', c) -> b' == b && c.size = n) !pending in
  pending := later;
  List.iter (fun (_, c) -> ignore (add s.cfg b c)) (List.rev now);
  let check c =
    if add s.cfg b c then
      match s.goal with
      | Some (gty, outs) when b == s.main && key c.ty = key gty ->
          if Array.for_all2 (fun v o -> match v with Some v -> Value.equal v o | None -> false) c.vec outs
          then raise (Found c.expr)
      | _ -> ()
  in
  (* Components and constructors, args first-order first, functions last. *)
  List.iter (fun comp ->
      let args, res = unarrow comp.scheme in
      let k = List.length args in
      if k > 0 && k < n then begin
        let indexed = List.mapi (fun i (_, t) -> (i, t)) args in
        let fo = List.filter (fun (_, t) -> match repr t with TArrow _ -> false | _ -> true) indexed in
        let ho = List.filter (fun (_, t) -> match repr t with TArrow _ -> true | _ -> false) indexed in
        let order = fo @ ho in
        List.iter (fun sizes ->
            let rec pick subst chosen = function
              | [] ->
                  let rty = subst_apply subst res in
                  (* A component applied to constants alone is a constant
                     nobody supplied: `succ 400` invents 401. Constructors
                     of constants are values, and stay. *)
                  let invented = chosen <> [] && is_component comp
                                 && List.for_all (fun (_, e, _) -> closed e) chosen in
                  (* under the strict reading a comparison may not look at a
                     rigid 'a: that is what makes the free theorem hold *)
                  let compares_var = s.cfg.strict && List.mem comp.cname comparing
                                     && (match List.assoc_opt 0 subst with
                                         | Some t -> Parametric.has_var t | None -> false) in
                  (* x = 2, x = "Bob": a parameter compared for equality with
                     a value is a lookup of that example, not a rule. Chars are
                     the exception: c = ' ' is how a char predicate is said. *)
                  let memorizes = (comp.cname = "=" || comp.cname = "<>")
                                  && (match chosen with
                                      | [ (_, e1, _); (_, e2, _) ] ->
                                          let lit = function
                                            | Expr.Lit (Value.Int (0 | 1)) | Expr.Lit (Value.String "") -> false
                                            | Expr.Lit (Value.Int _ | Value.String _) -> true
                                            | _ -> false in
                                          let var = function Expr.Var _ -> true | _ -> false in
                                          (var e1 && lit e2) || (lit e1 && var e2)
                                      | _ -> false) in
                  let invented = invented || compares_var || memorizes in
                  if not (has_gen rty) && not invented then begin
                    let chosen = List.sort (fun (i, _, _) (j, _, _) -> compare i j) chosen in
                    let exprs = List.map (fun (_, e, _) -> e) chosen in
                    let vecs = List.map (fun (_, _, v) -> v) chosen in
                    let size = n in
                    let vec = apply_at s.cfg comp.run vecs npoints in
                    check { expr = comp.build exprs; size; ty = rty; vec }
                  end
              | ((i, sch), sz) :: rest ->
                  (* a function parameter of the right type can go here as is *)
                  (match repr sch with
                   | TArrow _ ->
                       List.iter (fun (cty, cands) ->
                           match mtch subst sch cty with
                           | None -> ()
                           | Some subst' ->
                               List.iter (fun c -> match c.expr with
                                   | Expr.Var _ -> pick subst' ((i, c.expr, c.vec) :: chosen) rest
                                   | _ -> ()) cands)
                         (if sz = 1 then at b 1 else [])
                   | _ -> ());
                  (match repr sch with
                   | TArrow _ when String.length comp.cname > 5 && String.sub comp.cname 0 5 = "__app" -> ()
                   | TArrow _ when lambda_depth > 0 ->
                       let pargs, pres = unarrow sch in
                       let ptys = List.map (fun (_, t) -> subst_apply subst t) pargs in
                       if List.for_all (fun t -> not (has_gen t)) ptys then begin
                         let lb = lambdas_for s b ptys in
                         let lams = lambda_level s lb (sz - 1) ~lambda_depth in
                         List.iter (fun (lty, cands) ->
                             match mtch subst pres lty with
                             | None -> ()
                             | Some subst' ->
                                 List.iter (fun lc ->
                                     let lam = Expr.Lam (List.map fst lb.params, lc.expr) in
                                     let vec = Array.init npoints (fun j ->
                                         Some (Value.Fun (fun v ->
                                             let rec close names vals = match names with
                                               | [] -> (match Eval.run ~budget:!Eval.fuel
                                                               (List.combine (List.map fst lb.params) (List.rev vals) @ b.ctx.points.(j)) lc.expr with
                                                        | Some r -> r | None -> raise Eval.Stuck)
                                               | _ :: more -> Value.Fun (fun w -> close more (w :: vals))
                                             in
                                             match lb.params with
                                             | [ _ ] -> close [] [ v ]
                                             | _ :: more -> close more [ v ]
                                             | [] -> raise Eval.Stuck))) in
                                     pick subst' ((i, lam, vec) :: chosen) rest) cands) lams
                       end
                   | TArrow _ -> ()
                   | _ ->
                       List.iter (fun (cty, cands) ->
                           match mtch subst sch cty with
                           | None -> ()
                           | Some subst' ->
                               List.iter (fun c -> pick subst' ((i, c.expr, c.vec) :: chosen) rest) cands)
                         (at b sz))
            in
            pick [] [] (List.combine order sizes))
          (compositions (n - 1) k)
      end) s.comps;
  (* if c then a else b *)
  if n >= 4 then
    List.iter (fun sizes -> match sizes with
        | [ sc; sa; sb ] ->
            List.iter (fun (ct, cs) -> if key ct = "bool" then
                List.iter (fun c ->
                    List.iter (fun (at_, as_) ->
                        List.iter (fun (bt, bs) -> if key at_ = key bt then
                            List.iter (fun a -> List.iter (fun bb ->
                                let vec = Array.init npoints (fun j -> match c.vec.(j) with
                                    | Some (Value.Bool true) -> a.vec.(j)
                                    | Some (Value.Bool false) -> bb.vec.(j)
                                    | _ -> None) in
                                check { expr = Expr.If (c.expr, a.expr, bb.expr); size = n; ty = at_; vec })
                                bs) as_) (at b sb)) (at b sa)) cs) (at b sc)
        | _ -> ()) (compositions (n - 1) 3)

and lambdas_for s (outer : bank) ptys =
  let k = key (TTuple ptys) ^ "@" ^ string_of_int (Hashtbl.hash (List.map fst outer.ctx.vars)) in
  match List.assoc_opt k s.lambda_banks with
  | Some lb -> lb
  | None ->
      let ctx, names, back = lambda_ctx outer.ctx ptys in
      let lb = { lam_bank = new_bank ctx; params = List.combine names ptys; lam_points = back } in
      seed s lb.lam_bank;
      s.lambda_banks <- (k, lb) :: s.lambda_banks;
      lb

and lambda_level s lb n ~lambda_depth =
  if n < 1 || n > s.cfg.max_lambda_size then []
  else begin
    (* grow lazily up to n *)
    let rec ensure m =
      if m > 1 && not (Hashtbl.mem lb.lam_bank.by_size m) then begin
        ensure (m - 1);
        ignore (level lb.lam_bank m);
        grow s lb.lam_bank m ~lambda_depth:(lambda_depth - 1)
      end in
    ensure n;
    at lb.lam_bank n
  end

(* ------------------------------------------------------------------ driver *)

type result =
  | Solved of Expr.t * int          (* term, terms considered *)
  | Gave_up of string

let solve ?(cfg = default) ~(decls : decl list) ~(params : (string * ty) list) ~(out_ty : ty)
    (examples : Spec.example list) =
  total := 0;
  Value.declare_variant [];
  List.iter (fun d -> match d.kind with
      | Variant ctors -> Value.declare_variant (List.map (fun (c, a) -> (c, List.length a)) ctors)
      | _ -> ()) decls;
  let points = Array.of_list (List.map (fun ex -> List.combine (List.map fst params) ex.Spec.args) examples) in
  let ctx = { vars = params; points } in
  let outs = Array.of_list (List.map (fun ex -> ex.Spec.out) examples) in
  let comps = List.map of_component Components.all @ ctor_comps decls in
  let all_types = List.sort_uniq (fun a b -> compare (key a) (key b))
      (types_in out_ty @ List.concat_map (fun (_, t) -> types_in t) params
       @ [ t_list t_int; t_list t_char; t_list t_string ]) in
  let s = { data_consts = []; cfg; comps; decls; consts = constants examples out_ty decls; all_types;
            lambda_banks = []; main = new_bank ctx; goal = Some (out_ty, outs) } in
  try
    (* size-1 terms can already be the answer *)
    List.iter (fun c -> ignore c) [];
    seed s s.main;
    Hashtbl.iter (fun _ _ -> ()) s.main.seen;
    List.iter (fun (_, _, cs) -> List.iter (fun c ->
        if key c.ty = key out_ty
        && Array.for_all2 (fun v o -> match v with Some v -> Value.equal v o | None -> false) c.vec outs
        then raise (Found c.expr)) !cs) !(level s.main 1);
    for n = 2 to cfg.max_size do
      ignore (level s.main n);
      grow s s.main n ~lambda_depth:2
    done;
    Gave_up (Printf.sprintf "no term up to size %d among %d considered" cfg.max_size !total)
  with
  | Found e -> Solved (e, !total)
  | Exhausted -> Gave_up (Printf.sprintf "search bound reached: %d terms considered" !total)

(* ------------------------------------------------- banks for the deducer *)

(* A bank of every distinct term up to max_size in a context, with no goal:
   the leaves the deductive layer looks answers up in. Growth stops quietly at
   the bank's bound; what was built is kept. *)
let build_search ?(cfg = default) ~(decls : decl list) ~(examples : Spec.example list)
    ~(ctx : ctx) ~(types : ty list) max_size =
  List.iter (fun d -> match d.kind with
      | Variant ctors -> Value.declare_variant (List.map (fun (c, a) -> (c, List.length a)) ctors)
      | _ -> ()) decls;
  (* Only components whose base types the part ever mentions: a string
     operation can never apply to a problem about 'a lists, and offering it
     only fills the banks. int and bool are always in reach (lengths, tests). *)
  let mentioned = List.concat_map types_in (types @ List.map snd ctx.vars)
                  @ List.concat_map (fun d -> match d.kind with
                      | Variant cs -> List.concat_map (fun (_, ts) -> List.concat_map types_in ts) cs
                      | Record fs -> List.concat_map (fun (_, t) -> types_in t) fs
                      | Alias t -> types_in t | _ -> []) decls in
  let bases = List.sort_uniq compare ("int" :: "bool" :: "list" :: "option" :: List.filter_map (fun t ->
      match repr t with TCon (n, _) -> Some n | _ -> None) mentioned) in
  let in_reach (c : comp) =
    let rec ok t = match repr t with
      | TCon (n, ts) -> List.mem n bases && List.for_all ok ts
      | TTuple ts -> List.for_all ok ts
      | TArrow (_, a, b) -> ok a && ok b
      | _ -> true in
    ok c.scheme in
  let comps = List.filter in_reach (List.map of_component Components.all) @ ctor_comps decls @ sibling_comps () in
  let all_types = List.sort_uniq (fun a b -> compare (key a) (key b))
      (List.concat_map types_in types @ List.concat_map (fun (_, t) -> types_in t) ctx.vars
       @ [ t_list t_int; t_list t_char; t_list t_string ]) in
  let consts = constants examples t_unit decls in
  let s = { data_consts = data_constants examples; cfg; comps; decls; consts; all_types;
            lambda_banks = []; main = new_bank ctx; goal = None } in
  (try
     seed s s.main;
     for n = 2 to max_size do
       ignore (level s.main n);
       grow s s.main n ~lambda_depth:1
     done
   with Exhausted -> ());
  s

(* Every term of a type in a bank, smallest first. *)
let terms_of b t =
  let k = key t in
  let sizes = List.sort compare (Hashtbl.fold (fun n _ acc -> n :: acc) b.by_size []) in
  List.concat_map (fun n -> List.concat_map (fun (t', cs) -> if key t' = k then cs else []) (at b n)) sizes

(* Every term in a bank, smallest first, with its type. *)
let all_terms b =
  let sizes = List.sort compare (Hashtbl.fold (fun n _ acc -> n :: acc) b.by_size []) in
  List.concat_map (fun n -> List.concat_map (fun (_, cs) -> cs) (at b n)) sizes
