(* OCaml literal text to a writer value, through the compiler's own parser.
 *
 * Used on two kinds of text: what a probe printed (Printers' output) and what
 * the ocaml.org toplevel transcripts show after `- : t =`. Both are OCaml
 * syntax for first-order values, so one reader serves both. A generic block
 * printed for a value of rigid type comes back as an opaque constructor that
 * is equal exactly when the printed values were. *)

open Parsetree

exception Not_a_literal of string

let constant (c : constant) : Value.t =
  match c with
  | Pconst_integer (s, None) -> Value.Int (int_of_string s)
  | Pconst_integer (s, Some 'L') -> Value.Int64 (Int64.of_string s)
  | Pconst_integer (s, Some 'l') -> Value.Int (int_of_string s)
  | Pconst_integer (s, Some _) -> raise (Not_a_literal s)
  | Pconst_char ch -> Value.Char ch
  | Pconst_string (s, _, _) -> Value.String s
  | Pconst_float (s, _) -> Value.Float (float_of_string s)

let ctor_name (li : Longident.t) = Longident.last li

let rec value (e : expression) : Value.t =
  match e.pexp_desc with
  | Pexp_constant c -> constant c
  | Pexp_construct ({ txt = Longident.Lident "()"; _ }, None) -> Value.Unit
  | Pexp_construct ({ txt = Longident.Lident "true"; _ }, None) -> Value.Bool true
  | Pexp_construct ({ txt = Longident.Lident "false"; _ }, None) -> Value.Bool false
  | Pexp_construct ({ txt = Longident.Lident "[]"; _ }, None) -> Value.List []
  | Pexp_construct ({ txt = Longident.Lident "::"; _ }, Some { pexp_desc = Pexp_tuple [ h; t ]; _ }) ->
      (match value t with
       | Value.List l -> Value.List (value h :: l)
       | _ -> raise (Not_a_literal "improper list"))
  | Pexp_construct ({ txt; _ }, None) -> Value.Con (ctor_name txt, [])
  | Pexp_construct ({ txt; _ }, Some { pexp_desc = Pexp_tuple args; _ })
    when ctor_name txt <> "Some" && ctor_name txt <> "Ok" && ctor_name txt <> "Error" ->
      Value.Con (ctor_name txt, List.map value args)
  | Pexp_construct ({ txt; _ }, Some arg) -> Value.Con (ctor_name txt, [ value arg ])
  | Pexp_variant (tag, None) -> Value.Poly (tag, None)
  | Pexp_variant (tag, Some arg) -> Value.Poly (tag, Some (value arg))
  | Pexp_tuple es -> Value.Tuple (List.map value es)
  | Pexp_array es -> Value.Array (Array.of_list (List.map value es))
  | Pexp_record (fs, None) ->
      Value.Record (List.map (fun ({ Location.txt; _ }, e) -> (Longident.last txt, value e)) fs)
  | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Longident.Lident "~-"; _ }; _ }, [ (_, x) ]) ->
      (match value x with
       | Value.Int n -> Value.Int (- n)
       | Value.Int64 n -> Value.Int64 (Int64.neg n)
       | Value.Float f -> Value.Float (-. f)
       | _ -> raise (Not_a_literal "negation"))
  | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Longident.Lident "~-."; _ }; _ }, [ (_, x) ]) ->
      (match value x with Value.Float f -> Value.Float (-. f) | _ -> raise (Not_a_literal "negation"))
  | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Longident.Lident "__gw_block"; _ }; _ },
                [ (_, tag); (_, { pexp_desc = Pexp_tuple fields; _ }) ]) ->
      let fields = List.filter (fun f -> match f.pexp_desc with
          | Pexp_construct ({ txt = Longident.Lident "()"; _ }, None) -> false | _ -> true) fields in
      (match value tag with
       | Value.Int t -> Value.Con ("#" ^ string_of_int t, List.map value fields)
       | _ -> raise (Not_a_literal "block"))
  | Pexp_constraint (e, _) -> value e
  | _ -> raise (Not_a_literal (Format.asprintf "%a" Pprintast.expression e))

let of_string s =
  let e = Parse.expression (Lexing.from_string s) in
  value e

let of_string_opt s = try Some (of_string s) with _ -> None
