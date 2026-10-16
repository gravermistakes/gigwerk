type error =
  | Empty_id of int
  | Empty_statement of int
  | Empty_acceptance of int
  | Duplicate_id of string
  | Unknown_dependency of { id : string; dependency : string }
  | Unknown_acceptance_target of string
  | Unknown_acceptance of int * string
  | Malformed_line of int * string

type t = {
  requirements : Production.requirement list;
  source : string;
}

let trim = String.trim

let starts_with s prefix =
  let n = String.length prefix in
  String.length s >= n && String.sub s 0 n = prefix

let split_once s ch =
  match String.index_opt s ch with
  | None -> None
  | Some i -> Some (String.sub s 0 i, String.sub s (i + 1) (String.length s - i - 1))

let add_dep id dep reqs =
  List.map
    (fun r ->
      if r.Production.id = id then
        { r with depends_on = r.depends_on @ [ dep ] }
      else r)
    reqs

let set_acceptance id accept reqs =
  List.map
    (fun r ->
      if r.Production.id = id then { r with acceptance = Some accept } else r)
    reqs

(* An acceptance argument names a path or target INSIDE the workspace. No
   absolute paths, no parent traversal, no leading dash (which dune would read
   as a flag). There is no shell to quote against; this guards the argv itself. *)
let safe_argument a =
  a <> ""
  && a.[0] <> '-'
  && a.[0] <> '/'
  && not (String.length a >= 2 && String.sub a 0 2 = "..")
  && (let ok = ref true in
      String.iter
        (fun c ->
          match c with
          | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' | '.' | '/' -> ()
          | _ -> ok := false)
        a;
      !ok)
  && (let rec no_dotdot i =
        i + 1 >= String.length a
        || not (a.[i] = '.' && a.[i + 1] = '.')
           && no_dotdot (i + 1)
      in
      no_dotdot 0)

let words s =
  String.split_on_char ' ' s
  |> List.concat_map (String.split_on_char '\t')
  |> List.filter (fun w -> w <> "")

(* The whole hole closes here. Anything not matching a declared verb is an
   error, so unrecognised text cannot reach Verifier at all. *)
let parse_acceptance line_no text =
  match words text with
  | [ "dune"; "build" ] -> Ok Production.Dune_build
  | [ "dune"; ("runtest" | "test") ] -> Ok (Production.Dune_runtest None)
  | [ "dune"; ("runtest" | "test"); dir ] when safe_argument dir ->
      Ok (Production.Dune_runtest (Some dir))
  | [ "dune"; "exec"; target ] when safe_argument target ->
      Ok (Production.Dune_exec target)
  | [ "fmt"; "check" ] | [ "dune"; "fmt" ] -> Ok Production.Fmt_check
  | _ -> Error (Unknown_acceptance (line_no, text))

let find id reqs = List.find_opt (fun r -> r.Production.id = id) reqs


let parse source =
  let lines = String.split_on_char '\n' source in
  let rec loop line_no reqs directives = function
    | [] ->
        let directives = List.rev directives in
        let rec validate = function
          | [] -> Ok ()
          | `Depends (id, dep) :: rest ->
              if Option.is_none (find id reqs) then
                Error (Unknown_dependency { id; dependency = dep })
              else if Option.is_none (find dep reqs) then
                Error (Unknown_dependency { id; dependency = dep })
              else validate rest
          | `Accept (id, _) :: rest ->
              if Option.is_none (find id reqs) then
                Error (Unknown_acceptance_target id)
              else validate rest
        in
        begin match validate directives with
        | Error e -> Error e
        | Ok () ->
            let reqs =
              List.fold_left
                (fun acc d ->
                  match d with
                  | `Depends (id, dep) -> add_dep id dep acc
                  | `Accept (id, a) -> set_acceptance id a acc)
                reqs directives
            in
            Ok { requirements = reqs; source }
        end
    | raw :: rest ->
        let line = trim raw in
        if line = "" || (String.length line > 0 && line.[0] = '#') then
          loop (line_no + 1) reqs directives rest
        else if starts_with line "req " then
          begin match split_once (String.sub line 4 (String.length line - 4)) ':' with
          | None -> Error (Malformed_line (line_no, raw))
          | Some (id, statement) ->
              let id = trim id and statement = trim statement in
              if id = "" then Error (Empty_id line_no)
              else if statement = "" then Error (Empty_statement line_no)
              else if Option.is_some (find id reqs) then Error (Duplicate_id id)
              else
                loop (line_no + 1)
                  (reqs @ [ { Production.id; statement; depends_on = []; acceptance = None } ])
                  directives rest
          end
        else if starts_with line "depends " then
          begin match split_once (String.sub line 8 (String.length line - 8)) ':' with
          | None -> Error (Malformed_line (line_no, raw))
          | Some (id, deps) ->
              let id = trim id in
              let deps =
                String.split_on_char ',' deps |> List.map trim
                |> List.filter (fun x -> x <> "")
              in
              (* Shape only HERE. Existence is still checked, once, by the
                 `validate` pass at end-of-parse -- doing it inline as well was
                 redundant. What does NOT belong at parse time is cycle
                 detection: both ids of a cycle exist, so a cycle survives
                 parsing by construction and Production_graph catches it, naming
                 the whole path rather than one edge. *)
              if id = "" || deps = [] then Error (Malformed_line (line_no, raw))
              else
                loop (line_no + 1) reqs
                  (List.fold_left
                     (fun ds d -> `Depends (id, d) :: ds)
                     directives deps)
                  rest
          end
        else if starts_with line "accept " then
          begin match split_once (String.sub line 7 (String.length line - 7)) ':' with
          | None -> Error (Malformed_line (line_no, raw))
          | Some (id, command) ->
              let id = trim id and command = trim command in
              if id = "" then Error (Malformed_line (line_no, raw))
              else if command = "" then Error (Empty_acceptance line_no)
              else (
                match parse_acceptance line_no command with
                | Error e -> e |> fun e -> Error e
                | Ok a ->
                    loop (line_no + 1) reqs
                      (`Accept (id, a) :: directives) rest)
          end
        else Error (Malformed_line (line_no, raw))
  in
  loop 1 [] [] lines

let requirements t = t.requirements
