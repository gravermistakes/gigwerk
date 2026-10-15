(* OCaml source for printers of a part's types, so a probe compiled against the
 * part's own interface can write any value it sees as an OCaml literal the
 * writer reads back. A value of a rigid type variable is printed generically
 * from its representation: the writer treats 'a as opaque, so all it needs
 * is a printing that is equal exactly when the values are. *)

open Types

let generic =
  {|let rec __gw_any (v : Stdlib.Obj.t) =
  if Stdlib.Obj.is_int v then Stdlib.string_of_int (Stdlib.Obj.obj v : int)
  else if Stdlib.Obj.tag v = Stdlib.Obj.string_tag then Stdlib.Printf.sprintf "%S" (Stdlib.Obj.obj v : string)
  else if Stdlib.Obj.tag v = Stdlib.Obj.double_tag then Stdlib.Printf.sprintf "%h" (Stdlib.Obj.obj v : float)
  else if Stdlib.Obj.tag v < Stdlib.Obj.no_scan_tag then
    "(__gw_block " ^ Stdlib.string_of_int (Stdlib.Obj.tag v) ^ " ("
    ^ Stdlib.String.concat ", " (Stdlib.List.init (Stdlib.Obj.size v) (fun i -> __gw_any (Stdlib.Obj.field v i))) ^ ",()))"
  else "<opaque>"
|}

exception Unprintable of string

let rec printer decls t : string =
  match repr t with
  | TCon ("int", []) -> "(fun (x : int) -> if Stdlib.(<) x 0 then \"(\" ^ Stdlib.string_of_int x ^ \")\" else Stdlib.string_of_int x)"
  | TCon ("int64", []) -> "(fun x -> \"(\" ^ Stdlib.Int64.to_string x ^ \"L)\")"
  | TCon ("float", []) -> "(fun x -> Stdlib.Printf.sprintf \"(%h)\" x)"
  | TCon ("bool", []) -> "Stdlib.string_of_bool"
  | TCon ("char", []) -> "(fun c -> Stdlib.Printf.sprintf \"%C\" c)"
  | TCon ("string", []) -> "(fun s -> Stdlib.Printf.sprintf \"%S\" s)"
  | TCon ("unit", []) -> "(fun () -> \"()\")"
  | TCon ("list", [ a ]) ->
      "(fun l -> \"[\" ^ Stdlib.String.concat \"; \" (Stdlib.List.map " ^ printer decls a ^ " l) ^ \"]\")"
  | TCon ("array", [ a ]) ->
      "(fun l -> \"[|\" ^ Stdlib.String.concat \"; \" (Stdlib.Array.to_list (Stdlib.Array.map " ^ printer decls a ^ " l)) ^ \"|]\")"
  | TCon ("option", [ a ]) ->
      "(function None -> \"None\" | Some x -> \"(Some \" ^ " ^ printer decls a ^ " x ^ \")\")"
  | TCon ("result", [ a; b ]) ->
      "(function Ok x -> \"(Ok \" ^ " ^ printer decls a ^ " x ^ \")\" | Error e -> \"(Error \" ^ "
      ^ printer decls b ^ " e ^ \")\")"
  | TTuple ts ->
      let xs = Stdlib.List.mapi (fun i _ -> "x" ^ Stdlib.string_of_int i) ts in
      "(fun (" ^ Stdlib.String.concat ", " xs ^ ") -> \"(\" ^ Stdlib.String.concat \", \" ["
      ^ Stdlib.String.concat "; " (Stdlib.List.map2 (fun x t -> printer decls t ^ " " ^ x) xs ts) ^ "] ^ \")\")"
  | TVar _ -> "(fun x -> __gw_any (Stdlib.Obj.repr x))"
  | TCon (n, args) ->
      (match List.find_opt (fun d -> d.name = n) decls with
       | Some d when d.kind <> Abstract && List.length args = List.length d.params ->
           "(__gw_pr_" ^ n ^ Stdlib.String.concat "" (Stdlib.List.map (fun a -> " " ^ printer decls a) args) ^ ")"
       | Some { kind = Alias _; _ } -> printer decls (Iface.expand decls t)
       | _ -> raise (Unprintable (to_string t)))
  | TArrow _ -> raise (Unprintable (to_string t))
  | _ -> raise (Unprintable (to_string t))

(* One recursive printer per declaration, parameterized by printers for the
   declaration's own type parameters. *)
let decl_printers decls =
  let one d =
    let params = Stdlib.List.map (fun p -> "__gw_p_" ^ p) d.params in
    let sub t =
      let rec go t = match repr t with
        | TVar v when List.mem v d.params -> TCon ("__param_" ^ v, [])
        | TCon (n, ts) -> TCon (n, Stdlib.List.map go ts)
        | TTuple ts -> TTuple (Stdlib.List.map go ts)
        | t -> t in go t in
    let pr t =
      let s = printer ({ name = "__param"; params = []; kind = Abstract } :: decls) (sub t) in s in
    let pr t = try pr t with Unprintable _ ->
      (match repr t with TVar v -> "__gw_p_" ^ v | _ -> raise (Unprintable (to_string t))) in
    let pr t = match repr t with TVar v when List.mem v d.params -> "__gw_p_" ^ v | _ -> pr t in
    let body = match d.kind with
      | Variant ctors ->
          "function " ^ Stdlib.String.concat " | " (Stdlib.List.map (fun (c, args) ->
              match args with
              | [] -> c ^ " -> \"" ^ c ^ "\""
              | [ t ] -> c ^ " x -> \"(" ^ c ^ " \" ^ " ^ pr t ^ " x ^ \")\""
              | ts ->
                  let xs = Stdlib.List.mapi (fun i _ -> "x" ^ Stdlib.string_of_int i) ts in
                  c ^ " (" ^ Stdlib.String.concat ", " xs ^ ") -> \"(" ^ c ^ " (\" ^ Stdlib.String.concat \", \" ["
                  ^ Stdlib.String.concat "; " (Stdlib.List.map2 (fun x t -> pr t ^ " " ^ x) xs ts) ^ "] ^ \"))\"")
              ctors)
      | Record fields ->
          "fun r -> \"{ \" ^ Stdlib.String.concat \"; \" ["
          ^ Stdlib.String.concat "; " (Stdlib.List.map (fun (f, t) ->
              "\"" ^ f ^ " = \" ^ " ^ pr t ^ " r." ^ f) fields) ^ "] ^ \" }\""
      | Poly rows ->
          "function " ^ Stdlib.String.concat " | " (Stdlib.List.map (fun (tag, arg) ->
              match arg with
              | None -> "`" ^ tag ^ " -> \"`" ^ tag ^ "\""
              | Some t -> "`" ^ tag ^ " x -> \"(`" ^ tag ^ " \" ^ " ^ pr t ^ " x ^ \")\"") rows)
      | Alias t -> pr t
      | Abstract -> "fun _ -> \"<abstract>\""
    in
    "__gw_pr_" ^ d.name ^ " " ^ Stdlib.String.concat " " params ^ (if params = [] then "" else " ")
    ^ "= " ^ body
  in
  match decls with
  | [] -> ""
  | _ ->
      let printable = List.filter_map (fun d ->
          try Some (one d) with Unprintable _ -> None) decls in
      if printable = [] then ""
      else "let rec " ^ Stdlib.String.concat "\nand " printable ^ "\n"
