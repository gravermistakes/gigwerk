(* Independent semantic tests for exercise 020.  This file intentionally contains
   no candidate implementation.  The production module is supplied by the
   later backend as [Generated]. *)
open Generated

let fail case = failwith ("remove_at: " ^ case)

let assert_equal case expected actual =
  if actual <> expected then fail case

(* Test-only oracle.  Every caller in this file supplies 0 <= index < length xs.
   It is isolated from contract.sq and from any future generated component. *)
let rec oracle_remove_valid index = function
  | [] -> invalid_arg "oracle_remove_valid: generated invalid test index"
  | _ :: tail when index = 0 -> tail
  | head :: tail -> head :: oracle_remove_valid (index - 1) tail

let test_official_example () =
  assert_equal "official example: index 1"
    ["a"; "c"; "d"]
    (remove_at 1 ["a"; "b"; "c"; "d"])

let test_boundary_positions () =
  assert_equal "remove first" [20; 30] (remove_at 0 [10; 20; 30]);
  assert_equal "remove middle" [10; 30] (remove_at 1 [10; 20; 30]);
  assert_equal "remove final" [10; 20] (remove_at 2 [10; 20; 30]);
  assert_equal "singleton becomes empty" ([] : int list) (remove_at 0 [99])

let test_multiplicity_and_order () =
  assert_equal "remove one duplicate only" [1; 2; 1]
    (remove_at 1 [1; 1; 2; 1]);
  assert_equal "retain repeated suffix in order" ["x"; "x"; "y"]
    (remove_at 2 ["x"; "x"; "x"; "y"])

let rec lists_of_length values length =
  if length = 0 then [[]]
  else
    List.concat
      (List.map
         (fun suffixes -> List.map (fun x -> x :: suffixes) values)
         (lists_of_length values (length - 1)))

let test_exhaustive_small_valid_inputs () =
  let values = [0; 1; 2] in
  for length = 1 to 4 do
    List.iter
      (fun xs ->
        for index = 0 to length - 1 do
          assert_equal
            (Printf.sprintf "exhaustive length=%d index=%d" length index)
            (oracle_remove_valid index xs)
            (remove_at index xs)
        done)
      (lists_of_length values length)
  done

(* Deliberately incorrect NEGATIVE CONTROL expectation.  It is deliberately
   excluded from [run_all]: a conforming implementation must fail it because
   index 1 must be removed, not retained.  It documents that no-op removal is
   not an accepted interpretation of the valid-index contract. *)
let negative_control_intentionally_wrong_expectation () =
  assert_equal "NEGATIVE CONTROL (must fail for conforming code)"
    [10; 20; 30]
    (remove_at 1 [10; 20; 30])

let run_all () =
  test_official_example ();
  test_boundary_positions ();
  test_multiplicity_and_order ();
  test_exhaustive_small_valid_inputs ();
  print_endline "remove_at valid-index semantic tests passed"

let () = run_all ()
