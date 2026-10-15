(* Terms to Prolog: the same derivation, delivered in another language.
 *
 * The search never produces OCaml; it produces terms over a vocabulary. What
 * makes the writer an OCaml writer is only the last mile (Lower_ocaml) and the
 * check that runs it. This is the other last mile: a function of n arguments
 * becomes a predicate of n+1, its result in the last; a nested call becomes a
 * sequence of goals through fresh variables; a lambda becomes a yall lambda
 * sharing its free variables; each Stdlib component maps to a SWI-Prolog
 * builtin or to one of a few generic definitions in `prelude`.
 *
 * Representation, fixed once: integers as integers, strings as SWI strings,
 * chars as one-character atoms, booleans as the atoms true and false, lists as
 * lists, constructors as lowercase functors (none, some(X), ok(X), error(E)),
 * tuples as t(...), records as r(...) in field order. *)

open Expr

exception Unsupported of string

let atom_name c =
  if c = "" then "c_" else
  let c = String.uncapitalize_ascii c in
  String.map (fun ch -> if ch = '#' then 'x' else ch) c

let rec term (v : Value.t) =
  match v with
  | Value.Int n -> string_of_int n
  | Value.Int64 n -> Int64.to_string n
  | Value.Float f -> Printf.sprintf "%.17g" f
  | Value.Bool b -> string_of_bool b
  | Value.Char c -> "'" ^ (if c = '\'' then "\\'" else if c = '\\' then "\\\\" else String.make 1 c) ^ "'"
  | Value.String s -> "\"" ^ String.concat "\\\"" (String.split_on_char '"' (String.concat "\\\\" (String.split_on_char '\\' s))) ^ "\""
  | Value.Unit -> "unit"
  | Value.List l -> "[" ^ String.concat "," (List.map term l) ^ "]"
  | Value.Array a -> "[" ^ String.concat "," (List.map term (Array.to_list a)) ^ "]"
  | Value.Tuple l -> "t(" ^ String.concat "," (List.map term l) ^ ")"
  | Value.Con (c, []) -> atom_name c
  | Value.Con (c, args) -> atom_name c ^ "(" ^ String.concat "," (List.map term args) ^ ")"
  | Value.Poly (c, None) -> atom_name c
  | Value.Poly (c, Some a) -> atom_name c ^ "(" ^ term a ^ ")"
  | Value.Record fs -> "r(" ^ String.concat "," (List.map (fun (_, v) -> term v) fs) ^ ")"
  | Value.Fun _ -> raise (Unsupported "a function value")

(* Generic definitions for Stdlib functions SWI has no single builtin for.
   Each mirrors the OCaml function exactly, including where it fails. *)
