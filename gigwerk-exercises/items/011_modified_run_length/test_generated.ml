(* Independent semantic tests for Exercise 011.
   This file is intentionally outside Synquid synthesis inputs.  It opens the
   mechanically lowered candidate module supplied by the backend. *)
open Generated

exception Test_failure of string

let fail message = raise (Test_failure message)

let equal_rle_list left right =
  let equal_item left_item right_item =
    match (left_item, right_item) with
    | One left_value, One right_value -> left_value = right_value
    | Many (left_count, left_value), Many (right_count, right_value) ->
        left_count = right_count && left_value = right_value
    | _ -> false
  in
  try List.for_all2 equal_item left right with Invalid_argument _ -> false

let assert_rle_equal name expected actual =
  if not (equal_rle_list expected actual) then
    fail (name ^ ": exact ordered run encoding differed")

(* Test-only oracle.  It is independently written and is never supplied to
   Synquid as a component or specification. *)
let oracle values =
  let rec consume value count = function
    | next :: rest when next = value -> consume value (count + 1) rest
    | remaining -> (count, remaining)
  in
  let rec encode_runs = function
    | [] -> []
    | value :: rest ->
        let count, remaining = consume value 1 rest in
        let item = if count = 1 then One value else Many (count, value) in
        item :: encode_runs remaining
  in
  encode_runs values

let assert_matches_oracle name input =
  assert_rle_equal name (oracle input) (encode input)

let test_official_example () =
  let input =
    [ "a"; "a"; "a"; "a"; "b"; "c"; "c"; "a"; "a"; "d"; "e"; "e"; "e"; "e" ]
  in
  let expected =
    [ Many (4, "a"); One "b"; Many (2, "c"); Many (2, "a"); One "d"; Many (4, "e") ]
  in
  assert_rle_equal "official example" expected (encode input)

let test_empty_input () = assert_rle_equal "empty input" [] (encode [])

let test_singleton_input () =
  assert_rle_equal "singleton input" [ One 42 ] (encode [ 42 ])

let test_all_equal_run () =
  assert_rle_equal "all equal run" [ Many (5, "x") ]
    (encode [ "x"; "x"; "x"; "x"; "x" ])

let test_run_boundaries_preserve_order_and_multiplicity () =
  assert_rle_equal "separated equal runs" [ Many (2, 1); One 2; Many (2, 1) ]
    (encode [ 1; 1; 2; 1; 1 ])

let test_no_adjacent_duplicates_are_not_coalesced () =
  assert_rle_equal "non-adjacent duplicates" [ One "a"; One "b"; One "a"; One "b" ]
    (encode [ "a"; "b"; "a"; "b" ])

let test_two_and_three_element_runs () =
  assert_rle_equal "mixed run lengths"
    [ Many (2, 0); Many (3, 1); One 2; Many (2, 3) ]
    (encode [ 0; 0; 1; 1; 1; 2; 3; 3 ])

let rec lists_of_length alphabet length =
  if length = 0 then [ [] ]
  else
    let tails = lists_of_length alphabet (length - 1) in
    List.concat
      (List.map (fun head -> List.map (fun tail -> head :: tail) tails) alphabet)

let test_exhaustive_small_inputs () =
  let alphabet = [ 0; 1; 2 ] in
  for length = 0 to 6 do
    List.iter
      (fun input -> assert_matches_oracle "exhaustive ternary input" input)
      (lists_of_length alphabet length)
  done

let expect_test_failure name thunk =
  let assertion_rejected =
    try
      thunk ();
      false
    with
    | Test_failure _ -> true
  in
  if not assertion_rejected then
    fail (name ^ ": deliberately incorrect expectation unexpectedly held")

let test_negative_control_rejects_singleton_tag_for_duplicate_run () =
  (* NEGATIVE CONTROL: a defective encoder that emits One for ["q"; "q"]
     would make this deliberately wrong expectation hold, so this test fails
     for that defect and passes only when the wrong expectation is rejected. *)
  expect_test_failure "negative control"
    (fun () ->
      assert_rle_equal "negative-control wrong expected output" [ One "q" ]
        (encode [ "q"; "q" ]))

let tests =
  [ ("official example", test_official_example)
  ; ("empty input", test_empty_input)
  ; ("singleton input", test_singleton_input)
  ; ("all equal run", test_all_equal_run)
  ; ("ordered boundaries", test_run_boundaries_preserve_order_and_multiplicity)
  ; ("non-adjacent duplicates", test_no_adjacent_duplicates_are_not_coalesced)
  ; ("mixed run lengths", test_two_and_three_element_runs)
  ; ("exhaustive small inputs", test_exhaustive_small_inputs)
  ; ("negative control", test_negative_control_rejects_singleton_tag_for_duplicate_run)
  ]

let () =
  List.iter
    (fun (name, test) ->
      test ();
      Printf.printf "PASS: %s\n%!" name)
    tests
