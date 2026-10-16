(* A part, written as a Smyth sketch: the contract Smyth is booked against.
 *
 * Smyth (UChicago-PL, ICFP 2020) synthesizes from types and input-output
 * assertions in a small typed functional language. This module only states
 * the part in that language; it searches for nothing. What the language
 * cannot state (strings, characters, floats, negative integers, functions as
 * data, records) is named in the refusal, because a contract that silently
 * drops part of the part would be a different commission.
 *
 * Correspondence, fixed once: non-negative int is Nat, bool is Boolean, list
 * is List, option is Option, a polymorphic variant row `A is the constructor
 * P_A, any other declared variant keeps its constructors. Each type variable
 * of the part stays a type variable, so Smyth cannot look inside it; the
 * assertions instantiate it at Nat, one numeral per distinct example value. *)

open Types

exception Unrepresentable of string

let reserved = [ "Z"; "S"; "T"; "F"; "Nil"; "Cons"; "None"; "Some" ]

let prelude = {|type Nat
  = Z ()
  | S Nat

type Boolean
  = F ()
  | T ()

type List a
  = Nil ()
  | Cons (a, List a)

type Option a
  = None ()
  | Some a
|}

let tyname n = String.capitalize_ascii n

let rec typ ~inst t =
  match repr t with
  | TCon ("int", []) -> "Nat"
  | TCon ("bool", []) -> "Boolean"
  | TCon ("list", [ a ]) -> "(List " ^ typ ~inst a ^ ")"
  | TCon ("option", [ a ]) -> "(Option " ^ typ ~inst a ^ ")"
  | TCon ("unit", []) -> "()"
  | TTuple ts -> "(" ^ String.concat ", " (List.map (typ ~inst) ts) ^ ")"
  | TArrow (_, a, b) -> "(" ^ typ ~inst a ^ " -> " ^ typ ~inst b ^ ")"
  | TVar v -> if inst then "Nat" else String.lowercase_ascii v
  | TCon (n, args) when List.for_all (fun c -> c <> n) [ "string"; "char"; "float"; "int64"; "array"; "result" ] ->
      if args = [] then tyname n else "(" ^ String.concat " " (tyname n :: List.map (typ ~inst) args) ^ ")"
  | t -> raise (Unrepresentable ("type " ^ Types.to_string t))

let decl (d : decl) =
  let params = List.map String.lowercase_ascii d.params in
  let head = String.concat " " (tyname d.name :: params) in
  let arg = function [] -> "()" | [ t ] -> typ ~inst:false t | ts -> typ ~inst:false (TTuple ts) in
  match d.kind with
  | Variant ctors ->
      List.iter (fun (c, _) ->
          if List.mem c reserved then raise (Unrepresentable ("constructor " ^ c ^ " is one of Smyth's own"))) ctors;
      Printf.sprintf "type %s\n  = %s\n" head
        (String.concat "\n  | " (List.map (fun (c, ts) -> c ^ " " ^ arg ts) ctors))
  | Poly rows ->
      Printf.sprintf "type %s\n  = %s\n" head
        (String.concat "\n  | " (List.map (fun (r, t) ->
             "P_" ^ r ^ " " ^ (match t with None -> "()" | Some t -> typ ~inst:false t)) rows))
  | Alias _ -> ""
  | Record _ -> raise (Unrepresentable ("record type " ^ d.name))
  | Abstract -> raise (Unrepresentable ("abstract type " ^ d.name))

(* Constructor argument types, from the part's declarations, with the
   declaration's parameters standing in for themselves. *)
let ctor_types : (string -> ty list option) ref = ref (fun _ -> None)

(* A value at a type, as a Smyth term. Values at a type variable become the
   numeral of their index among the distinct such values. *)
let value ~elts ty v =
  let index v =
    match List.find_opt (fun (w, _) -> Value.equal v w) !elts with
    | Some (_, i) -> i
    | None -> let i = List.length !elts in elts := !elts @ [ (v, i) ]; i in
  let rec go t v =
    match repr t, v with
    | TVar _, v -> string_of_int (index v)
    | TCon ("int", []), Value.Int n ->
        if n < 0 then raise (Unrepresentable "a negative integer") else string_of_int n
    | TCon ("bool", []), Value.Bool b -> if b then "T ()" else "F ()"
    | TCon ("unit", []), _ -> "()"
    | TCon ("list", [ a ]), Value.List l ->
        "[" ^ String.concat ", " (List.map (go a) l) ^ "]<" ^ typ ~inst:true a ^ ">"
    | TCon ("option", [ a ]), Value.Con ("None", []) -> "None<" ^ typ ~inst:true a ^ "> ()"
    | TCon ("option", [ a ]), Value.Con ("Some", [ x ]) -> "Some<" ^ typ ~inst:true a ^ "> (" ^ go a x ^ ")"
    | TTuple ts, Value.Tuple vs when List.length ts = List.length vs ->
        "(" ^ String.concat ", " (List.map2 go ts vs) ^ ")"
    | TCon (_, args), Value.Poly (r, None) when args = [] -> "P_" ^ r ^ " ()"
    | TCon _, Value.Con (c, args) ->
        let targs = List.map (fun a -> typ ~inst:true a) (match repr t with TCon (_, a) -> a | _ -> []) in
        let ta = if targs = [] then "" else "<" ^ String.concat ", " targs ^ ">" in
        let ctor_tys = !ctor_types c in
        (match ctor_tys, args with
         | _, [] -> c ^ ta ^ " ()"
         | Some [ ty ], [ a ] -> c ^ ta ^ " (" ^ go ty a ^ ")"
         | Some tys, _ when List.length tys = List.length args ->
             c ^ ta ^ " (" ^ String.concat ", " (List.map2 go tys args) ^ ")"
         | _ -> raise (Unrepresentable ("constructor " ^ c)))
    | t, _ -> raise (Unrepresentable ("a value of type " ^ Types.to_string t)) in
  go ty v

let sketch ~decls ~name ~(params : (string * ty) list) ~out_ty (examples : Spec.example list) =
  ctor_types := (fun c ->
      List.find_map (fun (d : decl) -> match d.kind with
          | Variant cs -> List.assoc_opt c cs
          | _ -> None) decls);
  let tvars = List.sort_uniq compare
      (let rec vars t = match repr t with
          | TVar v -> [ String.lowercase_ascii v ]
          | TCon (_, ts) | TTuple ts -> List.concat_map vars ts
          | TArrow (_, a, b) -> vars a @ vars b
          | _ -> [] in
       List.concat_map (fun (_, t) -> vars t) params @ vars out_ty) in
  let ftype = String.concat " -> " (List.map (fun (_, t) -> typ ~inst:false t) params @ [ typ ~inst:false out_ty ]) in
  let forall = if tvars = [] then "" else "forall " ^ String.concat " " tvars ^ " . " in
  let tparams = String.concat "" (List.map (fun v -> " <" ^ v ^ ">") tvars) in
  let pnames = List.mapi (fun i _ -> "p" ^ string_of_int i) params in
  let inst = String.concat "" (List.map (fun _ -> " <Nat>") tvars) in
  let elts = ref [] in
  let asserts = List.map (fun (ex : Spec.example) ->
      let args = List.map2 (fun (_, t) v -> "(" ^ value ~elts t v ^ ")") params ex.Spec.args in
      Printf.sprintf "assert (%s%s) %s == (%s)" name inst (String.concat " " args) (value ~elts out_ty ex.Spec.out))
      examples in
  String.concat "\n" (prelude :: List.map decl decls)
  ^ Printf.sprintf "\n%s : %s%s\n%s%s %s =\n  ??\n\n%s\n" name forall ftype name tparams
      (String.concat " " pnames) (String.concat "\n" asserts)

(* Smyth's answer, as the OCaml definition of the part's value. The answer
   names parameters p0..pn and calls itself unlabelled, so it is bound as an
   inner function the labelled definition applies. *)
let definition ~name ~(params : (string * label) list) body =
  let pnames = List.mapi (fun i _ -> "p" ^ string_of_int i) params in
  let poly = Str.global_replace (Str.regexp "\\bP_\\([A-Z][A-Za-z0-9_']*\\)") "`\\1" body in
  let outer = List.map2 (fun p (_, l) -> match l with
      | Labelled s -> "~" ^ s ^ ":" ^ p
      | Optional s -> "?" ^ s ^ ":" ^ p
      | Nolabel -> p) pnames params in
  Printf.sprintf "let %s %s =\n  let rec %s %s = %s in\n  %s %s"
    name (String.concat " " outer) name (String.concat " " pnames) poly name (String.concat " " pnames)
