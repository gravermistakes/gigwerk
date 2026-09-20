open Gigwerk

(* Declaration order is not a contract.
 *
 * This test began as a parse-time assertion that a requirement may not depend
 * on one declared after it. That contract cannot coexist with
 * test_production_graph, which needs `parse` to ACCEPT a cycle and an unknown
 * dependency so that Production_graph.build can reject them with `Cycle` and
 * `Unknown_requirement`. Validating dependencies at parse time made both of
 * those errors unreachable.
 *
 * Graph-level validation wins: it is implemented, it is tested, and its error
 * names the whole cycle path rather than one edge. So the regression this file
 * guards is re-pointed at the real contract -- out-of-order declaration is
 * legal and must build correctly, and bad dependencies are still caught, one
 * layer down. *)

let pass = ref 0
let fail = ref 0

let check label condition =
  if condition then incr pass
  else begin incr fail; Printf.eprintf "FAIL: %s\n" label end

let ids requirements = List.map (fun r -> r.Production.id) requirements

let () =
  (* `a` depends on `b`, and `b` is declared AFTER it. A valid DAG either way. *)
  let source = "req a : first\nreq b : second\ndepends a : b\n" in
  (match Specification.parse source with
   | Error _ -> check "out-of-order declaration parses" false
   | Ok spec -> (
       check "out-of-order declaration parses" true;
       match Production_graph.build spec with
       | Error _ -> check "out-of-order declaration builds" false
       | Ok g ->
           check "out-of-order declaration builds" true;
           check "the dependency is the root, not the first line declared"
             (ids (Production_graph.roots g) = [ "b" ]);
           check "the dependent is ready only once its dependency completes"
             (ids (Production_graph.ready g ~completed:[]) = [ "b" ]
              && ids (Production_graph.ready g ~completed:[ "b" ]) = [ "a" ])));

  (* A cycle DOES survive parsing -- both ids exist -- so the graph is what
     catches it, and its error names the whole path rather than one edge. That
     is the division of labour, and it is why dependency existence checking
     belongs at parse time while cycle detection cannot. *)
  (match Specification.parse "req a : first\nreq b : second\ndepends a : b\ndepends b : a\n" with
   | Error _ -> check "a cycle survives parsing" false
   | Ok spec -> (
       check "a cycle survives parsing" true;
       match Production_graph.build spec with
       | Error (Production_graph.Cycle path) ->
           check "...and the graph names the whole path" (List.length path >= 3)
       | _ -> check "...and the graph rejects it" false));

  Printf.printf "specification_ordering: %d passed, %d failed\n" !pass !fail;
  exit (if !fail = 0 then 0 else 1)