let prelude = {|:- use_module(library(yall)).
:- use_module(library(apply)).
:- use_module(library(lists)).
gw_bool(G, R) :- ( call(G) -> R = true ; R = false ).
gw_cmp(Op, A, B, R) :- ( compare(O, A, B), gw_op(Op, O) -> R = true ; R = false ).
gw_op(=, =). gw_op(<>, <). gw_op(<>, >). gw_op(<, <). gw_op(>, >).
gw_op(=<, <). gw_op(=<, =). gw_op(>=, >). gw_op(>=, =).
gw_compare(A, B, R) :- compare(O, A, B), ( O = (<) -> R = -1 ; O = (=) -> R = 0 ; R = 1 ).
gw_max(A, B, R) :- ( compare(<, A, B) -> R = B ; R = A ).
gw_min(A, B, R) :- ( compare(>, A, B) -> R = B ; R = A ).
gw_nth_opt(L, N, R) :- N >= 0, ( nth0(N, L, X) -> R = some(X) ; R = none ).
gw_option_value(some(X), _, X) :- !.
gw_option_value(none, D, D).
gw_option_map(F, some(X), some(Y)) :- !, call(F, X, Y).
gw_option_map(_, none, none).
gw_is_some(O, R) :- ( O = some(_) -> R = true ; R = false ).
gw_hd([X|_], X).
gw_tl([_|T], T).
gw_init(N, F, L) :- N >= 0, N1 is N - 1, ( N1 < 0 -> L = [] ; numlist(0, N1, Is), maplist(F, Is, L) ).
gw_mapi(F, L, R) :- length(L, N), N1 is N - 1, ( N1 < 0 -> R = [] ; numlist(0, N1, Is), maplist(F, Is, L, R) ).
gw_filter(F, L, R) :- include([X]>>call(F, X, true), L, R).
gw_filter_map(F, L, R) :- foldl([X, A0, A]>>(call(F, X, O), ( O = some(Y) -> append(A0, [Y], A) ; A = A0 )), L, [], R).
gw_concat_map(F, L, R) :- maplist(F, L, Ls), append(Ls, R).
gw_fold_left(F, Z, L, R) :- foldl([X, A0, A]>>call(F, A0, X, A), L, Z, R).
gw_fold_right(F, L, Z, R) :- reverse(L, RL), foldl([X, A0, A]>>call(F, X, A0, A), RL, Z, R).
gw_exists(F, L, R) :- ( member(X, L), call(F, X, true) -> R = true ; R = false ).
gw_for_all(F, L, R) :- ( forall(member(X, L), call(F, X, true)) -> R = true ; R = false ).
gw_mem(X, L, R) :- ( memberchk(X, L) -> R = true ; R = false ).
gw_find_opt(F, L, R) :- ( member(X, L), call(F, X, true) -> R = some(X) ; R = none ).
gw_assoc_opt(K, L, R) :- ( memberchk(t(K, V), L) -> R = some(V) ; R = none ).
gw_combine([], [], []).
gw_combine([X|Xs], [Y|Ys], [t(X, Y)|R]) :- gw_combine(Xs, Ys, R).
gw_split(L, t(A, B)) :- maplist([t(X, Y), X, Y]>>true, L, A, B).
gw_sort(L, R) :- msort(L, R).
gw_sort_uniq(L, R) :- sort(L, R).
gw_concat(Ls, R) :- append(Ls, R).
gw_string_get(S, I, C) :- I >= 0, string_length(S, N), I < N, sub_atom(S, I, 1, _, C).
gw_string_sub(S, I, N, R) :- I >= 0, N >= 0, string_length(S, L), I + N =< L, sub_string(S, I, N, _, R).
gw_string_make(N, C, R) :- N >= 0, length(L, N), maplist(=(C), L), string_chars(R, L).
gw_string_concat(Sep, L, R) :- atomic_list_concat(L, Sep, A), atom_string(A, R).
gw_string_trim(S, R) :- normalize_space(string(_), S), split_string(S, "", " \t\n\r", [R]).
gw_split_on_char(C, S, R) :- atom_string(C, CS), split_string(S, CS, "", R).
gw_contains(S, C, R) :- ( sub_atom(S, _, 1, _, C) -> R = true ; R = false ).
gw_string_map(F, S, R) :- string_chars(S, Cs), maplist(F, Cs, Ds), string_chars(R, Ds).
gw_string_init(N, F, R) :- gw_init(N, F, Cs), string_chars(R, Cs).
gw_capitalize(S, R) :- ( string_chars(S, [C|Cs]) -> upcase_atom(C, U), string_chars(R, [U|Cs]) ; R = S ).
gw_int_of_string_opt(S, R) :- ( catch(number_string(N, S), _, fail), integer(N) -> R = some(N) ; R = none ).
gw_char_upper(C, U) :- ( char_type(C, lower(Up)) -> U = Up ; U = C ).
gw_char_lower(C, L) :- ( char_type(C, upper(Lo)) -> L = Lo ; L = C ).
gw_chr(N, C) :- N >= 0, N =< 255, char_code(C, N).
gw_string_exists(F, S, R) :- string_chars(S, Cs), gw_exists(F, Cs, R).
gw_string_for_all(F, S, R) :- string_chars(S, Cs), gw_for_all(F, Cs, R).
gw_filteri(F, L, R) :- length(L, N), N1 is N - 1, ( N1 < 0 -> R = [] ; numlist(0, N1, Is),
    foldl([I, X, A0, A]>>(call(F, I, X, true) -> append(A0, [X], A) ; A = A0), Is, L, [], R) ).
gw_find_map(F, L, R) :- ( member(X, L), call(F, X, some(Y)) -> R = some(Y) ; R = none ).
gw_div(A, B, R) :- B =\= 0, R is A // B.
gw_mod(A, B, R) :- B =\= 0, R is A rem B.
|}

type env = {
  vars : (string * string) list;     (* OCaml variable -> Prolog variable *)
  n : int ref;                       (* shared by every copy of the env *)
  self : string;
  arity : int;
}

let fresh env = incr env.n; "V" ^ string_of_int !(env.n)

