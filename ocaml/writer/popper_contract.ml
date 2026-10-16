(* A part, written as a Popper task: the contract Popper is booked against.
 *
 * Popper (Cropper and Morel) learns Prolog programs from examples,
 * background knowledge and a declaration bias. This module only states the
 * part in those three files; the learning is Popper's.
 *
 * - exs.pl: each example is a positive. A function has one answer per
 *   input, so the answers other examples gave, where they differ, are
 *   negatives (the closed-world reading of a function). A test (bool result)
 *   is learned as a relation of its inputs, true examples positive and
 *   false ones negative.
 * - bk.pl: one fixed library of list and integer predicates, the same for
 *   every part, the way Stdlib is the same for every OCaml part.
 * - bias.pl: the part's own predicate, and the library predicates its types
 *   reach, typed by the part's types.
 *
 * What the library cannot type (two different list types in one part,
 * functions as arguments) is named in the refusal. *)

open Types

exception Unrepresentable of string

let library = {|head([H|_],H).
tail([_|T],T).
empty([]).
cons(H,T,[H|T]).
snoc(L,E,R) :- append(L,[E],R).
app(A,B,C) :- append(A,B,C).
zero(0).
one(1).
inc(A,B) :- integer(A), B is A+1.
dec(A,B) :- integer(A), A > 0, B is A-1.
add(A,B,C) :- integer(A), integer(B), C is A+B.
mult(A,B,C) :- integer(A), integer(B), C is A*B.
geq(A,B) :- integer(A), integer(B), A >= B.
even(A) :- integer(A), 0 is A mod 2.
odd(A) :- integer(A), 1 is A mod 2.
eq(A,A).
neq(A,B) :- A \== B.
some(X,some(X)).
none(none).
|}

type preds = { decls : (string * string list * string list) list }
(* name, types, directions *)

let label t =
  match repr t with
  | TCon ("int", []) -> "int"
  | TCon ("list", _) -> "list"
  | TCon ("bool", []) -> "bool"
  | TCon ("option", _) -> "option"
  | TTuple _ -> raise (Unrepresentable "a tuple argument")
  | TArrow _ -> raise (Unrepresentable "a function argument")
  | _ -> "elem"

let reached (tys : ty list) =
  let lists = List.sort_uniq compare (List.filter_map (fun t -> match repr t with
      | TCon ("list", [ e ]) -> Some (Types.to_string e) | _ -> None) tys) in
  if List.length lists > 1 then raise (Unrepresentable "two different list types in one part");
  let elem = List.find_map (fun t -> match repr t with
      | TCon ("list", [ e ]) -> Some (match repr e with TCon ("int", []) -> "int" | _ -> "elem") | _ -> None) tys in
  let has_int = List.exists (fun t -> match repr t with TCon ("int", []) -> true | _ -> false) tys
                || elem = Some "int" in
  let list_preds = match elem with
    | None -> []
    | Some e ->
        [ ("head", [ "list"; e ], [ "in"; "out" ]); ("tail", [ "list"; "list" ], [ "in"; "out" ]);
          ("empty", [ "list" ], [ "out" ]); ("cons", [ e; "list"; "list" ], [ "in"; "in"; "out" ]);
          ("snoc", [ "list"; e; "list" ], [ "in"; "in"; "out" ]);
          ("app", [ "list"; "list"; "list" ], [ "in"; "in"; "out" ]) ]
        @ (if e = "elem" then [ ("eq", [ "elem"; "elem" ], [ "in"; "in" ]); ("neq", [ "elem"; "elem" ], [ "in"; "in" ]) ]
           else []) in
  let int_preds = if not has_int then [] else
      [ ("zero", [ "int" ], [ "out" ]); ("one", [ "int" ], [ "out" ]);
        ("inc", [ "int"; "int" ], [ "in"; "out" ]); ("dec", [ "int"; "int" ], [ "in"; "out" ]);
        ("add", [ "int"; "int"; "int" ], [ "in"; "in"; "out" ]);
        ("mult", [ "int"; "int"; "int" ], [ "in"; "in"; "out" ]);
        ("geq", [ "int"; "int" ], [ "in"; "in" ]); ("even", [ "int" ], [ "in" ]); ("odd", [ "int" ], [ "in" ]);
        ("eq", [ "int"; "int" ], [ "in"; "in" ]); ("neq", [ "int"; "int" ], [ "in"; "in" ]) ] in
  let opt_preds = List.concat_map (fun t -> match repr t with
      | TCon ("option", [ e ]) ->
          let e = match repr e with TCon ("int", []) -> "int" | _ -> "elem" in
          [ ("some", [ e; "option" ], [ "in"; "out" ]); ("none", [ "option" ], [ "out" ]) ]
      | _ -> []) tys in
  (* one declaration per name: an elem eq and an int eq cannot both stand *)
  List.fold_left (fun acc (n, t, d) -> if List.exists (fun (m, _, _) -> m = n) acc then acc else acc @ [ (n, t, d) ])
    [] (list_preds @ int_preds @ opt_preds)

