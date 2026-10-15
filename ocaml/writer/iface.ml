(* A part's interface, read with the compiler's own parser: the declarations it
 * names and the values it asks for, in the writer's types. Anything the
 * writer's types cannot express (a functor, a module type, Base's Map.M) is
 * kept as Unreadable with its source, so the part can be declined by name
 * rather than half-read. *)

open Parsetree
open Types

type value_spec = { vname : string; vty : ty }

type t = {
  decls : decl list;
  values : value_spec list;
  unreadable : string list;        (* items the writer cannot represent *)
  opens : string list;
}

exception Unsupported of string

let longident_last li = Longident.last li

(* Type constructors the writer knows under another spelling. *)
let normalize_con name args =
  match name, args with
  | ("result" | "Result.t" | "Base.Result.t" | "Stdlib.result"), [ _; _ ] -> TCon ("result", args)
  | ("Int64.t" | "Base.Int64.t"), [] -> t_int64
  | ("Option.t" | "option"), [ a ] -> t_option a
  | ("List.t" | "list"), [ a ] -> t_list a
  | ("Array.t" | "array"), [ a ] -> t_array a
  | ("Int.t"), [] -> t_int
  | ("String.t"), [] -> t_string
  | ("Char.t"), [] -> t_char
  | ("Bool.t"), [] -> t_bool
  | ("Float.t"), [] -> t_float
  | _ -> TCon (name, args)

let rec ty_of_core (ct : core_type) : ty =
  match ct.ptyp_desc with
  | Ptyp_var v -> TVar v
  | Ptyp_arrow (l, a, b) ->
      let lbl = match l with
        | Asttypes.Nolabel -> Nolabel
        | Asttypes.Labelled s -> Labelled s
        | Asttypes.Optional s -> Optional s in
      TArrow (lbl, ty_of_core a, ty_of_core b)
  | Ptyp_tuple ts -> TTuple (List.map ty_of_core ts)
  | Ptyp_constr ({ txt; _ }, args) ->
      let name = match Longident.flatten txt with
        | parts -> String.concat "." parts
        | exception _ -> raise (Unsupported "applicative functor path") in
      normalize_con name (List.map ty_of_core args)
  | Ptyp_poly ([], t) -> ty_of_core t
  | Ptyp_variant (rows, _, _) ->
      (* An inline polymorphic variant is named by its tags, so two
         occurrences of the same row are the same type. *)
      let tags = List.map (fun r -> match r.prf_desc with
          | Rtag ({ txt; _ }, _, []) -> (txt, None)
          | Rtag ({ txt; _ }, _, [ t ]) -> (txt, Some (ty_of_core t))
          | _ -> raise (Unsupported "polymorphic variant row")) rows in
      TCon ("[" ^ String.concat "|" (List.map fst tags) ^ "]", [])
  | _ -> raise (Unsupported (Format.asprintf "%a" Pprintast.core_type ct))

let poly_rows (ct : core_type) =
  match ct.ptyp_desc with
  | Ptyp_variant (rows, _, _) ->
      Some (List.map (fun r -> match r.prf_desc with
          | Rtag ({ txt; _ }, _, []) -> (txt, None)
          | Rtag ({ txt; _ }, _, [ t ]) -> (txt, Some (ty_of_core t))
          | _ -> raise (Unsupported "polymorphic variant row")) rows)
  | _ -> None

let decl_of (td : type_declaration) : decl =
  let params = List.map (fun (ct, _) -> match ct.ptyp_desc with
      | Ptyp_var v -> v | _ -> raise (Unsupported "type parameter")) td.ptype_params in
  let kind =
    match td.ptype_kind, td.ptype_manifest with
    | Ptype_variant cds, _ ->
        Variant (List.map (fun cd ->
            let args = match cd.pcd_args with
              | Pcstr_tuple ts -> List.map ty_of_core ts
              | Pcstr_record _ -> raise (Unsupported "inline record") in
            (cd.pcd_name.txt, args)) cds)
    | Ptype_record lds, _ -> Record (List.map (fun ld -> (ld.pld_name.txt, ty_of_core ld.pld_type)) lds)
    | Ptype_abstract, None -> Abstract
    | Ptype_abstract, Some ct ->
        (match poly_rows ct with Some rows -> Poly rows | None -> Alias (ty_of_core ct))
    | Ptype_open, _ -> raise (Unsupported "open type")
  in
  { name = td.ptype_name.txt; params; kind }

let of_signature (sg : signature) : t =
  let decls = ref [] and values = ref [] and unreadable = ref [] and opens = ref [] in
  let src item = Format.asprintf "%a" Pprintast.signature [ item ] in
  List.iter (fun item ->
      match item.psig_desc with
      | Psig_type (_, tds) ->
          List.iter (fun td ->
              try decls := decl_of td :: !decls
              with Unsupported _ -> unreadable := src item :: !unreadable) tds
      | Psig_value vd ->
          (try values := { vname = vd.pval_name.txt; vty = ty_of_core vd.pval_type } :: !values
           with Unsupported _ -> unreadable := src item :: !unreadable)
      | Psig_open od ->
          opens := String.concat "." (Longident.flatten od.popen_expr.txt) :: !opens
      | _ -> unreadable := src item :: !unreadable) sg;
  { decls = List.rev !decls; values = List.rev !values;
    unreadable = List.rev !unreadable; opens = List.rev !opens }

let parse_string s =
  let lexbuf = Lexing.from_string s in
  of_signature (Parse.interface lexbuf)

let read_file path =
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic; s

let parse_file path = parse_string (read_file path)

(* Resolve aliases (type base = int) so the writer sees the real type. *)
let rec expand decls t =
  match repr t with
  | TCon (n, args) ->
      (match List.find_opt (fun d -> d.name = n) decls with
       | Some { kind = Alias body; params; _ } when List.length params = List.length args ->
           let sub = List.combine params (List.map (expand decls) args) in
           let rec subst t = match repr t with
             | TVar v -> (match List.assoc_opt v sub with Some t -> t | None -> t)
             | TCon (n, ts) -> TCon (n, List.map subst ts)
             | TTuple ts -> TTuple (List.map subst ts)
             | TArrow (l, a, b) -> TArrow (l, subst a, subst b)
             | t -> t in
           expand decls (subst body)
       | _ -> TCon (n, List.map (expand decls) args))
  | TTuple ts -> TTuple (List.map (expand decls) ts)
  | TArrow (l, a, b) -> TArrow (l, expand decls a, expand decls b)
  | t -> t

let _ = longident_last
