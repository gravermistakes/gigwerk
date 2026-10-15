(* Independent conformance tests for Generated.rotate.
   This file deliberately contains no implementation of rotate.  The oracle is
   test-only and is not an input to synthesis.  It covers only the unambiguous
   finite rotation domain documented in assessment.md: 0 <= n <= length xs,
   plus the forced empty-list output for any n. *)

open Generated

exception Test_failure of string

let fail name = raise (Test_failure name)

let assert_equal name expected actual =
  if actual <> expected then fail name

(* Test-only reference logic; it is intentionally isolated from contract.sq.
   Its precondition is 0 <= n <= List.length xs. *)
let rec split_at n xs =
  match (n, xs) with
  | 0, _ -> ([], xs)
  | _, [] -> ([], [])
  | k, x :: rest ->
      let left, right = split_at (k - 1) rest in
      (x :: left, right)

let reference_rotate_in_range xs n =
  let left, right = split_at n xs in
  right @ left

let check_in_range name xs n =
  assert_equal name (reference_rotate_in_range xs n) (rotate xs n)

let rec lists_of_length alphabet length =
  if length = 0 then [ [] ]
  else
    let tails = lists_of_length alphabet (length - 1) in
    List.concat (List.map (fun x -> List.map (fun xs -> x :: xs) tails) alphabet)

let test_official_example () =
  assert_equal "official example: rotate left by 3"
    [ "d"; "e"; "f"; "g"; "h"; "a"; "b"; "c" ]
    (rotate [ "a"; "b"; "c"; "d"; "e"; "f"; "g"; "h" ] 3)

let test_zero_and_full_cycle () =
  check_in_range "zero leaves a nonempty list unchanged" [ 1; 2; 3; 4 ] 0;
  check_in_range "a full finite cycle leaves a list unchanged" [ 1; 2; 3; 4 ] 4

let test_duplicates_are_not_collapsed () =
  check_in_range "order and multiplicity with duplicates" [ "x"; "y"; "x"; "z" ] 2

let test_empty_list_is_forced_empty () =
  assert_equal "empty list at zero" ([] : int list) (rotate [] 0);
  (* Although the source does not state n's range, no nonempty list can be
     obtained by reordering an empty input; this checks that edge case only. *)
  assert_equal "empty list at arbitrary index" ([] : int list) (rotate [] 5)

let test_exhaustive_small_lists () =
  for length = 0 to 4 do
    List.iter
      (fun xs ->
        for n = 0 to length do
          check_in_range
            (Printf.sprintf "exhaustive binary list length=%d n=%d" length n)
            xs n
        done)
      (lists_of_length [ 0; 1 ] length)
  done

(* DELIBERATELY INCORRECT NEGATIVE CONTROL EXPECTATION:
   an identity implementation must not be accepted for a positive rotation.
   The verification log compiles this very suite against an external,
   explicitly-labelled identity stub and observes the expected semantic
   assertion failure in [test_official_example]. *)
let run () =
  test_official_example ();
  test_zero_and_full_cycle ();
  test_duplicates_are_not_collapsed ();
  test_empty_list_is_forced_empty ();
  test_exhaustive_small_lists ()

let () =
  try
    run ();
    Printf.printf "rotate_list tests: PASS\n"
  with
  | Test_failure name ->
      Printf.eprintf "rotate_list tests: FAIL: %s\n" name;
      exit 1
