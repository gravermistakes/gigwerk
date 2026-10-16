(* Admission to the roster: the same material, performed twice, must come out
 * the same.
 *
 * Everything downstream leans on the talent being deterministic: a derived
 * result is cacheable because the same contract gives the same code forever,
 * and an outcome is evidence about the talent only if the talent would do it
 * again. So before a talent is trusted with a part it performs the part twice,
 * each time on a freshly staged copy of the material in a different directory,
 * and the two performances must agree on the phases walked, on the paths
 * delivered, and on every byte of every delivered file.
 *
 * Two runs can prove a talent nondeterministic. They cannot prove it
 * deterministic: a clock read that lands in the same second, a seed that
 * happens to repeat, a scheduler that happens to serialize, all pass. Admitted
 * means "not caught", and is named for what it is.
 *
 * The staging directories differ on purpose. An artifact that embeds where it
 * was performed is not the same artifact twice, and is rejected for it. *)

type rejection =
  | Did_not_perform of { performance : int; why : string }
  | Different_trail of { requirement : string; first : string list; second : string list }
  | Different_paths of { requirement : string; first : string list; second : string list }
  | Diverged of { requirement : string; path : string }
  | Unreadable of { requirement : string; path : string; why : string }

type admitted = {
  talent : string;
  artifacts : (string * Digest.t) list;   (* delivered path, digest of its bytes *)
}

let rejection_to_string = function
  | Did_not_perform { performance; why } ->
      Printf.sprintf "performance %d delivered nothing: %s" performance why
  | Different_trail { requirement; first; second } ->
      Printf.sprintf "%s: walked [%s] then [%s]" requirement
        (String.concat " " first) (String.concat " " second)
  | Different_paths { requirement; first; second } ->
      Printf.sprintf "%s: delivered [%s] then [%s]" requirement
        (String.concat " " first) (String.concat " " second)
  | Diverged { requirement; path } ->
      Printf.sprintf "%s: %s differs between the two performances" requirement path
  | Unreadable { requirement; path; why } ->
      Printf.sprintf "%s: %s was delivered but cannot be read: %s" requirement path why

(* Every requirement produced, or the reason one was not. *)
let delivered performance (r : Producer.result) =
  let rec go acc = function
    | [] when acc = [] -> Error (Did_not_perform { performance; why = "no requirement produced" })
    | [] -> Ok (List.rev acc)
    | (id, Producer.Produced (a, trail)) :: rest -> go ((id, a, trail) :: acc) rest
    | (id, Producer.Production_failed why) :: _ ->
        Error (Did_not_perform { performance; why = id ^ ": " ^ why })
    | (id, Producer.Production_refused words) :: _ ->
        Error (Did_not_perform { performance; why = id ^ ": refused"
          ^ (match words with Some w -> ": " ^ w | None -> "") })
  in
  (* The status is not consulted: a production that went unverified still
     delivered, and admission asks whether it delivers the same thing twice,
     not whether it passed. *)
  go [] r.Producer.outcomes

let read_in root path =
  match Workspace.create root with
  | Error (Workspace.Invalid_root e | Workspace.Invalid_path e | Workspace.Io_error e) -> Error e
  | Ok ws ->
      Workspace.read ws ~path
      |> Result.map_error (function
           | Workspace.Invalid_root e | Workspace.Invalid_path e | Workspace.Io_error e -> e)

let check ~(actor : (module Code_actor.S)) ~specification ~stage ~obligations ~now =
  let module A = (val actor : Code_actor.S) in
  let perform () =
    let root = stage () in
    (root, Producer.run ~actor ~specification ~workspace:root ~obligations ~now)
  in
  let root1, r1 = perform () in
  let root2, r2 = perform () in
  let ( let* ) = Result.bind in
  let* d1 = delivered 1 r1 in
  let* d2 = delivered 2 r2 in
  let rec compare_all acc = function
    | [], [] -> Ok { talent = A.name; artifacts = List.rev acc }
    | (id, a1, t1) :: rest1, (id2, a2, t2) :: rest2 when id = id2 ->
        let p1 = a1.Production.paths and p2 = a2.Production.paths in
        if t1 <> t2 then Error (Different_trail { requirement = id; first = t1; second = t2 })
        else if p1 <> p2 then Error (Different_paths { requirement = id; first = p1; second = p2 })
        else
          let rec files acc = function
            | [] -> Ok acc
            | path :: more ->
                (match read_in root1 path, read_in root2 path with
                 | Error why, _ | _, Error why ->
                     Error (Unreadable { requirement = id; path; why })
                 | Ok b1, Ok b2 when b1 <> b2 -> Error (Diverged { requirement = id; path })
                 | Ok b1, Ok _ -> files ((path, Digest.string b1) :: acc) more)
          in
          let* acc = files acc p1 in
          compare_all acc (rest1, rest2)
    | (id, _, _) :: _, _ | [], (id, _, _) :: _ ->
        Error (Did_not_perform { performance = 2;
                                 why = id ^ ": the two performances produced different requirements" })
  in
  compare_all [] (d1, d2)
