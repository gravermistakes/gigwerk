(* Independent semantic tests for benchmark 002_tail_penultimate.
   This file opens the backend-produced Generated module; it is not an implementation. *)
open Generated

exception Test_failure of string

let fail message = raise (Test_failure message)

let show_pair (x, y) = Printf.sprintf "(%d, %d)" x y

let show_int_option = function
  | None -> "None"
  | Some pair -> "Some " ^ show_pair pair

let assert_int_option ~case expected actual =
  if actual <> expected then
    fail
      (Printf.sprintf "%s: expected %s, got %s" case
         (show_int_option expected) (show_int_option actual))

let assert_string_option ~case expected actual =
  if actual <> expected then
    fail (Printf.sprintf "%s: unexpected string option result" case)

let observe ~case xs =
  try last_two xs with
  | Failure "unsynthesized" ->
      fail (case ^ ": expected a semantic result, but reached the unsynthesized negative-control stub")
  | exn ->
      fail
        (Printf.sprintf "%s: unexpected exception from last_two: %s" case
           (Printexc.to_string exn))

(* Oracle isolated from synthesis inputs. It uses only Stdlib list reversal and
   states the required terminal ordering directly. *)
let reference_last_two xs =
  match List.rev xs with
  | last :: penultimate :: _ -> Some (penultimate, last)
  | [] | [ _ ] -> None

let test_official_examples () =
  assert_string_option ~case:"official four-string example"
    (Some ("c", "d"))
    (observe ~case:"official four-string example" [ "a"; "b"; "c"; "d" ]);
  assert_string_option ~case:"official singleton example" None
    (observe ~case:"official singleton example" [ "a" ])

let test_edges_and_order () =
  assert_int_option ~case:"empty list" None (observe ~case:"empty list" []);
  assert_int_option ~case:"singleton list" None (observe ~case:"singleton list" [ 9 ]);
  assert_int_option ~case:"two elements" (Some (3, 7))
    (observe ~case:"two elements" [ 3; 7 ]);
  assert_int_option ~case:"three elements" (Some (7, 1))
    (observe ~case:"three elements" [ 3; 7; 1 ]);
  assert_int_option ~case:"duplicate multiplicity is retained" (Some (4, 4))
    (observe ~case:"duplicate multiplicity is retained" [ 1; 4; 4 ]);
  assert_int_option ~case:"prefix cannot affect chosen values" (Some (2, 5))
    (observe ~case:"prefix cannot affect chosen values" [ 8; 8; 8; 2; 5 ])

let rec lists_of_length alphabet n =
  if n = 0 then [ [] ]
  else
    let shorter = lists_of_length alphabet (n - 1) in
    List.concat_map
      (fun x -> List.map (fun xs -> x :: xs) shorter)
      alphabet

let test_exhaustive_small_lists () =
  let alphabet = [ 0; 1; 2 ] in
  for n = 0 to 6 do
    List.iter
      (fun xs ->
        assert_int_option
          ~case:(Printf.sprintf "exhaustive length-%d case" n)
          (reference_last_two xs)
          (observe ~case:(Printf.sprintf "exhaustive length-%d case" n) xs))
      (lists_of_length alphabet n)
  done

let expect_semantic_assertion_failure ~case thunk =
  try
    thunk ();
    fail (case ^ ": deliberately incorrect expectation unexpectedly passed")
  with
  | Test_failure _ -> ()

let test_negative_control_reversed_pair_is_rejected () =
  (* NEGATIVE CONTROL: (3, 2) is intentionally wrong for [1; 2; 3].
     A correct implementation must make the inner semantic assertion fail.
     A reversed-pair defect makes it pass and therefore fails this outer test. *)
  expect_semantic_assertion_failure
    ~case:"negative control: reversed tail pair must be rejected"
    (fun () ->
      assert_int_option ~case:"intentionally wrong reversed expectation"
        (Some (3, 2))
        (observe ~case:"intentionally wrong reversed expectation" [ 1; 2; 3 ]))

let () =
  test_official_examples ();
  test_edges_and_order ();
  test_exhaustive_small_lists ();
  test_negative_control_reversed_pair_is_rejected ();
  print_endline "002_tail_penultimate: semantic tests passed"
