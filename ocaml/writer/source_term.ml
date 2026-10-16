(* OCaml source for a small function, read as a term of the writer's
 * language: the lambdas a part's tests pass as arguments (fun x -> x + 1,
 * fun acc x -> acc + x). Only what the components can mean is read; anything
 * else is None, and the example it belonged to is not used. *)

open Parsetree

exception Unreadable

let arity name =
  match Hashtbl.find_opt Eval.components name with
  | Some c -> List.length (fst (Types.unarrow c.Components.scheme))
  | None -> 0

(* eta-expand a component applied to fewer arguments than it takes *)
let eta name args =
  let missing = arity name - List.length args in
  if missing <= 0 then Expr.Call (name, args)
  else
    let xs = List.init missing (fun i -> "eta" ^ string_of_int i) in
    Expr.Lam (xs, Expr.Call (name, args @ List.map (fun x -> Expr.Var x) xs))

let helpers : (string * Expr.t) list ref = ref []

(* Operators a test may use from Base, read by their meaning in Stdlib terms:
   Base's % is the non-negative modulus. *)
let base_ops = [
  ("%", Expr.Lam ([ "a"; "b" ], Expr.Call ("mod", [ Expr.Call ("+", [ Expr.Call ("mod", [ Expr.Var "a"; Expr.Var "b" ]); Expr.Var "b" ]);
                                                    Expr.Var "b" ])));
]

let rec term bound (e : expression) : Expr.t =
  match e.pexp_desc with
  | Pexp_fun (Asttypes.Nolabel, None, { ppat_desc = Ppat_var { txt; _ }; _ }, body) ->
      (match term (txt :: bound) body with
       | Expr.Lam (xs, b) -> Expr.Lam (txt :: xs, b)
       | b -> Expr.Lam ([ txt ], b))
  | Pexp_ident { txt = Longident.Lident x; _ } when List.mem x bound -> Expr.Var x
  | Pexp_ident { txt = Longident.Lident x; _ } when List.mem_assoc x !helpers -> List.assoc x !helpers
  | Pexp_ident { txt; _ } when Hashtbl.mem Eval.components (String.concat "." (Longident.flatten txt)) ->
      eta (String.concat "." (Longident.flatten txt)) []
  | Pexp_constant _ | Pexp_construct (_, None) -> (try Expr.Lit (Literal.value e) with _ -> raise Unreadable)
  | Pexp_apply ({ pexp_desc = Pexp_ident { txt; _ }; _ }, args) ->
      let name = String.concat "." (Longident.flatten txt) in
      let args = List.map (fun (l, a) -> if l <> Asttypes.Nolabel then raise Unreadable else term bound a) args in
      if List.mem_assoc name base_ops then Expr.App (List.assoc name base_ops, args)
      else if Hashtbl.mem Eval.components name then eta name args
      else if List.mem_assoc name !helpers then Expr.App (List.assoc name !helpers, args)
      else if List.mem name bound then Expr.App (Expr.Var name, args)
      else raise Unreadable
  | Pexp_ifthenelse (c, a, Some b) -> Expr.If (term bound c, term bound a, term bound b)
  | Pexp_tuple es -> Expr.Tuple (List.map (term bound) es)
  | Pexp_construct ({ txt; _ }, Some arg) ->
      (match Longident.last txt, arg.pexp_desc with
       | "::", Pexp_tuple [ h; t ] -> Expr.Call ("::", [ term bound h; term bound t ])
       | c, Pexp_tuple es when c <> "Some" -> Expr.Con (c, List.map (term bound) es)
       | c, _ -> Expr.Con (c, [ term bound arg ]))
  | _ -> raise Unreadable

(* A test file's own small functions (let is_odd n = n mod 2 = 1), read so a
   call site that passes one by name can be read too. *)
let read_helpers (str : structure) =
  helpers := [];
  List.iter (fun item -> match item.pstr_desc with
      | Pstr_value (_, vbs) ->
          List.iter (fun (vb : value_binding) -> match vb.pvb_pat.ppat_desc, vb.pvb_expr.pexp_desc with
              | Ppat_var { txt; _ }, Pexp_fun _ ->
                  (try helpers := (txt, term [] vb.pvb_expr) :: !helpers with _ -> ())
              | _ -> ()) vbs
      | _ -> ()) str

(* The value of a function argument read from its source, recorded under
   the OCaml the writer would print for it, so generated calls compile
   without the test's helpers in scope. *)
let value_of_source src =
  match Parse.expression (Lexing.from_string src) with
  | exception _ -> None
  | e ->
      (match term [] e with
       | exception _ -> None
       | t ->
           let src = Lower_ocaml.expr t in
           (match Eval.run [] t with
            | Some v ->
                (match Value.as_function v with
                 | Some g -> Hashtbl.replace Value.funs src g; Some (Value.Con ("#fun", [ Value.String src ]))
                 | None -> None)
            | None -> None))
