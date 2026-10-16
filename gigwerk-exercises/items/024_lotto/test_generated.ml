(*
   Independent semantic tests for Generated.lotto_select.

   Compile a candidate module named generated.ml (therefore module Generated)
   with this file.  These tests deliberately do not assert the official sample's
   displayed list: the source says the result is random and specifies no order.
   They test only the stated feasible domain 0 <= n <= m.
*)
open Generated

let fail_case name detail =
  failwith (name ^ ": " ^ detail)

let has_pairwise_distinct_elements xs =
  let rec loop seen = function
    | [] -> true
    | x :: rest ->
        if List.mem x seen then false else loop (x :: seen) rest
  in
  loop [] xs

let assert_valid_draw name n m result =
  if List.length result <> n then
    fail_case name
      (Printf.sprintf "expected length %d, got %d" n (List.length result));
  if not (List.for_all (fun x -> 1 <= x && x <= m) result) then
    fail_case name
      (Printf.sprintf "output contains a value outside 1..%d" m);
  if not (has_pairwise_distinct_elements result) then
    fail_case name "output contains duplicate values"

let test_official_example_parameters () =
  (* The official source shows lotto_select 6 49, but its concrete list is
     only one possible random draw. *)
  assert_valid_draw "official example parameters" 6 49 (lotto_select 6 49)

let test_zero_draw_from_empty_set () =
  assert_valid_draw "zero draw from empty set" 0 0 (lotto_select 0 0)

let test_singleton_draw () =
  assert_valid_draw "singleton draw" 1 1 (lotto_select 1 1)

let test_full_draw_is_a_permutation_of_the_domain () =
  let result = lotto_select 7 7 in
  assert_valid_draw "full draw" 7 7 result;
  for value = 1 to 7 do
    if not (List.mem value result) then
      fail_case "full draw" (Printf.sprintf "missing required value %d" value)
  done

let test_all_small_feasible_pairs () =
  for m = 0 to 8 do
    for n = 0 to m do
      let name = Printf.sprintf "small feasible pair n=%d m=%d" n m in
      assert_valid_draw name n m (lotto_select n m)
    done
  done

let test_negative_control_oracle_rejects_duplicates () =
  (* NEGATIVE CONTROL: [1; 1] is deliberately not a valid result for n=2,m=3.
     This guards the oracle itself against accidentally omitting uniqueness. *)
  let deliberately_incorrect_result = [1; 1] in
  if has_pairwise_distinct_elements deliberately_incorrect_result then
    fail_case "NEGATIVE CONTROL" "duplicate-result oracle unexpectedly accepted [1; 1]"

let () =
  test_negative_control_oracle_rejects_duplicates ();
  test_official_example_parameters ();
  test_zero_draw_from_empty_set ();
  test_singleton_draw ();
  test_full_draw_is_a_permutation_of_the_domain ();
  test_all_small_feasible_pairs ();
  print_endline "lotto_select semantic tests passed"
