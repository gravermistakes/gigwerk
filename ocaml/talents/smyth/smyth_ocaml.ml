(* Smyth, booked: run its synthesizer on a sketch and print what it derived as
 * an OCaml expression. Nothing here searches; the search is Smyth's.
 *
 *   smyth_ocaml <sketch-file>
 *
 * Exit 0 and the expression on stdout, or exit 1 and Smyth's reason on
 * stderr. Smyth's core types map onto OCaml's: Nat to non-negative int,
 * Boolean to bool, List to list, Option to option; any other datatype is
 * printed with its own constructors. *)

open Smyth
open Lang

let keywords = [ "and"; "as"; "begin"; "class"; "do"; "done"; "downto"; "else"; "end"; "exception";
                 "external"; "for"; "fun"; "function"; "functor"; "if"; "in"; "include"; "inherit";
                 "lazy"; "let"; "match"; "method"; "module"; "mutable"; "new"; "object"; "of"; "open";
                 "or"; "private"; "rec"; "sig"; "struct"; "then"; "to"; "try"; "type"; "val";
                 "virtual"; "when"; "while"; "with"; "mod"; "land"; "lor"; "lxor"; "lsl"; "lsr"; "asr" ]

let id x = if List.mem x keywords then x ^ "_" else x

let counter = ref 0
let fresh base = incr counter; Printf.sprintf "%s_%d" base !counter

let rec pat = function
  | PVar x -> id x
  | PWildcard -> "_"
  | PTuple [] -> "()"
  | PTuple ps -> "(" ^ String.concat ", " (List.map pat ps) ^ ")"

let rec ocaml fills e =
  let go = ocaml fills in
  match e with
  | EFix (name, PatParam p, body) ->
      (match name with
       | Some f -> Printf.sprintf "(let rec %s %s = %s in %s)" (id f) (pat p) (go body) (id f)
       | None -> Printf.sprintf "(fun %s -> %s)" (pat p) (go body))
  | EFix (_, TypeParam _, body) -> go body
  | EApp (_, f, EAType _) -> go f
  | EApp (_, f, EAExp a) -> Printf.sprintf "(%s %s)" (go f) (go a)
  | EVar x -> id x
  | ETuple [] -> "()"
  | ETuple es -> "(" ^ String.concat ", " (List.map go es) ^ ")"
  | EProj (n, i, t) ->
      let v = fresh "gw_p" in
      let slots = List.init n (fun k -> if k = i - 1 then v else "_") in
      Printf.sprintf "(let (%s) = %s in %s)" (String.concat ", " slots) (go t) v
  | ECtor (c, _, arg) -> ctor fills c arg
  | ECase (s, branches) -> case fills (go s) branches
  | EHole h ->
      (match List.assoc_opt h fills with
       | Some e -> go e
       | None -> failwith (Printf.sprintf "hole %d left unfilled" h))
  | EAssert _ -> failwith "an assertion inside a derived term"
  | ETypeAnnotation (e, _) -> go e

and ctor fills c arg =
  let go = ocaml fills in
  match c, arg with
  | "Z", _ -> "0"
  | "S", a -> Printf.sprintf "(%s + 1)" (go a)
  | "T", _ -> "true"
  | "F", _ -> "false"
  | "Nil", _ -> "[]"
  | "Cons", ETuple [ h; t ] -> Printf.sprintf "(%s :: %s)" (go h) (go t)
  | "Cons", a -> let h = fresh "gw_h" and t = fresh "gw_t" in
      Printf.sprintf "(let (%s, %s) = %s in %s :: %s)" h t (go a) h t
  | _, ETuple [] -> c
  | _, a -> Printf.sprintf "(%s %s)" c (go a)

and case fills s branches =
  let go = ocaml fills in
  let ctors = List.map fst branches in
  let body c = List.assoc_opt c branches in
  if List.mem "Z" ctors || List.mem "S" ctors then
    let v = fresh "gw_n" in
    let z = match body "Z" with Some (_, b) -> go b | None -> "assert false" in
    let sbr = match body "S" with
      | Some (p, b) -> Printf.sprintf "let %s = %s - 1 in %s" (pat p) v (go b)
      | None -> "assert false" in
    Printf.sprintf "(let %s = %s in if %s = 0 then %s else %s)" v s v z sbr
  else if List.mem "T" ctors || List.mem "F" ctors then
    let t = match body "T" with Some (_, b) -> go b | None -> "assert false" in
    let f = match body "F" with Some (_, b) -> go b | None -> "assert false" in
    Printf.sprintf "(if %s then %s else %s)" s t f
  else
    let arm (c, (p, b)) =
      let lhs, bind = match c, p with
        | "Nil", _ -> ("[]", "")
        | "Cons", PTuple [ h; t ] -> (Printf.sprintf "(%s :: %s)" (pat h) (pat t), "")
        | "Cons", PVar x ->
            let h = fresh "gw_h" and t = fresh "gw_t" in
            (Printf.sprintf "(%s :: %s)" h t, Printf.sprintf "let %s = (%s, %s) in " (id x) h t)
        | "Cons", _ -> ("(_ :: _)", "")
        | _, PTuple [] -> (c, "")
        | _, PWildcard -> (c ^ " _", "")
        | _, p -> (Printf.sprintf "%s %s" c (pat p), "") in
      Printf.sprintf "%s -> %s%s" lhs bind (go b) in
    Printf.sprintf "(match %s with %s)" s (String.concat " | " (List.map arm branches))

let () =
  match Sys.argv with
  | [| _; file |] ->
      let ic = open_in_bin file in
      let sketch = really_input_string ic (in_channel_length ic) in
      close_in ic;
      (match Endpoint.solve ~sketch with
       | Ok { Endpoint.hole_fillings = fills :: _; _ } ->
           let main = List.fold_left (fun acc (h, _) -> min acc h) max_int fills in
           print_endline (ocaml fills (EHole main))
       | Ok _ -> prerr_endline "no solutions"; exit 1
       | Error (Endpoint.ParseError _) -> prerr_endline "parse error"; exit 1
       | Error (Endpoint.TypeError _) -> prerr_endline "type error"; exit 1
       | Error (Endpoint.EvalError s) -> prerr_endline ("eval error: " ^ s); exit 1
       | Error (Endpoint.TimedOut t) -> Printf.eprintf "timed out after %.1fs\n" t; exit 1
       | Error Endpoint.NoSolutions -> prerr_endline "no solutions"; exit 1
       | Error Endpoint.PartialNotSubsetFull -> prerr_endline "partial not subset"; exit 1)
  | _ -> prerr_endline "usage: smyth_ocaml <sketch-file>"; exit 2
