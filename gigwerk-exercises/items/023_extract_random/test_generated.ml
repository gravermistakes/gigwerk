(*
   Independent semantic tests for Generated.rand_select.

   This test file is intentionally not an implementation.  It opens the module
   supplied by the later lowering/backend.  Its local helpers only check results
   and do not select elements or call Random.

   The upstream statement gives no behavior for negative n or n greater than
   the source length.  Those calls are deliberately outside this suite.
*)
open Generated

exception Test_failure of string

let fail message = raise (Test_failure message)

let assert_bool label condition =
  if not condition then fail label

let assert_string_list label expected actual =
  if expected <> actual then
    fail
      (Printf.sprintf "%s: expected [%s], got [%s]" label
         (String.concat "; " expected)
         (String.concat "; " actual))

let assert_int_list label expected actual =
  if expected <> actual then
    fail
      (Printf.sprintf "%s: unexpected integer-list result" label)

let count value xs =
  List.fold_left (fun total x -> if x = value then total + 1 else total) 0 xs

(* A positional sample may contain equal values, but it may never contain any
   value more often than the input contains that value. *)
let assert_submultiset label picked source =
  List.iter
    (fun value ->
      assert_bool
        (Printf.sprintf "%s: output repeats a value beyond input multiplicity" label)
        (count value picked <= count value source))
    picked

let assert_valid_sample label source n picked =
  assert_bool
    (Printf.sprintf "%s: expected exactly n selected elements" label)
    (List.length picked = n);
  assert_submultiset label picked source

let test_official_example () =
  let source = [ "a"; "b"; "c"; "d"; "e"; "f"; "g"; "h" ] in
  assert_string_list "official documented seeded example" [ "e"; "c"; "g" ]
    (rand_select source 3)

let test_reinitializes_at_each_call () =
  let source = [ "a"; "b"; "c"; "d"; "e"; "f"; "g"; "h" ] in
  let first = rand_select source 3 in
  let second = rand_select source 3 in
  assert_string_list "per-call Random.init 0 reproducibility" first second

let test_zero_selection_is_empty () =
  assert_int_list "zero selections" [] (rand_select [ 1; 2; 3 ] 0);
  assert_int_list "zero selections from empty input" [] (rand_select [] 0)

let test_singleton_selection () =
  assert_int_list "singleton selected once" [ 42 ] (rand_select [ 42 ] 1)

let test_valid_selection_preserves_size_and_input_multiplicity () =
  let source = [ 1; 1; 2; 3; 5 ] in
  let picked = rand_select source 3 in
  assert_valid_sample "partial duplicate-containing input" source 3 picked

let test_full_selection_uses_every_input_occurrence () =
  let source = [ 1; 1; 2; 3 ] in
  let picked = rand_select source 4 in
  assert_valid_sample "full duplicate-containing input" source 4 picked;
  assert_submultiset "full duplicate-containing input reverse inclusion" source picked

let tests =
  [
    ("official example", test_official_example);
    ("per-call seeded reproducibility", test_reinitializes_at_each_call);
    ("zero selection boundaries", test_zero_selection_is_empty);
    ("singleton", test_singleton_selection);
    ("partial selection multiplicity", test_valid_selection_preserves_size_and_input_multiplicity);
    ("full selection multiplicity", test_full_selection_uses_every_input_occurrence);
  ]

let () =
  let failures = ref 0 in
  List.iter
    (fun (name, test) ->
      try
        test ();
        Printf.printf "PASS %s\n%!" name
      with
      | Test_failure message ->
          incr failures;
          Printf.eprintf "FAIL %s: %s\n%!" name message
      | exn ->
          incr failures;
          Printf.eprintf "ERROR %s: %s\n%!" name (Printexc.to_string exn))
    tests;
  if !failures <> 0 then exit 1
