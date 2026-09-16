let pass = ref 0
let fail = ref 0

let check label condition =
  if condition then incr pass
  else begin
    incr fail;
    Printf.eprintf "FAIL: %s\n" label
  end

let parse source =
  match Specification.parse source with
  | Ok specification -> specification
  | Error _ -> failwith "test specification must parse"

let ids requirements = List.map (fun r -> r.Production.id) requirements

let () =
  let specification =
    parse "req a : first\nreq b : second\nreq c : third\ndepends b : a\ndepends c : b\n"
  in
  begin match Production_graph.build specification with
  | Error _ -> check "linear graph builds" false
  | Ok graph ->
      check "root contains a" (ids (Production_graph.roots graph) = ["a"]);
      check "a is initially ready" (ids (Production_graph.ready graph ~completed:[]) = ["a"]);
      check "b becomes ready" (ids (Production_graph.ready graph ~completed:["a"]) = ["b"]);
      check "c becomes ready after b" (ids (Production_graph.ready graph ~completed:["a"; "b"]) = ["c"])
  end;
  let cycle =
    parse "req a : first\nreq b : second\ndepends a : b\ndepends b : a\n"
  in
  begin match Production_graph.build cycle with
  | Error (Production_graph.Cycle path) -> check "cycle is rejected" (List.length path >= 3)
  | _ -> check "cycle is rejected" false
  end;
  let unknown = parse "req a : first\ndepends a : missing\n" in
  begin match Production_graph.build unknown with
  | Error (Production_graph.Unknown_requirement "missing") -> incr pass
  | _ -> check "unknown dependency is rejected" false
  end;
  Printf.printf "production_graph: %d passed, %d failed\n" !pass !fail;
  exit (if !fail = 0 then 0 else 1)
