(* The OCaml-writing talent's components, each against behavior it must have.
 * No network, no exercise catalogue: every input is written here. *)
open Writer

let pass = ref 0 and fail = ref 0
let check name b =
  if b then (incr pass; Printf.printf "  ok   %s\n" name)
  else (incr fail; Printf.printf "  FAIL %s\n" name)

let ex args out = { Spec.args; out }
let s x = Value.String x and i n = Value.Int n

let derive ?(depth = 4) params out_ty exs =
  match Topdown.solve_top ~depth ~decls:[] ~params ~out_ty exs with
  | Topdown.Solved (e, _) -> Some e
  | Topdown.Gave_up _ -> None

let run1 e x = Eval.run [ ("x", x) ] e

let () =
  print_endline "values -- ordered the way the compiled program orders them";
  Value.declare_variant [ ("Eggs", 0); ("Peanuts", 0); ("Node", 3) ];
  check "constant constructors order by declaration, not by name"
    (Value.compare (Value.Con ("Peanuts", [])) (Value.Con ("Eggs", [])) > 0);
  check "every constant constructor comes before every one carrying values"
    (Value.compare (Value.Con ("Peanuts", [])) (Value.Con ("Node", [ i 0; i 0; i 0 ])) < 0);
  check "None before Some, as the runtime has it"
    (Value.compare (Value.Con ("None", [])) (Value.Con ("Some", [ i (-5) ])) < 0);

  print_endline "\nliterals -- what a probe or a transcript prints, read back";
  check "negative numbers, options and nesting"
    (Literal.of_string_opt "(Some [(-3); 4])" = Some (Value.Con ("Some", [ Value.List [ i (-3); i 4 ] ])));
  check "records keep their field names"
    (Literal.of_string_opt "{ value = 3; weight = 4 }" = Some (Value.Record [ ("value", i 3); ("weight", i 4) ]));
  check "polymorphic variants"
    (Literal.of_string_opt "[`A; `C]" = Some (Value.List [ Value.Poly ("A", None); Value.Poly ("C", None) ]));
  check "an opaque block printed for a rigid 'a comes back as an opaque constructor"
    (match Literal.of_string_opt "(__gw_block 0 (1, \"x\",()))" with
     | Some (Value.Con ("#0", [ Value.Int 1; Value.String "x" ])) -> true | _ -> false);

  print_endline "\ninterfaces -- read with the compiler's parser";
  let iface = Iface.parse_string
      "type base = int\ntype t = A | B of int\nval f : from:base -> ?n:int -> t list -> (int, string) result\n" in
  (match iface.Iface.values with
   | [ { Iface.vname = "f"; vty } ] ->
       let args, out = Types.unarrow (Iface.expand iface.Iface.decls vty) in
       check "labels, optional arguments and aliases are kept and expanded"
         (List.map fst args = [ Types.Labelled "from"; Types.Optional "n"; Types.Nolabel ]
          && Types.to_string (snd (List.hd args)) = "int"
          && Types.to_string out = "(int, string) result")
   | _ -> check "the interface's value was read" false);
  check "what the writer cannot represent is named, not half-read"
    ((Iface.parse_string "module type S = sig end\nval x : int\n").Iface.unreadable <> []);

  print_endline "\nsearch -- derived from examples, judged on inputs it never saw";
  (match derive [ ("x", Types.t_option Types.t_string) ] Types.t_string
           [ ex [ Value.Con ("Some", [ s "Bob" ]) ] (s "One for Bob, one for me.");
             ex [ Value.Con ("Some", [ s "Alice" ]) ] (s "One for Alice, one for me.");
             ex [ Value.Con ("None", []) ] (s "One for you, one for me.") ] with
   | Some e ->
       check "string constants are cut from the outputs, and the term generalizes"
         (run1 e (Value.Con ("Some", [ s "Zed" ])) = Some (s "One for Zed, one for me."))
   | None -> check "two-fer's shape was derived" false);
  let leap y = (y mod 4 = 0 && y mod 100 <> 0) || y mod 400 = 0 in
  let years = [ 2015; 1970; 1996; 1960; 2100; 1900; 2000; 2400; 1800 ] in
  (match derive [ ("x", Types.t_int) ] Types.t_bool
           (List.map (fun y -> ex [ i y ] (Value.Bool (leap y))) years) with
   | Some e ->
       check "divisors are solved from the data, and the rule holds on every year to 3000"
         (List.for_all (fun y -> run1 e (i y) = Some (Value.Bool (leap y))) (List.init 3000 (fun k -> k + 1)))
   | None -> check "leap was derived" false);
  (match derive [ ("x", Types.t_list (Types.TVar "a")) ] (Types.t_option (Types.TVar "a"))
           [ ex [ Value.List [ s "a"; s "b"; s "c"; s "d" ] ] (Value.Con ("Some", [ s "d" ]));
             ex [ Value.List [] ] (Value.Con ("None", [])) ] with
   | Some e ->
       check "with one long example, the last element is not mistaken for index 3"
         (run1 e (Value.List [ s "p"; s "q" ]) = Some (Value.Con ("Some", [ s "q" ])))
   | None -> check "last was derived" false);
  let exs = [ ex [ i 3 ] (i 9); ex [ i 4 ] (i 16); ex [ i 5 ] (i 25) ] in
  check "the same examples give the same term, every time"
    (derive [ ("x", Types.t_int) ] Types.t_int exs = derive [ ("x", Types.t_int) ] Types.t_int exs);

  print_endline "\nbounds -- a candidate that loops has no value, it does not hang the search";
  let loop = Expr.Let (true, "f", Expr.Lam ([ "n" ], Expr.App (Expr.Var "f", [ Expr.Var "n" ])),
                       Expr.App (Expr.Var "f", [ Expr.Lit (i 1) ])) in
  check "fuel runs out and the run reports no value" (Eval.run ~budget:10_000 [] loop = None);

  print_endline "\nthe reference never reaches the actor";
  let md = "## Solution\n\n```ocaml\n# let secret_solution x = x * 7;;\nval secret_solution : int -> int = <fun>\n```\n\n\
            ## Statement\n\nWrite `times : int -> int`.\n\n```ocaml\n# times 2;;\n- : int = 14\n```\n" in
  let p = Transcript.read ~slug:"t" md in
  check "the statement's example is read, with its stated type"
    (match p.Transcript.targets with
     | [ ("times", Some _, [ { Spec.args = [ Value.Int 2 ]; out = Value.Int 14 } ]) ] -> true | _ -> false);
  check "nothing from the Solution is in the part"
    (not (List.exists (fun u -> String.length u > 0 &&
                                (try ignore (Str.search_forward (Str.regexp_string "secret") u 0); true
                                 with Not_found -> false)) p.Transcript.unread)
     && List.for_all (fun (n, _, _) -> n <> "secret_solution") p.Transcript.targets);
  check "...while the verifier can still read it"
    (try ignore (Str.search_forward (Str.regexp_string "secret_solution x = x * 7") (Transcript.reference md) 0); true
     with Not_found -> false);

  Printf.printf "writer: %d passed, %d failed\n" !pass !fail;
  if !fail <> 0 then exit 1
