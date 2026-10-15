(* Runtime values of the writer's term language. *)

type t =
  | Int of int
  | Int64 of int64
  | Float of float
  | Bool of bool
  | Char of char
  | String of string
  | Unit
  | List of t list
  | Array of t array
  | Tuple of t list
  | Con of string * t list          (* None, Some, Ok, Error, the part's own *)
  | Poly of string * t option       (* `A, `B v *)
  | Record of (string * t) list     (* fields in declaration order *)
  | Fun of (t -> t)

exception Not_comparable

(* How OCaml's own compare orders constructors: every constant constructor
   (an immediate) before every one carrying values (a block), and within each
   group by declaration order. Ordering by name instead would make sorting
   disagree with the compiled program. Set from the part's declarations. *)
let ranks : (string, bool * int) Hashtbl.t = Hashtbl.create 16
let () =
  List.iter (fun (c, r) -> Hashtbl.replace ranks c r)
    [ ("None", (true, 0)); ("Some", (false, 0)); ("Ok", (false, 0)); ("Error", (false, 1)) ]

let declare_variant ctors =
  let consts = ref 0 and blocks = ref 0 in
  List.iter (fun (c, arity) ->
      if arity = 0 then (Hashtbl.replace ranks c (true, !consts); incr consts)
      else (Hashtbl.replace ranks c (false, !blocks); incr blocks)) ctors

(* Polymorphic variants compare by the compiler's tag hash. *)
let hash_variant s =
  let accu = ref 0 in
  String.iter (fun ch -> accu := 223 * !accu + Char.code ch) s;
  accu := !accu land (1 lsl 31 - 1);
  if !accu > 0x3FFFFFFF then !accu - (1 lsl 31) else !accu

(* Structural order, total on first-order values. Floats compare exactly; the
   verifier, not this, decides whether a float answer is close enough. *)
let rec compare a b =
  match a, b with
  | Int x, Int y -> Stdlib.compare x y
  | Int64 x, Int64 y -> Stdlib.compare x y
  | Float x, Float y -> Stdlib.compare x y
  | Bool x, Bool y -> Stdlib.compare x y
  | Char x, Char y -> Stdlib.compare x y
  | String x, String y -> Stdlib.compare x y
  | Unit, Unit -> 0
  | List xs, List ys -> list xs ys
  | Array xs, Array ys -> list (Array.to_list xs) (Array.to_list ys)
  | Tuple xs, Tuple ys -> list xs ys
  | Con (c, xs), Con (d, ys) ->
      let rank c args = match Hashtbl.find_opt ranks c with
        | Some (imm, i) -> ((if imm then 0 else 1), i)
        | None -> ((if args = [] then 0 else 1), 0) in
      let k = Stdlib.compare (rank c xs) (rank d ys) in
      if k <> 0 then k
      else let k = Stdlib.compare c d in if k <> 0 then k else list xs ys
  | Poly (c, x), Poly (d, y) ->
      (match x, y with
       | None, Some _ -> -1 | Some _, None -> 1
       | None, None -> Stdlib.compare (hash_variant c) (hash_variant d)
       | Some x, Some y ->
           let k = Stdlib.compare (hash_variant c) (hash_variant d) in
           if k <> 0 then k else compare x y)
  | Record xs, Record ys -> list (List.map snd xs) (List.map snd ys)
  | Fun _, _ | _, Fun _ -> raise Not_comparable
  | _ -> Stdlib.compare (tag a) (tag b)
and list xs ys =
  match xs, ys with
  | [], [] -> 0 | [], _ -> -1 | _, [] -> 1
  | x :: xs, y :: ys -> let k = compare x y in if k <> 0 then k else list xs ys
and tag = function
  | Int _ -> 0 | Int64 _ -> 1 | Float _ -> 2 | Bool _ -> 3 | Char _ -> 4
  | String _ -> 5 | Unit -> 6 | List _ -> 7 | Array _ -> 8 | Tuple _ -> 9
  | Con _ -> 10 | Poly _ -> 11 | Record _ -> 12 | Fun _ -> 13

let equal a b = try compare a b = 0 with Not_comparable -> false

(* OCaml source for a value, as the toplevel would print it. *)
let rec to_ocaml = function
  | Int n -> if n < 0 then "(" ^ string_of_int n ^ ")" else string_of_int n
  | Int64 n -> "(" ^ Int64.to_string n ^ "L)"
  | Float f ->
      let s = Printf.sprintf "%.17g" f in
      let s = if String.contains s '.' || String.contains s 'e' || String.contains s 'n'
                 || String.contains s 'i' then s else s ^ "." in
      if f < 0. then "(" ^ s ^ ")" else s
  | Bool b -> string_of_bool b
  | Char c -> "'" ^ Char.escaped c ^ "'"
  | String s -> "\"" ^ String.escaped s ^ "\""
  | Unit -> "()"
  | List xs -> "[" ^ String.concat "; " (List.map to_ocaml xs) ^ "]"
  | Array xs -> "[|" ^ String.concat "; " (Array.to_list (Array.map to_ocaml xs)) ^ "|]"
  | Tuple xs -> "(" ^ String.concat ", " (List.map to_ocaml xs) ^ ")"
  | Con (c, []) -> c
  | Con (c, [ x ]) -> "(" ^ c ^ " " ^ to_ocaml x ^ ")"
  | Con (c, xs) -> "(" ^ c ^ " (" ^ String.concat ", " (List.map to_ocaml xs) ^ "))"
  | Poly (c, None) -> "`" ^ c
  | Poly (c, Some x) -> "(`" ^ c ^ " " ^ to_ocaml x ^ ")"
  | Record fs ->
      "{ " ^ String.concat "; " (List.map (fun (f, v) -> f ^ " = " ^ to_ocaml v) fs) ^ " }"
  | Fun _ -> "<fun>"

let to_string = to_ocaml
