(* Independent OCaml semantic tests for exercise 010.
   Contract target: Generated.encode : 'a list -> (int * 'a) list.
   This file deliberately contains no target implementation. The reference oracle
   is test-only and is not an input to Synquid synthesis. *)

open Generated

exception Test_failure of string

let fail name = raise (Test_failure name)

let assert_equal name expected actual =
  if expected <> actual then fail name

let actual_encode name input =
  try encode input with
  | Test_failure _ as exn -> raise exn
  | _ -> fail (name ^ " (encode raised instead of returning a value)")

(* Test-only oracle: split an input into maximal, non-empty adjacent-equal runs,
   preserving run order, then expose each run as (its length, its representative).
   It is isolated in this test artifact and is not supplied to synthesis. *)
let reference_encode xs =
  let rec consume representative count rest =
    match rest with
    | next :: tail when next = representative ->
        consume representative (count + 1) tail
    | _ ->
        ((count, representative), rest)
  in
  let rec loop remaining =
    match remaining with
    | [] -> []
    | first :: rest ->
        let run, after_run = consume first 1 rest in
        run :: loop after_run
  in
  loop xs

let rec repeat n x =
  if n <= 0 then [] else x :: repeat (n - 1) x

let rec decode runs =
  match runs with
  | [] -> []
  | (count, value) :: tail -> repeat count value @ decode tail

let all_lists_of_length alphabet length =
  let rec make n =
    if n = 0 then [ [] ]
    else
      let suffixes = make (n - 1) in
      List.concat
        (List.map
           (fun value -> List.map (fun suffix -> value :: suffix) suffixes)
           alphabet)
  in
  make length

let test_official_example () =
  let input =
    [ "a"; "a"; "a"; "a"; "b"; "c"; "c"; "a"; "a"; "d"; "e";
      "e"; "e"; "e" ]
  in
  let expected =
    [ (4, "a"); (1, "b"); (2, "c"); (2, "a"); (1, "d"); (4, "e") ]
  in
  assert_equal "official example: exact ordered runs" expected
    (actual_encode "official example: exact ordered runs" input)

let test_empty () =
  assert_equal "empty list" [] (actual_encode "empty list" ([] : int list))

let test_singleton () =
  assert_equal "singleton is one count-one run" [ (1, 42) ]
    (actual_encode "singleton is one count-one run" [ 42 ])

let test_one_long_run () =
  assert_equal "one maximal run" [ (5, 7) ]
    (actual_encode "one maximal run" [ 7; 7; 7; 7; 7 ])

let test_alternating_values () =
  assert_equal "alternating values keep separate count-one runs"
    [ (1, 1); (1, 2); (1, 1); (1, 2) ]
    (actual_encode "alternating values keep separate count-one runs" [ 1; 2; 1; 2 ])

let test_nonadjacent_equal_values_do_not_merge () =
  assert_equal "equal values separated by another value remain separate runs"
    [ (2, 9); (1, 3); (2, 9) ]
    (actual_encode "equal values separated by another value remain separate runs"
       [ 9; 9; 3; 9; 9 ])

let test_boundaries_and_integer_values () =
  assert_equal "first and last runs, zero, and negative values"
    [ (2, -1); (3, 0); (1, -1) ]
    (actual_encode "first and last runs, zero, and negative values"
       [ -1; -1; 0; 0; 0; -1 ])

let test_exhaustive_small_int_lists () =
  let alphabet = [ -1; 0; 1 ] in
  for length = 0 to 5 do
    List.iter
      (fun input ->
        let actual = actual_encode "exhaustive exact oracle comparison" input in
        let expected = reference_encode input in
        assert_equal "exhaustive exact oracle comparison" expected actual;
        assert_equal "exhaustive reconstruction preserves every input position"
          input (decode actual);
        if List.exists (fun (count, _) -> count <= 0) actual then
          fail "every emitted run count is strictly positive")
      (all_lists_of_length alphabet length)
  done

(* Deliberately incorrect NEGATIVE CONTROL expectation. A correct implementation
   must reject it: [1;1;2] is not encoded as two count-one runs. If a candidate
   ever satisfies this wrong expectation, the harness itself fails. *)
let test_negative_control_wrong_expectation_is_rejected () =
  let wrong_expected = [ (1, 1); (1, 2) ] in
  let rejected =
    try
      assert_equal "NEGATIVE CONTROL (deliberately wrong expectation)"
        wrong_expected
        (actual_encode "NEGATIVE CONTROL (deliberately wrong expectation)" [ 1; 1; 2 ]);
      false
    with
    | Test_failure _ -> true
  in
  if not rejected then
    fail "negative control unexpectedly passed: multiplicity was discarded"

let tests =
  [ ("official example", test_official_example);
    ("empty", test_empty);
    ("singleton", test_singleton);
    ("one long run", test_one_long_run);
    ("alternating", test_alternating_values);
    ("nonadjacent equal values", test_nonadjacent_equal_values_do_not_merge);
    ("boundaries and integers", test_boundaries_and_integer_values);
    ("exhaustive small int lists", test_exhaustive_small_int_lists);
    ("negative control", test_negative_control_wrong_expectation_is_rejected) ]

let () =
  let passed = ref 0 in
  List.iter
    (fun (name, test) ->
      try
        test ();
        incr passed;
        Printf.printf "PASS: %s\n%!" name
      with
      | Test_failure assertion ->
          Printf.eprintf "FAIL: %s -- semantic assertion: %s\n%!" name assertion;
          exit 1
      | exn ->
          Printf.eprintf "FAIL: %s -- unexpected exception: %s\n%!" name
            (Printexc.to_string exn);
          exit 1)
    tests;
  Printf.printf "PASS: %d semantic test groups\n%!" !passed
