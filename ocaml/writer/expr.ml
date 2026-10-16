(* Terms the writer derives. A component is always fully applied (Call), so
 * every term has a first-order shape the enumerator can size and the lowerers
 * can print without guessing at partial application. Functions as values exist
 * only as Lam, passed to a higher-order component or bound by Let. *)

type pat =
  | PVar of string
  | PWild
  | PNil
  | PCons of pat * pat
  | PCon of string * pat list
  | PPoly of string * pat option
  | PTuple of pat list
  | PLit of Value.t

type t =
  | Var of string
  | Lit of Value.t
  | Call of string * t list              (* a component, by its name *)
  | App of t * t list                    (* applying a bound function *)
  | Lam of string list * t
  | Con of string * t list
  | Poly of string * t option
  | Tuple of t list
  | Record of (string * t) list
  | Field of t * string
  | If of t * t * t
  | Match of t * (pat * t) list
  | Let of bool * string * t * t         (* rec?, name, bound, body *)

let rec size = function
  | Var _ | Lit _ -> 1
  | Call (_, args) | App (Var _, args) -> 1 + sum args
  | App (f, args) -> size f + sum args
  | Lam (_, b) -> 1 + size b
  | Con (_, args) | Tuple args -> 1 + sum args
  | Poly (_, None) -> 1
  | Poly (_, Some e) -> 1 + size e
  | Record fs -> 1 + sum (List.map snd fs)
  | Field (e, _) -> 1 + size e
  | If (c, a, b) -> 1 + size c + size a + size b
  | Match (e, bs) -> 1 + size e + sum (List.map snd bs)
  | Let (_, _, a, b) -> 1 + size a + size b
and sum es = List.fold_left (fun n e -> n + size e) 0 es

let rec pat_vars = function
  | PVar x -> [ x ]
  | PWild | PNil | PLit _ | PPoly (_, None) -> []
  | PCons (a, b) -> pat_vars a @ pat_vars b
  | PCon (_, ps) | PTuple ps -> List.concat_map pat_vars ps
  | PPoly (_, Some p) -> pat_vars p

(* Does `name` occur free? Used to tell a recursive body from one that never
   recurses, which lowers without `rec`. *)
let rec mentions name = function
  | Var x -> x = name
  | Lit _ | Poly (_, None) -> false
  | Call (_, args) | Con (_, args) | Tuple args -> List.exists (mentions name) args
  | App (f, args) -> mentions name f || List.exists (mentions name) args
  | Lam (xs, b) -> not (List.mem name xs) && mentions name b
  | Poly (_, Some e) | Field (e, _) -> mentions name e
  | Record fs -> List.exists (fun (_, e) -> mentions name e) fs
  | If (c, a, b) -> mentions name c || mentions name a || mentions name b
  | Match (e, bs) ->
      mentions name e
      || List.exists (fun (p, b) -> not (List.mem name (pat_vars p)) && mentions name b) bs
  | Let (r, x, a, b) ->
      (if r && x = name then false else mentions name a)
      || (x <> name && mentions name b)