let var env x = match List.assoc_opt x env.vars with
  | Some v -> v
  | None -> raise (Unsupported ("unbound " ^ x))

(* The goals that compute a component's result into r. *)
let call_goal name args r =
  let a = Array.of_list args in
  let g fmt = fmt in
  match name, args with
  | ("+" | "-" | "*"), [ x; y ] -> Printf.sprintf "%s is %s %s %s" r x name y
  | "/", [ x; y ] -> Printf.sprintf "gw_div(%s, %s, %s)" x y r
  | "mod", [ x; y ] -> Printf.sprintf "gw_mod(%s, %s, %s)" x y r
  | "abs", [ x ] -> Printf.sprintf "%s is abs(%s)" r x
  | "~-", [ x ] -> Printf.sprintf "%s is -(%s)" r x
  | "succ", [ x ] -> Printf.sprintf "%s is %s + 1" r x
  | "pred", [ x ] -> Printf.sprintf "%s is %s - 1" r x
  | ("max" | "min"), [ x; y ] -> Printf.sprintf "gw_%s(%s, %s, %s)" name x y r
  | "compare", [ x; y ] -> Printf.sprintf "gw_compare(%s, %s, %s)" x y r
  | "=", [ x; y ] -> Printf.sprintf "gw_cmp(=, %s, %s, %s)" x y r
  | "<>", [ x; y ] -> Printf.sprintf "gw_cmp(<>, %s, %s, %s)" x y r
  | "<", [ x; y ] -> Printf.sprintf "gw_cmp(<, %s, %s, %s)" x y r
  | ">", [ x; y ] -> Printf.sprintf "gw_cmp(>, %s, %s, %s)" x y r
  | "<=", [ x; y ] -> Printf.sprintf "gw_cmp(=<, %s, %s, %s)" x y r
  | ">=", [ x; y ] -> Printf.sprintf "gw_cmp(>=, %s, %s, %s)" x y r
  | "&&", [ x; y ] -> Printf.sprintf "( %s == true -> %s = %s ; %s = false )" x r y r
  | "||", [ x; y ] -> Printf.sprintf "( %s == true -> %s = true ; %s = %s )" x r r y
  | "not", [ x ] -> Printf.sprintf "( %s == true -> %s = false ; %s = true )" x r r
  | ("+." | "-." | "*." | "/."), [ x; y ] ->
      Printf.sprintf "%s is %s %s %s" r x (String.sub name 0 1) y
  | "**", [ x; y ] -> Printf.sprintf "%s is %s ** %s" r x y
  | "sqrt", [ x ] -> Printf.sprintf "%s is sqrt(%s)" r x
  | "float_of_int", [ x ] -> Printf.sprintf "%s is float(%s)" r x
  | "int_of_float", [ x ] -> Printf.sprintf "%s is truncate(%s)" r x
  | ("Int64.of_int" | "Int64.to_int"), [ x ] -> Printf.sprintf "%s = %s" r x
  | "^", [ x; y ] -> Printf.sprintf "string_concat(%s, %s, %s)" x y r
  | "String.length", [ x ] -> Printf.sprintf "string_length(%s, %s)" x r
  | "String.get", [ s; i ] -> Printf.sprintf "gw_string_get(%s, %s, %s)" s i r
  | "String.sub", [ s; i; n ] -> Printf.sprintf "gw_string_sub(%s, %s, %s, %s)" s i n r
  | "String.make", [ n; c ] -> Printf.sprintf "gw_string_make(%s, %s, %s)" n c r
  | "String.concat", [ sep; l ] -> Printf.sprintf "gw_string_concat(%s, %s, %s)" sep l r
  | "String.uppercase_ascii", [ s ] -> Printf.sprintf "string_upper(%s, %s)" s r
  | "String.lowercase_ascii", [ s ] -> Printf.sprintf "string_lower(%s, %s)" s r
  | "String.capitalize_ascii", [ s ] -> Printf.sprintf "gw_capitalize(%s, %s)" s r
  | "String.trim", [ s ] -> Printf.sprintf "gw_string_trim(%s, %s)" s r
  | "String.split_on_char", [ c; s ] -> Printf.sprintf "gw_split_on_char(%s, %s, %s)" c s r
  | "String.contains", [ s; c ] -> Printf.sprintf "gw_contains(%s, %s, %s)" s c r
  | "String.map", [ f; s ] -> Printf.sprintf "gw_string_map(%s, %s, %s)" f s r
  | "String.init", [ n; f ] -> Printf.sprintf "gw_string_init(%s, %s, %s)" n f r
  | "String.exists", [ f; s ] -> Printf.sprintf "gw_string_exists(%s, %s, %s)" f s r
  | "String.for_all", [ f; s ] -> Printf.sprintf "gw_string_for_all(%s, %s, %s)" f s r
  | "String.starts_with", [ p; s ] -> Printf.sprintf "gw_bool(string_concat(%s, _, %s), %s)" p s r
  | "String.ends_with", [ p; s ] -> Printf.sprintf "gw_bool(string_concat(_, %s, %s), %s)" p s r
  | "String.index_opt", [ s; c ] -> Printf.sprintf "( sub_atom(%s, I0, 1, _, %s) -> %s = some(I0) ; %s = none )" s c r r
  | "List.filteri", [ f; l ] -> Printf.sprintf "gw_filteri(%s, %s, %s)" f l r
  | "List.find_map", [ f; l ] -> Printf.sprintf "gw_find_map(%s, %s, %s)" f l r
  | "List.partition", [ f; l ] -> Printf.sprintf "( partition([X]>>call(%s, X, true), %s, Y, N), %s = t(Y, N) )" f l r
  | "string_of_int", [ x ] -> Printf.sprintf "number_string(%s, %s)" x r
  | "int_of_string_opt", [ s ] -> Printf.sprintf "gw_int_of_string_opt(%s, %s)" s r
  | "explode", [ s ] -> Printf.sprintf "string_chars(%s, %s)" s r
  | "implode", [ l ] -> Printf.sprintf "string_chars(%s, %s)" r l
  | "String.of_char", [ c ] -> Printf.sprintf "atom_string(%s, %s)" c r
  | "Char.code", [ c ] -> Printf.sprintf "char_code(%s, %s)" c r
  | "Char.chr", [ n ] -> Printf.sprintf "gw_chr(%s, %s)" n r
  | "Char.uppercase_ascii", [ c ] -> Printf.sprintf "gw_char_upper(%s, %s)" c r
  | "Char.lowercase_ascii", [ c ] -> Printf.sprintf "gw_char_lower(%s, %s)" c r
  | "::", [ x; l ] -> Printf.sprintf "%s = [%s|%s]" r x l
  | "@", [ x; y ] -> Printf.sprintf "append(%s, %s, %s)" x y r
  | "List.length", [ l ] -> Printf.sprintf "length(%s, %s)" l r
  | "List.rev", [ l ] -> Printf.sprintf "reverse(%s, %s)" l r
  | "List.hd", [ l ] -> Printf.sprintf "gw_hd(%s, %s)" l r
  | "List.tl", [ l ] -> Printf.sprintf "gw_tl(%s, %s)" l r
  | "List.nth", [ l; n ] -> Printf.sprintf "( %s >= 0, nth0(%s, %s, %s) )" n n l r
  | "List.nth_opt", [ l; n ] -> Printf.sprintf "gw_nth_opt(%s, %s, %s)" l n r
  | "List.map", [ f; l ] -> Printf.sprintf "maplist(%s, %s, %s)" f l r
  | "List.mapi", [ f; l ] -> Printf.sprintf "gw_mapi(%s, %s, %s)" f l r
  | "List.filter", [ f; l ] -> Printf.sprintf "gw_filter(%s, %s, %s)" f l r
  | "List.filter_map", [ f; l ] -> Printf.sprintf "gw_filter_map(%s, %s, %s)" f l r
  | "List.concat_map", [ f; l ] -> Printf.sprintf "gw_concat_map(%s, %s, %s)" f l r
  | "List.fold_left", [ f; z; l ] -> Printf.sprintf "gw_fold_left(%s, %s, %s, %s)" f z l r
  | "List.fold_right", [ f; l; z ] -> Printf.sprintf "gw_fold_right(%s, %s, %s, %s)" f l z r
  | "List.exists", [ f; l ] -> Printf.sprintf "gw_exists(%s, %s, %s)" f l r
  | "List.for_all", [ f; l ] -> Printf.sprintf "gw_for_all(%s, %s, %s)" f l r
  | "List.mem", [ x; l ] -> Printf.sprintf "gw_mem(%s, %s, %s)" x l r
  | "List.concat", [ l ] -> Printf.sprintf "gw_concat(%s, %s)" l r
  | "List.init", [ n; f ] -> Printf.sprintf "gw_init(%s, %s, %s)" n f r
  | "List.sort", [ l ] -> Printf.sprintf "gw_sort(%s, %s)" l r
  | "List.sort_uniq", [ l ] -> Printf.sprintf "gw_sort_uniq(%s, %s)" l r
  | "List.assoc_opt", [ k; l ] -> Printf.sprintf "gw_assoc_opt(%s, %s, %s)" k l r
  | "List.find_opt", [ f; l ] -> Printf.sprintf "gw_find_opt(%s, %s, %s)" f l r
  | "List.combine", [ x; y ] -> Printf.sprintf "gw_combine(%s, %s, %s)" x y r
  | "List.split", [ l ] -> Printf.sprintf "gw_split(%s, %s)" l r
  | "Option.value", [ o; d ] -> Printf.sprintf "gw_option_value(%s, %s, %s)" o d r
  | "Option.map", [ f; o ] -> Printf.sprintf "gw_option_map(%s, %s, %s)" f o r
  | "Option.is_some", [ o ] -> Printf.sprintf "gw_is_some(%s, %s)" o r
  | "fst", [ p ] -> Printf.sprintf "%s = t(%s, _)" p r
  | "snd", [ p ] -> Printf.sprintf "%s = t(_, %s)" p r
  | ("Array.to_list" | "Array.of_list"), [ x ] -> Printf.sprintf "%s = %s" r x
  | "Array.length", [ x ] -> Printf.sprintf "length(%s, %s)" x r
  | "Array.get", [ x; i ] -> Printf.sprintf "( %s >= 0, nth0(%s, %s, %s) )" i i x r
  | _ when Hashtbl.mem Components.siblings name ->
      Printf.sprintf "gw_%s(%s)" name (String.concat ", " (args @ [ r ]))
  | _ -> ignore (a, g); raise (Unsupported ("component " ^ name))

let rec pat env (p : pat) : string * env =
  match p with
  | PVar x -> let v = fresh env in (v, { env with vars = (x, v) :: env.vars })
  | PWild -> ("_", env)
  | PNil -> ("[]", env)
  | PCons (h, t) ->
      let h', env = pat env h in let t', env = pat env t in ("[" ^ h' ^ "|" ^ t' ^ "]", env)
  | PCon (c, []) -> (atom_name c, env)
  | PCon (c, ps) ->
      let ss, env = List.fold_left (fun (acc, env) p -> let s, env = pat env p in (acc @ [ s ], env)) ([], env) ps in
      (atom_name c ^ "(" ^ String.concat "," ss ^ ")", env)
  | PPoly (c, None) -> (atom_name c, env)
  | PPoly (c, Some p) -> let s, env = pat env p in (atom_name c ^ "(" ^ s ^ ")", env)
  | PTuple ps ->
      let ss, env = List.fold_left (fun (acc, env) p -> let s, env = pat env p in (acc @ [ s ], env)) ([], env) ps in
      ("t(" ^ String.concat "," ss ^ ")", env)
  | PLit v -> (term v, env)

(* Goals computing e, and the Prolog term holding its value. *)
let rec expr env (e : Expr.t) : string list * string =
  match e with
  | Var x -> ([], var env x)
  | Lit v -> ([], term v)
  | Call ("&&", [ a; b ]) ->
      (* OCaml does not evaluate b when a is false; neither may Prolog *)
      let ga, ra = expr env a and gb, rb = expr env b in
      let r = fresh env in
      (ga @ [ Printf.sprintf "( %s == true -> %s ; %s = false )" ra (String.concat ", " (gb @ [ r ^ " = " ^ rb ])) r ], r)
  | Call ("||", [ a; b ]) ->
      let ga, ra = expr env a and gb, rb = expr env b in
      let r = fresh env in
      (ga @ [ Printf.sprintf "( %s == true -> %s = true ; %s )" ra r (String.concat ", " (gb @ [ r ^ " = " ^ rb ])) ], r)
  | Call (name, args) ->
      let gs, rs = args_of env args in
      let r = fresh env in
      (gs @ [ call_goal name rs r ], r)
  | App (Var f, args) when f = env.self ->
      let gs, rs = args_of env args in
      let r = fresh env in
      (gs @ [ env.self ^ "(" ^ String.concat ", " (rs @ [ r ]) ^ ")" ], r)
  | App (f, args) ->
      let gf, rf = expr env f in
      let gs, rs = args_of env args in
      let r = fresh env in
      (gf @ gs @ [ "call(" ^ String.concat ", " (rf :: rs @ [ r ]) ^ ")" ], r)
  | Lam (xs, body) ->
      let ps = List.map (fun _ -> fresh env) xs in
      let env' = { env with vars = List.combine xs ps @ env.vars } in
      let gs, r = expr env' body in
      let out = fresh env in
      let shared = List.sort_uniq compare (List.map snd env.vars) in
      (* yall: variables listed in {...}/ are shared with the clause, every
         other variable of the lambda is fresh at each call *)
      let free = if shared = [] then "" else "{" ^ String.concat "," shared ^ "}/" in
      ([], Printf.sprintf "%s[%s]>>(%s)" free (String.concat "," (ps @ [ out ]))
             (String.concat ", " (gs @ [ out ^ " = " ^ r ])))
  | Con (c, []) -> ([], atom_name c)
  | Con (c, args) -> let gs, rs = args_of env args in (gs, atom_name c ^ "(" ^ String.concat "," rs ^ ")")
  | Poly (c, None) -> ([], atom_name c)
  | Poly (c, Some a) -> let gs, r = expr env a in (gs, atom_name c ^ "(" ^ r ^ ")")
  | Tuple args -> let gs, rs = args_of env args in (gs, "t(" ^ String.concat "," rs ^ ")")
  | Record fs -> let gs, rs = args_of env (List.map snd fs) in (gs, "r(" ^ String.concat "," rs ^ ")")
  | Field _ -> raise (Unsupported "record field access")
  | If (c, a, b) ->
      let gc, rc = expr env c in
      let ga, ra = expr env a in
      let gb, rb = expr env b in
      let r = fresh env in
      (gc @ [ Printf.sprintf "( %s == true -> %s ; %s )" rc
                (String.concat ", " (ga @ [ r ^ " = " ^ ra ]))
                (String.concat ", " (gb @ [ r ^ " = " ^ rb ])) ], r)
  | Match (s, branches) ->
      let gs, rs = expr env s in
      let r = fresh env in
      let arms = List.map (fun (p, body) ->
          let ps, env' = pat env p in
          let gb, rb = expr env' body in
          Printf.sprintf "%s = %s -> %s" rs ps (String.concat ", " (gb @ [ r ^ " = " ^ rb ]))) branches in
      (gs @ [ "( " ^ String.concat " ; " arms ^ " )" ], r)
  | Let (false, x, a, b) ->
      let ga, ra = expr env a in
      let gb, rb = expr { env with vars = (x, ra) :: env.vars } b in
      (ga @ gb, rb)
  | Let (true, _, _, _) -> raise (Unsupported "local recursion")

and args_of env args =
  List.fold_left (fun (gs, rs) a -> let g, r = expr env a in (gs @ g, rs @ [ r ])) ([], []) args

let predicate_name name = "gw_" ^ name

(* One OCaml definition as one Prolog clause. *)
let definition ~name ~(params : string list) body =
  let self = predicate_name name in
  let env = { vars = []; n = ref 0; self; arity = List.length params + 1 } in
  let pvars = List.map (fun _ -> fresh env) params in
  let env = { env with vars = List.combine params pvars } in
  (* the derivation calls itself by the OCaml name *)
  let rec rename (e : Expr.t) : Expr.t = match e with
    | App (Var f, args) when f = name -> App (Var self, List.map rename args)
    | Call (n, a) -> Call (n, List.map rename a)
    | App (f, a) -> App (rename f, List.map rename a)
    | Lam (xs, b) -> Lam (xs, rename b)
    | Con (c, a) -> Con (c, List.map rename a)
    | Poly (t, Some a) -> Poly (t, Some (rename a))
    | Tuple a -> Tuple (List.map rename a)
    | Record fs -> Record (List.map (fun (f, a) -> (f, rename a)) fs)
    | Field (a, f) -> Field (rename a, f)
    | If (c, a, b) -> If (rename c, rename a, rename b)
    | Match (s, bs) -> Match (rename s, List.map (fun (p, b) -> (p, rename b)) bs)
    | Let (r, x, a, b) -> Let (r, x, rename a, rename b)
    | e -> e in
  let gs, r = expr env (rename body) in
  let out = "Out" in
  Printf.sprintf "%s(%s) :-\n    %s.\n" self (String.concat ", " (pvars @ [ out ]))
    (String.concat ",\n    " (gs @ [ out ^ " = " ^ r ]))
