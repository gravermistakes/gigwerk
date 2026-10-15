(*
   Independent semantic tests for Generated.last.
   Contract target: val last : 'a list -> 'a option

   This file deliberately contains no implementation of Generated.last.  The
   oracle below is test-only, is not a synthesis input, and may not be lowered
   as a candidate implementation.
*)
open Generated

let fail label detail =
  prerr_endline ("FAIL " ^ label ^ ": " ^ detail);
  exit 1

let call_last label xs =
  try last xs with
  | exn -> fail label ("Generated.last raised " ^ Printexc.to_string exn)

let show_int_option = function
  | None -> "None"
  | Some x -> "Some " ^ string_of_int x

let show_string_option = function
  | None -> "None"
  | Some x -> "Some " ^ Printf.sprintf "%S" x

let assert_int_option label expected actual =
  if expected <> actual then
    fail label
      ("expected " ^ show_int_option expected ^ ", got " ^ show_int_option actual)

let assert_string_option label expected actual =
  if expected <> actual then
    fail label
      ("expected " ^ show_string_option expected ^ ", got " ^ show_string_option actual)

let assert_not_int_option label forbidden actual =
  if forbidden = actual then
    fail label
      ("unexpectedly got the deliberately incorrect expectation "
       ^ show_int_option forbidden)

(* Test-only oracle.  It is intentionally isolated from contract.sq. *)
let rec oracle_last = function
  | [] -> None
  | [x] -> Some x
  | _ :: xs -> oracle_last xs

let rec lists_of_length n values =
  if n = 0 then [ [] ]
  else
    let shorter = lists_of_length (n - 1) values in
    List.concat
      (List.map (fun x -> List.map (fun xs -> x :: xs) shorter) values)

let all_lists_through max_length values =
  let rec loop n acc =
    if n > max_length then acc
    else loop (n + 1) (lists_of_length n values @ acc)
  in
  loop 0 []

let test_official_examples () =
  assert_string_option "official non-empty example" (Some "d")
    (call_last "official non-empty example" [ "a"; "b"; "c"; "d" ]);
  let empty_result : int option = call_last "official empty example" [] in
  assert_int_option "official empty example" None empty_result

let test_edges_and_multiplicity () =
  assert_int_option "singleton" (Some 42) (call_last "singleton" [ 42 ]);
  assert_int_option "two elements" (Some 2) (call_last "two elements" [ 1; 2 ]);
  assert_int_option "repeated values preserve final position" (Some 6)
    (call_last "repeated values preserve final position" [ 5; 6; 5; 6 ]);
  assert_int_option "negative and zero values" (Some 0)
    (call_last "negative and zero values" [ -7; -1; 0 ]);
  assert_int_option "longer traversal" (Some 10)
    (call_last "longer traversal" [ 1; 2; 3; 4; 5; 6; 7; 8; 9; 10 ])

let test_exhaustive_small_domain () =
  let cases = all_lists_through 5 [ -1; 0; 1 ] in
  List.iteri
    (fun i xs ->
      assert_int_option ("exhaustive list case " ^ string_of_int i)
        (oracle_last xs) (call_last ("exhaustive list case " ^ string_of_int i) xs))
    cases

let test_negative_control_wrong_head_expectation () =
  (* NEGATIVE CONTROL: Some 10 is deliberately wrong for this input.  A
     first-element implementation produces it and must therefore be rejected. *)
  let deliberately_incorrect_expectation = Some 10 in
  assert_not_int_option "negative control rejects first-element behavior"
    deliberately_incorrect_expectation
    (call_last "negative control rejects first-element behavior" [ 10; 20; 30 ])

let () =
  test_official_examples ();
  test_edges_and_multiplicity ();
  test_exhaustive_small_domain ();
  test_negative_control_wrong_head_expectation ();
  print_endline "PASS 001_tail: all semantic assertions held"
