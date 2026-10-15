(* Free theorems as examples.
 *
 * A function of type 'a list -> 'a list that never compares its elements
 * cannot tell them apart, so whatever it does to ["a"; "b"; "c"] it does to
 * ["x"; "x"; "x"] position for position. That is a theorem about the type,
 * not a guess, and it hands the search extra examples nobody wrote: collapse
 * every 'a value in an example to one value, inputs and output alike.
 *
 * The theorem holds only for programs that do not compare 'a values, so the
 * writer tries that reading first (strict: comparison components may not
 * touch a rigid variable, and the collapsed examples are added) and falls
 * back to the ordinary one. `duplicate ["a";"b";"c";"c";"d"]` stops looking
 * like `List.sort (x @ x)` the moment sorting is off the table. *)

open Types

let rec has_var t =
  match repr t with
  | TVar _ -> true
  | TCon (_, ts) | TTuple ts -> List.exists has_var ts
  | TArrow (_, a, b) -> has_var a || has_var b
  | _ -> false

let rec first_var_value ty (v : Value.t) =
  match repr ty, v with
  | TVar _, _ -> Some v
  | TCon (("list" | "array"), [ a ]), Value.List l -> List.find_map (first_var_value a) l
  | TCon ("option", [ a ]), Value.Con ("Some", [ x ]) -> first_var_value a x
  | TCon ("result", [ a; _ ]), Value.Con ("Ok", [ x ]) -> first_var_value a x
  | TCon ("result", [ _; b ]), Value.Con ("Error", [ x ]) -> first_var_value b x
  | TTuple ts, Value.Tuple xs when List.length ts = List.length xs ->
      List.find_map (fun (t, x) -> first_var_value t x) (List.combine ts xs)
  | _ -> None

exception Opaque

let rec collapse rep ty (v : Value.t) : Value.t =
  match repr ty, v with
  | TVar _, _ -> rep
  | TCon ("list", [ a ]), Value.List l -> Value.List (List.map (collapse rep a) l)
  | TCon ("option", [ a ]), Value.Con ("Some", [ x ]) -> Value.Con ("Some", [ collapse rep a x ])
  | TCon ("option", [ _ ]), Value.Con ("None", []) -> v
  | TCon ("result", [ a; _ ]), Value.Con ("Ok", [ x ]) -> Value.Con ("Ok", [ collapse rep a x ])
  | TCon ("result", [ _; b ]), Value.Con ("Error", [ x ]) -> Value.Con ("Error", [ collapse rep b x ])
  | TTuple ts, Value.Tuple xs when List.length ts = List.length xs ->
      Value.Tuple (List.map2 (collapse rep) ts xs)
  | t, _ when has_var t -> raise Opaque     (* a 'a inside a type this cannot walk *)
  | _ -> v

(* The examples, plus their collapsed images. None when the collapsed images
   contradict each other or the originals: then no strictly parametric
   function fits, and the strict reading is pointless. *)
let augment ~(params : (string * ty) list) ~out_ty (examples : Spec.example list) =
  if not (List.exists (fun (_, t) -> has_var t) params) then None
  else
    try
      let collapsed = List.filter_map (fun ex ->
          let rep = List.find_map (fun (t, a) -> first_var_value t a)
              (List.combine (List.map snd params) ex.Spec.args) in
          Option.map (fun rep ->
              { Spec.args = List.map2 (collapse rep) (List.map snd params) ex.Spec.args;
                out = collapse rep out_ty ex.Spec.out }) rep) examples in
      let all = examples @ collapsed in
      let conflict = List.exists (fun a -> List.exists (fun b ->
          List.for_all2 Value.equal a.Spec.args b.Spec.args && not (Value.equal a.Spec.out b.Spec.out)) all) all in
      if conflict then None
      else
        Some (List.fold_left (fun acc ex ->
            if List.exists (fun e -> List.for_all2 Value.equal e.Spec.args ex.Spec.args) acc then acc
            else acc @ [ ex ]) [] all)
    with Opaque -> None
