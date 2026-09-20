type error =
  | Empty_id of int
  | Empty_statement of int
  | Empty_acceptance of int
  | Duplicate_id of string
  | Unknown_dependency of { id : string; dependency : string }
  | Unknown_acceptance_target of string
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

let set_acceptance id command reqs =
  List.map
    (fun r ->
      if r.Production.id = id then { r with acceptance = Some command } else r)
    reqs

let find id reqs = List.find_opt (fun r -> r.Production.id = id) reqs


let parse source =
  let lines = String.split_on_char '\n' source in
  let rec loop line_no reqs directives = function
    | [] ->
        let directives = List.rev directives in
        let rec validate = function
          | [] -> Ok ()
          | (kind, id, value, n) :: rest -> (
              match kind with
              | `Depends ->
                  if Option.is_none (find id reqs) then
                    Error (Unknown_dependency { id; dependency = value })
                  else if Option.is_none (find value reqs) then
                    Error (Unknown_dependency { id; dependency = value })
                  else validate rest
              | `Accept ->
                  if Option.is_none (find id reqs) then
                    Error (Unknown_acceptance_target id)
                  else if trim value = "" then Error (Empty_acceptance n)
                  else validate rest)
        in
        begin match validate directives with
        | Error e -> Error e
        | Ok () ->
            let reqs =
              List.fold_left
                (fun acc (kind, id, value, _) ->
                  match kind with
                  | `Depends -> add_dep id value acc
                  | `Accept -> set_acceptance id value acc)
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
              (* Shape only. Whether a dependency EXISTS, and whether the
                 dependencies form a cycle, belong to Production_graph -- it
                 is the thing that can say "a -> b -> a" instead of naming one
                 edge, and its Cycle/Unknown_requirement errors are the tested
                 ones. Validating existence here made those unreachable and
                 broke test_production_graph. *)
              if id = "" || deps = [] then Error (Malformed_line (line_no, raw))
              else
                loop (line_no + 1) reqs
                  (List.fold_left
                     (fun ds d -> (`Depends, id, d, line_no) :: ds)
                     directives deps)
                  rest
          end
        else if starts_with line "accept " then
          begin match split_once (String.sub line 7 (String.length line - 7)) ':' with
          | None -> Error (Malformed_line (line_no, raw))
          | Some (id, command) ->
              let id = trim id and command = trim command in
              if id = "" then Error (Malformed_line (line_no, raw))
              else
                loop (line_no + 1) reqs
                  ((`Accept, id, command, line_no) :: directives) rest
          end
        else Error (Malformed_line (line_no, raw))
  in
  loop 1 [] [] lines

let requirements t = t.requirements
