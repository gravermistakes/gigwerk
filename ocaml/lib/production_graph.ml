type error = Cycle of string list | Unknown_requirement of string

type t = {
  requirements : Production.requirement list;
}

let build specification =
  let requirements = Specification.requirements specification in
  let known id = List.exists (fun r -> r.Production.id = id) requirements in
  let rec validate = function
    | [] -> Ok ()
    | r :: rest ->
        match List.find_opt (fun dep -> not (known dep)) r.Production.depends_on with
        | Some dep -> Error (Unknown_requirement dep)
        | None -> validate rest
  in
  let rec visit stack seen = function
    | [] -> Ok seen
    | id :: rest ->
        if List.mem id stack then
          let rec suffix = function
            | [] -> [id]
            | x :: xs when x = id -> x :: xs @ [id]
            | _ :: xs -> suffix xs
          in Error (Cycle (suffix (List.rev stack)))
        else if List.mem id seen then visit stack seen rest
        else
          match List.find_opt (fun r -> r.Production.id = id) requirements with
          | None -> Error (Unknown_requirement id)
          | Some r ->
              begin match visit (id :: stack) seen r.Production.depends_on with
              | Error e -> Error e
              | Ok seen' -> visit stack (id :: seen') rest
              end
  in
  match validate requirements with
  | Error e -> Error e
  | Ok () ->
      begin match visit [] [] (List.map (fun r -> r.Production.id) requirements) with
      | Error e -> Error e
      | Ok _ -> Ok { requirements }
      end

let roots t =
  List.filter (fun r -> r.Production.depends_on = []) t.requirements

let ready t ~completed =
  List.filter
    (fun r ->
      not (List.mem r.Production.id completed)
      && List.for_all (fun dep -> List.mem dep completed) r.Production.depends_on)
    t.requirements
