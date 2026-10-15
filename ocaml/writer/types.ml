(* Types of the writer's term language.
 *
 * TVar is a RIGID variable from the part's own signature: 'a in
 * `last : 'a list -> 'a option` is opaque to the writer, so no constant can
 * inhabit it and the element returned must come from the input. That is
 * parametricity doing the work examples cannot: two examples underdetermine
 * `last`, but its type rules out every program that invents an element.
 *
 * TGen is a variable quantified in a component's scheme (List.map's 'a and
 * 'b). It is instantiated with a fresh TMeta at each use and never meets a
 * rigid TVar by name. *)

type label = Nolabel | Labelled of string | Optional of string

type ty =
  | TCon of string * ty list     (* int, bool, list, option, result, user types *)
  | TTuple of ty list
  | TArrow of label * ty * ty
  | TVar of string
  | TGen of int
  | TMeta of meta ref
and meta = Unbound of int | Link of ty

let con n = TCon (n, [])
let t_int = con "int"
let t_int64 = con "int64"
let t_float = con "float"
let t_bool = con "bool"
let t_char = con "char"
let t_string = con "string"
let t_unit = con "unit"
let t_list t = TCon ("list", [ t ])
let t_array t = TCon ("array", [ t ])
let t_option t = TCon ("option", [ t ])
let t_result a b = TCon ("result", [ a; b ])
let arrow a b = TArrow (Nolabel, a, b)
let arrows args res = List.fold_right arrow args res

let counter = ref 0
let fresh () = incr counter; TMeta (ref (Unbound !counter))

let rec repr = function
  | TMeta ({ contents = Link t } as r) ->
      let t' = repr t in r := Link t'; t'
  | t -> t

(* Split a function type into its argument types and result. *)
let rec unarrow t =
  match repr t with
  | TArrow (l, a, b) -> let args, r = unarrow b in ((l, a) :: args, r)
  | t -> ([], t)

let rec occurs r t =
  match repr t with
  | TMeta r' -> r == r'
  | TCon (_, ts) | TTuple ts -> List.exists (occurs r) ts
  | TArrow (_, a, b) -> occurs r a || occurs r b
  | TVar _ | TGen _ -> false

exception Mismatch

let rec unify a b =
  match repr a, repr b with
  | TMeta r1, TMeta r2 when r1 == r2 -> ()
  | TMeta r, t | t, TMeta r ->
      if occurs r t then raise Mismatch; r := Link t
  | TCon (n1, a1), TCon (n2, a2) when n1 = n2 && List.length a1 = List.length a2 ->
      List.iter2 unify a1 a2
  | TTuple a1, TTuple a2 when List.length a1 = List.length a2 -> List.iter2 unify a1 a2
  | TArrow (_, a1, b1), TArrow (_, a2, b2) -> unify a1 a2; unify b1 b2
  | TVar x, TVar y when x = y -> ()
  | TGen i, TGen j when i = j -> ()
  | _ -> raise Mismatch

(* Unify, undoing every link made if it fails, so a failed attempt leaves no
   trace on the types it touched. *)
let try_unify a b =
  let trail = ref [] in
  let rec u a b =
    match repr a, repr b with
    | TMeta r1, TMeta r2 when r1 == r2 -> ()
    | TMeta r, t | t, TMeta r ->
        if occurs r t then raise Mismatch;
        trail := (r, !r) :: !trail; r := Link t
    | TCon (n1, a1), TCon (n2, a2) when n1 = n2 && List.length a1 = List.length a2 ->
        List.iter2 u a1 a2
    | TTuple a1, TTuple a2 when List.length a1 = List.length a2 -> List.iter2 u a1 a2
    | TArrow (_, a1, b1), TArrow (_, a2, b2) -> u a1 a2; u b1 b2
    | TVar x, TVar y when x = y -> ()
    | TGen i, TGen j when i = j -> ()
    | _ -> raise Mismatch
  in
  try u a b; true
  with Mismatch -> List.iter (fun (r, old) -> r := old) !trail; false

let instantiate t =
  let tbl = Hashtbl.create 4 in
  let rec go t =
    match repr t with
    | TGen i ->
        (match Hashtbl.find_opt tbl i with
         | Some m -> m
         | None -> let m = fresh () in Hashtbl.add tbl i m; m)
    | TCon (n, ts) -> TCon (n, List.map go ts)
    | TTuple ts -> TTuple (List.map go ts)
    | TArrow (l, a, b) -> TArrow (l, go a, go b)
    | t -> t
  in
  go t

(* A type with its metas resolved; None if one is still unbound. *)
let rec zonk t =
  match repr t with
  | TMeta _ -> None
  | TCon (n, ts) -> Option.map (fun ts -> TCon (n, ts)) (zonk_all ts)
  | TTuple ts -> Option.map (fun ts -> TTuple ts) (zonk_all ts)
  | TArrow (l, a, b) ->
      (match zonk a, zonk b with Some a, Some b -> Some (TArrow (l, a, b)) | _ -> None)
  | t -> Some t
and zonk_all ts =
  List.fold_right (fun t acc ->
      match zonk t, acc with Some t, Some acc -> Some (t :: acc) | _ -> None) ts (Some [])

let rec ground t = match zonk t with Some _ -> true | None -> false
and is_ground t = ground t

let rec to_string t =
  match repr t with
  | TCon (n, []) -> n
  | TCon (n, [ a ]) -> atom a ^ " " ^ n
  | TCon (n, ts) -> "(" ^ String.concat ", " (List.map to_string ts) ^ ") " ^ n
  | TTuple ts -> String.concat " * " (List.map atom ts)
  | TArrow (l, a, b) ->
      let pre = match l with
        | Nolabel -> "" | Labelled s -> s ^ ":" | Optional s -> "?" ^ s ^ ":" in
      pre ^ atom_arrow a ^ " -> " ^ to_string b
  | TVar v -> "'" ^ v
  | TGen i -> "'g" ^ string_of_int i
  | TMeta { contents = Unbound i } -> "'_m" ^ string_of_int i
  | TMeta { contents = Link t } -> to_string t
and atom t = match repr t with
  | TTuple _ | TArrow _ -> "(" ^ to_string t ^ ")"
  | _ -> to_string t
and atom_arrow t = match repr t with
  | TArrow _ -> "(" ^ to_string t ^ ")"
  | _ -> to_string t

(* A type declaration from the part's interface. *)
type decl_kind =
  | Variant of (string * ty list) list
  | Record of (string * ty) list
  | Alias of ty
  | Poly of (string * ty option) list      (* [ `A | `B of int ] *)
  | Abstract

type decl = { name : string; params : string list; kind : decl_kind }
