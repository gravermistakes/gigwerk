(* What the Agency keeps from earlier commissions, offered to later ones.
 *
 * Actors do not accumulate; the Agency does. When a part's derived values pass
 * the part's OWN published check (its test suite, or its statement replayed),
 * the Agency records them; a later part may then use them as vocabulary, the
 * way ocaml.org's problems build on one another ("modify the result of the
 * previous problem": encode is pack, then a count).
 *
 * The entry condition is deliberately the part's own check and never the
 * verifier's verdict. The verifier reads reference solutions; if its verdict
 * chose what the Agency keeps, a reference would be steering later
 * derivations. With this rule no reference reaches the search, not even as
 * one bit.
 *
 * Entries are the writer's own derivations: name, parameters, type, term. *)

type entry = {
  slug : string;
  name : string;
  params : (string * Types.label) list;
  ty : Types.ty;
  body : Expr.t;
}

let file dir slug = Filename.concat dir (slug ^ ".lib")

let save ~dir ~slug (entries : entry list) =
  (try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let oc = open_out_bin (file dir slug) in
  Marshal.to_channel oc (entries : entry list) [];
  close_out oc

let load_one path : entry list =
  try
    let ic = open_in_bin path in
    let (e : entry list) = Marshal.from_channel ic in
    close_in ic; e
  with _ -> []

(* Entries from parts that come before this one, the latest definition of
   each name, leaving out the names this part must define itself and types
   this part cannot name. *)
let before ~dir ~slug ~exclude ~(known_types : string list) =
  if not (Sys.file_exists dir) then []
  else
    let files = Sys.readdir dir |> Array.to_list
                |> List.filter (fun f -> Filename.check_suffix f ".lib" && Filename.remove_extension f < slug)
                |> List.sort compare in
    let all = List.concat_map (fun f -> load_one (Filename.concat dir f)) files in
    let latest = List.fold_left (fun acc e ->
        (e.name, e) :: List.remove_assoc e.name acc) [] all in
    let rec nameable t = match Types.repr t with
      | Types.TCon (n, ts) ->
          (List.mem n [ "int"; "bool"; "char"; "string"; "float"; "unit"; "int64"; "list"; "option"; "result"; "array" ]
           || List.mem n known_types) && List.for_all nameable ts
      | Types.TTuple ts -> List.for_all nameable ts
      | Types.TArrow (_, a, b) -> nameable a && nameable b
      | _ -> true in
    List.filter (fun (n, e) -> not (List.mem n exclude) && nameable e.ty) (List.rev latest) |> List.map snd

(* Offer entries to the search the same way a part's own siblings are. *)
let register (entries : entry list) =
  List.iter (fun e ->
      let args, out = Types.unarrow e.ty in
      let args = List.map (fun (l, t) -> match l with Types.Optional _ -> Types.t_option t | _ -> t) args in
      let rec gen t = match Types.repr t with
        | Types.TVar x -> Types.TGen (Hashtbl.hash x land 0xff)
        | Types.TCon (n, ts) -> Types.TCon (n, List.map gen ts)
        | Types.TTuple ts -> Types.TTuple (List.map gen ts)
        | Types.TArrow (l, a, b) -> Types.TArrow (l, gen a, gen b)
        | t -> t in
      let names = List.map fst e.params in
      if names <> [] then begin
        let impl vals =
          match Eval.run ~budget:(max 1000 !Eval.fuel)
                  (List.combine names vals)
                  (Expr.Let (true, e.name, Expr.Lam (names, e.body),
                             Expr.App (Expr.Var e.name, List.map (fun v -> Expr.Lit v) vals))) with
          | Some v -> v | None -> raise Components.Undefined in
        Hashtbl.replace Eval.components e.name
          { Components.name = e.name; scheme = gen (Types.arrows args out); impl;
            ocaml = (fun a -> "(" ^ String.concat " " (e.name :: a) ^ ")") };
        Hashtbl.replace Components.siblings e.name (List.length names)
      end) entries

(* The entries a set of terms reaches, transitively, in library order. *)
let reached (entries : entry list) (bodies : Expr.t list) =
  let rec calls (e : Expr.t) = match e with
    | Expr.Call (n, args) -> n :: List.concat_map calls args
    | Expr.App (f, a) -> calls f @ List.concat_map calls a
    | Expr.Lam (_, b) -> calls b
    | Expr.Con (_, a) | Expr.Tuple a -> List.concat_map calls a
    | Expr.Poly (_, Some a) | Expr.Field (a, _) -> calls a
    | Expr.Record fs -> List.concat_map (fun (_, a) -> calls a) fs
    | Expr.If (c, a, b) -> calls c @ calls a @ calls b
    | Expr.Match (s, bs) -> calls s @ List.concat_map (fun (_, b) -> calls b) bs
    | Expr.Let (_, _, a, b) -> calls a @ calls b
    | _ -> [] in
  let rec close names acc =
    let fresh = List.filter (fun n -> List.exists (fun e -> e.name = n) entries && not (List.mem n acc)) names in
    if fresh = [] then acc
    else close (List.concat_map (fun n ->
        List.concat_map (fun e -> if e.name = n then calls e.body else []) entries) fresh) (acc @ fresh) in
  let used = close (List.concat_map calls bodies) [] in
  List.filter (fun e -> List.mem e.name used) entries
