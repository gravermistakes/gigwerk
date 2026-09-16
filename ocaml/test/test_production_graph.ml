let pass = ref 0
let fail = ref 0

let check label condition =
  if condition then incr pass
  else begin
    incr fail;
    Printf.eprintf "FAIL: %s\n" label
  end

let requirement id depends_on =
  Production.{ id; statement = "statement"; depends_on; acceptance = None }

let spec requirements =
  Specification.of_requirements requirements

let () =
  let a = requirement "a" [] in
  let b = requirement "b" ["a"] in
  let c = requirement "c" ["b"] in
  begin match Production_graph.build (spec [a; b; c]) with
  | Error _ -> check "linear graph builds" false
  | Ok graph ->
      check "root contains a" (List.map (fun r -> r.Production.id) (Production_graph.roots graph) = ["a"]);
      let ready0 = Production_graph.ready graph ~completed:[] in
      check "a is initially ready" (List.map (fun r -> r.Production.id) ready0 = ["a"]);
      let ready1 = Production_graph.ready graph ~completed:["a"] in
      check "b becomes ready" (List.map (fun r -> r.Production.id) ready1 = ["b"])
  end;
  let cycle = [requirement "a" ["b"]; requirement "b" ["a"]] in
  begin match Production_graph.build (spec cycle) with
  | Error (Production_graph.Cycle path) -> check "cycle is rejected" (List.length path >= 3)
  | _ -> check "cycle is rejected" false
  end;
  match Production_graph.build (spec [requirement "a" ["missing"]]) with
  | Error (Production_graph.Unknown_requirement "missing") -> incr pass
  | _ -> check "unknown dependency is rejected" false;
  Printf.printf "production_graph: %d passed, %d failed\n" !pass !fail;
  exit (if !fail = 0 then 0 else 1)
