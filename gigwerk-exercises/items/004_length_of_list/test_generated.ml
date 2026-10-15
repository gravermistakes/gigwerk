(* Independent semantic tests for OCaml exercise 004: Length of a List.
   This file deliberately opens the future mechanically lowered module; it is
   not an implementation of Generated.length.  The local reference oracle is
   test-only and is isolated from Synquid inputs. *)
open Generated

exception Test_failure of string

let fail label detail = raise (Test_failure (label ^ ": " ^ detail))

let assert_int label expected actual =
  if expected <> actual then
    fail label
      ("expected " ^ string_of_int expected ^ ", got " ^ string_of_int actual)

(* Test-only oracle.  It is intentionally not supplied to synthesis. *)
let rec oracle_length = function
  | [] -> 0
  | _ :: tail -> 1 + oracle_length tail

let check label xs expected = assert_int label expected (length xs)

let rec lists_of_length alphabet n =
  if n = 0 then [ [] ]
  else
    let tails = lists_of_length alphabet (n - 1) in
    List.concat (List.map (fun x -> List.map (fun xs -> x :: xs) tails) alphabet)

let test_official_examples () =
  check "official/string triple" [ "a"; "b"; "c" ] 3;
  check "official/empty" ([] : string list) 0

let test_edges_and_polymorphism () =
  check "edge/int empty" ([] : int list) 0;
  check "edge/int singleton" [ 42 ] 1;
  check "edge/duplicates count multiplicity" [ 7; 7; 7; 7 ] 4;
  check "edge/booleans" [ true; false; true ] 3;
  check "edge/nested values" [ []; [ 1 ]; []; [ 2; 3 ] ] 4

let test_small_exhaustive_inputs () =
  for n = 0 to 6 do
    List.iter
      (fun xs ->
        assert_int
          ("exhaustive binary list of structural size " ^ string_of_int n)
          (oracle_length xs) (length xs))
      (lists_of_length [ 0; 1 ] n)
  done

(* NEGATIVE CONTROL: a constant-zero implementation must violate the same
   semantic assertion for a nonempty list.  This checks that the assertion is
   capable of rejecting a deliberately wrong behavior; it is not Generated. *)
let test_negative_control_rejects_constant_zero () =
  let deliberately_wrong_length _ = 0 in
  let rejected =
    try
      assert_int "negative-control/nonempty list" 3
        (deliberately_wrong_length [ "a"; "b"; "c" ]);
      false
    with Test_failure _ -> true
  in
  if not rejected then fail "negative-control" "wrong behavior was accepted"

let tests =
  [ ("official examples", test_official_examples);
    ("edges and polymorphism", test_edges_and_polymorphism);
    ("small exhaustive inputs", test_small_exhaustive_inputs);
    ("negative control rejects constant zero", test_negative_control_rejects_constant_zero) ]

let () =
  List.iter
    (fun (name, test) ->
      test ();
      Printf.printf "PASS %s\n%!" name)
    tests
