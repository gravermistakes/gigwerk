let pass = ref 0
let fail = ref 0

let check label condition =
  if condition then incr pass
  else begin incr fail; Printf.eprintf "FAIL: %s\n" label end

let () =
  let source =
    "req a : first\nreq b : second\ndepends a : b\n"
  in
  match Specification.parse source with
  | Error (Specification.Unknown_dependency { id = "a"; dependency = "b" }) -> incr pass
  | _ -> check "dependencies must reference already-declared requirements" false;
  Printf.printf "specification_ordering: %d passed, %d failed\n" !pass !fail;
  exit (if !fail = 0 then 0 else 1)
