open Gigwerk

let pass = ref 0
let fail = ref 0
let check name condition =
  if condition then incr pass
  else (incr fail; Printf.printf "FAIL %s\n" name)

let ids rs = List.map (fun r -> r.Production.id) rs
let parse s = Specification.parse s

let () =
  check "one requirement"
    (match parse "req a : build the thing" with
     | Ok s -> ids (Specification.requirements s) = ["a"]
     | Error _ -> false);
  check "declaration order"
    (match parse "req b : second\nreq a : first" with
     | Ok s -> ids (Specification.requirements s) = ["b"; "a"]
     | Error _ -> false);
  check "multiple dependencies preserve order"
    (match parse "req a : a\nreq b : b\nreq c : c\ndepends c : a,b" with
     | Ok s -> (List.hd (List.tl (List.tl (Specification.requirements s)))).Production.depends_on = ["a"; "b"]
     | Error _ -> false);
  check "acceptance"
    (match parse "req a : run\naccept a : dune test" with
     | Ok s -> (List.hd (Specification.requirements s)).Production.acceptance = Some "dune test"
     | Error _ -> false);
  check "duplicate ids"
    (match parse "req a : one\nreq a : two" with
     | Error (Specification.Duplicate_id "a") -> true | _ -> false);
  check "unknown dependency"
    (match parse "req a : one\ndepends a : missing" with
     | Error (Specification.Unknown_dependency _) -> true | _ -> false);
  check "unknown acceptance target"
    (match parse "accept missing : true" with
     | Error (Specification.Unknown_acceptance_target "missing") -> true | _ -> false);
  check "malformed line"
    (match parse "wat" with
     | Error (Specification.Malformed_line _) -> true | _ -> false);
  check "blank lines and comments"
    (match parse "# comment\n\nreq a : one\n # another" with
     | Ok s -> ids (Specification.requirements s) = ["a"]
     | Error _ -> false);
  check "empty id"
    (match parse "req : statement" with
     | Error (Specification.Empty_id _) -> true | _ -> false);
  check "empty statement"
    (match parse "req a :   " with
     | Error (Specification.Empty_statement _) -> true | _ -> false);
  check "empty acceptance"
    (match parse "req a : one\naccept a :   " with
     | Error (Specification.Empty_acceptance _) -> true | _ -> false);
  Printf.printf "specification: %d passed, %d failed\n" !pass !fail;
  if !fail <> 0 then exit 1
