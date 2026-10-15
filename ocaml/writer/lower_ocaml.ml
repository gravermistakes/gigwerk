(* Terms to OCaml source. The printer adds parentheses wherever precedence
 * could matter, because a derived program that means something else once
 * printed would pass the search and fail the compiler, or worse, pass both. *)

open Expr

let comp_ocaml name args =
  match Hashtbl.find_opt Eval.components name with
  | Some c -> c.Components.ocaml args
  | None -> "(" ^ String.concat " " (name :: args) ^ ")"

let rec pat = function
  | PVar x -> x
  | PWild -> "_"
  | PNil -> "[]"
  | PCons (h, t) -> "(" ^ pat h ^ " :: " ^ pat t ^ ")"
  | PCon (c, []) -> c
  | PCon (c, [ p ]) -> "(" ^ c ^ " " ^ pat p ^ ")"
  | PCon (c, ps) -> "(" ^ c ^ " (" ^ String.concat ", " (List.map pat ps) ^ "))"
  | PPoly (t, None) -> "`" ^ t
  | PPoly (t, Some p) -> "(`" ^ t ^ " " ^ pat p ^ ")"
  | PTuple ps -> "(" ^ String.concat ", " (List.map pat ps) ^ ")"
  | PLit v -> Value.to_ocaml v

let rec expr = function
  | Var x -> x
  | Lit v -> Value.to_ocaml v
  | Call (name, args) -> comp_ocaml name (List.map expr args)
  | App (f, args) -> "(" ^ String.concat " " (expr f :: List.map expr args) ^ ")"
  | Lam (xs, b) -> "(fun " ^ String.concat " " xs ^ " -> " ^ expr b ^ ")"
  | Con (c, []) -> c
  | Con (c, [ a ]) -> "(" ^ c ^ " " ^ expr a ^ ")"
  | Con (c, args) -> "(" ^ c ^ " (" ^ String.concat ", " (List.map expr args) ^ "))"
  | Poly (t, None) -> "`" ^ t
  | Poly (t, Some a) -> "(`" ^ t ^ " " ^ expr a ^ ")"
  | Tuple es -> "(" ^ String.concat ", " (List.map expr es) ^ ")"
  | Record fs -> "{ " ^ String.concat "; " (List.map (fun (f, e) -> f ^ " = " ^ expr e) fs) ^ " }"
  | Field (e, f) -> expr e ^ "." ^ f
  | If (c, a, b) -> "(if " ^ expr c ^ " then " ^ expr a ^ " else " ^ expr b ^ ")"
  | Match (e, bs) ->
      "(match " ^ expr e ^ " with "
      ^ String.concat " | " (List.map (fun (p, b) -> pat p ^ " -> " ^ expr b) bs) ^ ")"
  | Let (r, x, a, b) ->
      "(let " ^ (if r then "rec " else "") ^ x ^ " = " ^ expr a ^ " in " ^ expr b ^ ")"

(* A parameter's binder from its label. *)
let binder (name, label) =
  match label with
  | Types.Nolabel -> name
  | Types.Labelled l -> "~" ^ l ^ ":" ^ name
  | Types.Optional l -> "?" ^ l ^ ":" ^ name

let definition ~name ~params body =
  let rec_ = if Expr.mentions name body then "rec " else "" in
  match params with
  | [] -> Printf.sprintf "let %s%s = %s" rec_ name (expr body)
  | _ -> Printf.sprintf "let %s%s %s = %s" rec_ name (String.concat " " (List.map binder params)) (expr body)

(* The module: the interface's opens and declarations, then Stdlib re-opened
   so the derived code means what the writer's components mean. *)
let module_source ~mli_src ~definitions =
  let sg = Parse.interface (Lexing.from_string mli_src) in
  let prelude = List.filter_map (fun item ->
      match item.Parsetree.psig_desc with
      | Parsetree.Psig_type (rf, tds) ->
          Some (Format.asprintf "%a" Pprintast.structure [ Ast_helper.Str.type_ rf tds ])
      | Parsetree.Psig_open od ->
          Some ("open " ^ String.concat "." (Longident.flatten od.Parsetree.popen_expr.txt))
      | _ -> None) sg in
  String.concat "\n" prelude ^ "\nopen! Stdlib\n\n" ^ String.concat "\n\n" definitions ^ "\n"