let tuple xs = "(" ^ String.concat "," xs ^ (if List.length xs = 1 then ",)" else ")")

(* The three files, and the predicate the learned program defines. *)
let task ~name ~(params : (string * ty) list) ~out_ty (examples : Spec.example list) =
  let pred = Lower_prolog.predicate_name name in
  let arg_tys = List.map snd params in
  let is_test = (match repr out_ty with TCon ("bool", []) -> true | _ -> false) in
  let head_tys = List.map label arg_tys @ (if is_test then [] else [ label out_ty ]) in
  let head_dirs = List.map (fun _ -> "in") arg_tys @ (if is_test then [] else [ "out" ]) in
  let body = reached (arg_tys @ [ out_ty ]) in
  let term v = Lower_prolog.term v in
  let atom args = pred ^ "(" ^ String.concat "," (List.map term args) ^ ")" in
  let pos, neg =
    if is_test then
      List.partition_map (fun (ex : Spec.example) ->
          if ex.Spec.out = Value.Bool true then Left (atom ex.Spec.args) else Right (atom ex.Spec.args)) examples
    else
      let outs = List.sort_uniq compare (List.map (fun (ex : Spec.example) -> ex.Spec.out) examples) in
      (List.map (fun (ex : Spec.example) -> atom (ex.Spec.args @ [ ex.Spec.out ])) examples,
       List.concat_map (fun (ex : Spec.example) ->
           List.filteri (fun i _ -> i < 6)
             (List.filter_map (fun o -> if Value.equal o ex.Spec.out then None
                                else Some (atom (ex.Spec.args @ [ o ]))) outs)) examples) in
  let exs = String.concat "\n" (List.map (fun a -> "pos(" ^ a ^ ").") pos @ List.map (fun a -> "neg(" ^ a ^ ").") neg) ^ "\n" in
  let bias = String.concat "\n" (
      [ "enable_recursion.";
        Printf.sprintf "head_pred(%s,%d)." pred (List.length head_tys) ]
      @ List.map (fun (n, t, _) -> Printf.sprintf "body_pred(%s,%d)." n (List.length t)) body
      @ [ Printf.sprintf "type(%s,%s)." pred (tuple head_tys) ]
      @ List.map (fun (n, t, _) -> Printf.sprintf "type(%s,%s)." n (tuple t)) body
      @ [ Printf.sprintf "direction(%s,%s)." pred (tuple head_dirs) ]
      @ List.map (fun (n, _, d) -> Printf.sprintf "direction(%s,%s)." n (tuple d)) body) ^ "\n" in
  (pred, is_test, exs, library, bias)

(* Popper's program, as the predicate the Prolog acceptance calls: a test
   answers true or false, a function its last argument. *)
let program ~pred ~is_test ~arity clauses =
  let learned = if is_test then
      Str.global_replace (Str.regexp_string (pred ^ "(")) (pred ^ "_holds(") clauses else clauses in
  library ^ learned ^ "\n"
  ^ (if is_test then
       let vs = List.init arity (fun i -> "X" ^ string_of_int i) in
       Printf.sprintf "%s(%s, R) :- ( %s_holds(%s) -> R = true ; R = false ).\n"
         pred (String.concat ", " vs) pred (String.concat ", " vs)
     else "")
