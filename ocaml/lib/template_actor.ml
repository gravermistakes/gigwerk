let create ~templates =
  let module M : Code_actor.S = struct
    type context = Code_actor.context

    let produce _context requirement workspace =
      let template =
        match List.assoc_opt requirement.Production.id templates with
        | Some s -> Some s
        | None -> List.assoc_opt "default" templates
      in
      match template with
      | None -> Error (Code_actor.Actor_error ("no template for " ^ requirement.id))
      | Some contents ->
          let path = requirement.id ^ ".ml" in
          begin match Workspace.write workspace ~path ~contents with
          | Error e -> Error (Code_actor.Workspace_error (match e with
              | Workspace.Invalid_root s | Workspace.Invalid_path s | Workspace.Io_error s -> s))
          | Ok () -> Ok { Production.requirement_id = requirement.id; paths = [path] }
          end
  end in
  (module M : Code_actor.S)
