(* Independent acceptance tests for benchmark 022.
   Compile this file against a backend-produced module Generated exposing:
     val range : int -> int -> int list
   The oracle below is test-only and is not an input to Synquid synthesis. *)

open Generated

exception Test_failure of string

let failf fmt = Printf.ksprintf (fun message -> raise (Test_failure message)) fmt

let string_of_int_list xs =
  "[" ^ String.concat "; " (List.map string_of_int xs) ^ "]"

let assert_int_list ~label expected actual =
  if actual <> expected then
    failf "%s: expected %s but got %s"
      label (string_of_int_list expected) (string_of_int_list actual)

(* Test-only oracle. It is deliberately isolated from contract.sq and may not
   be used as a synthesis component or mechanically lowered implementation. *)
let expected_range first last =
  let step = if first <= last then 1 else -1 in
  let rec loop current acc =
    if current = last then List.rev (current :: acc)
    else loop (current + step) (current :: acc)
  in
  loop first []

let assert_contract_for_pair first last =
  let actual = range first last in
  let expected = expected_range first last in
  assert_int_list
    ~label:(Printf.sprintf "exact sequence for range %d %d" first last)
    expected actual;
  match actual with
  | [] -> failf "range %d %d: output must be non-empty" first last
  | head :: _ ->
      if head <> first then
        failf "range %d %d: first element must be %d, got %d"
          first last first head;
      if List.hd (List.rev actual) <> last then
        failf "range %d %d: final element must be %d"
          first last last;
      let step = if first <= last then 1 else -1 in
      let rec check_adjacency = function
        | [] | [_] -> ()
        | x :: ((y :: _) as tail) ->
            if y <> x + step then
              failf "range %d %d: adjacent values must differ by %d; saw %d then %d"
                first last step x y;
            check_adjacency tail
      in
      check_adjacency actual

let test_official_example () =
  assert_int_list
    ~label:"official example: range 4 9"
    [4; 5; 6; 7; 8; 9]
    (range 4 9)

let test_equal_endpoints () =
  assert_contract_for_pair 0 0;
  assert_contract_for_pair (-7) (-7)

let test_descending_and_adjacent_ranges () =
  assert_contract_for_pair 4 2;
  assert_contract_for_pair 9 4;
  assert_contract_for_pair 2 1;
  assert_contract_for_pair 1 2

let test_negative_and_cross_zero_ranges () =
  assert_contract_for_pair (-4) (-1);
  assert_contract_for_pair (-1) (-4);
  assert_contract_for_pair (-3) 3;
  assert_contract_for_pair 3 (-3)

let test_small_exhaustive_pairs () =
  for first = -6 to 6 do
    for last = -6 to 6 do
      assert_contract_for_pair first last
    done
  done

(* NEGATIVE CONTROL — deliberately incorrect expectation. It is never an
   acceptance criterion. The harness requires it to fail for a conforming
   implementation, demonstrating that a reversed/wrong sequence is rejected. *)
let test_negative_control_wrong_expectation_is_rejected () =
  let deliberately_wrong = [4; 2] in
  let rejected =
    try
      assert_int_list
        ~label:"NEGATIVE CONTROL: intentionally wrong range 4 2 expectation"
        deliberately_wrong (range 4 2);
      false
    with
    | Test_failure _ -> true
  in
  if not rejected then
    failf "NEGATIVE CONTROL unexpectedly accepted [4; 2] for range 4 2"

let tests = [
  ("official example", test_official_example);
  ("equal endpoints", test_equal_endpoints);
  ("descending and adjacent", test_descending_and_adjacent_ranges);
  ("negative and cross-zero", test_negative_and_cross_zero_ranges);
  ("small exhaustive pairs", test_small_exhaustive_pairs);
  ("negative control rejects wrong expectation",
   test_negative_control_wrong_expectation_is_rejected);
]

let () =
  List.iter
    (fun (name, test) ->
       try test (); Printf.printf "PASS %s\n%!" name
       with
       | Test_failure message ->
           Printf.eprintf "FAIL %s: %s\n%!" name message;
           exit 1
       | exn ->
           Printf.eprintf "FAIL %s: unexpected exception %s\n%!"
             name (Printexc.to_string exn);
           exit 1)
    tests
