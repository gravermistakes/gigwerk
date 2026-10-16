(*
   Benchmark-test template for item 021.

   This file deliberately opens Generated, as all generated-item tests do, but
   cannot name or invoke a candidate because the permitted source declares no
   entrypoint or OCaml signature.  The oracle below is test-only, is not a
   synthesis input, and covers only valid 0-based positions.  It must not be
   mistaken for a Generated implementation.
*)
[@@@warning "-33"]
open Generated

let fail label detail = failwith (label ^ ": " ^ detail)

let assert_equal_int label expected actual =
  if expected <> actual then
    fail label
      (Printf.sprintf "expected %d but received %d" expected actual)

let assert_equal_int_list label expected actual =
  if expected <> actual then
    let show xs =
      "[" ^ String.concat "; " (List.map string_of_int xs) ^ "]"
    in
    fail label
      (Printf.sprintf "expected %s but received %s" (show expected) (show actual))

(* Isolated reference oracle: specified only for positions 0..List.length xs.
   It deliberately has a different local name from any future Generated API. *)
let oracle_insert_valid_position position value xs =
  let rec go position prefix_rev suffix =
    match position, suffix with
    | 0, _ -> List.rev_append prefix_rev (value :: suffix)
    | n, head :: tail when n > 0 -> go (n - 1) (head :: prefix_rev) tail
    | _ -> invalid_arg "oracle_insert_valid_position: invalid test input"
  in
  go position [] xs

let test_oracle_examples () =
  assert_equal_int_list "insert at head"
    [9; 1; 2] (oracle_insert_valid_position 0 9 [1; 2]);
  assert_equal_int_list "insert in the middle"
    [1; 9; 2] (oracle_insert_valid_position 1 9 [1; 2]);
  assert_equal_int_list "insert at the final valid position"
    [1; 2; 9] (oracle_insert_valid_position 2 9 [1; 2]);
  assert_equal_int_list "insert into empty list"
    [9] (oracle_insert_valid_position 0 9 [])

let test_oracle_small_exhaustive_properties () =
  let inputs = [[]; [0]; [0; 1]; [0; 1; 2]] in
  List.iter
    (fun xs ->
      for position = 0 to List.length xs do
        let actual = oracle_insert_valid_position position 9 xs in
        assert_equal_int "insertion adds exactly one element"
          (List.length xs + 1) (List.length actual);
        let left = List.filteri (fun index _ -> index < position) actual in
        let right = List.filteri (fun index _ -> index > position) actual in
        assert_equal_int_list "prefix remains in order"
          (List.filteri (fun index _ -> index < position) xs) left;
        assert_equal_int_list "suffix remains in order"
          (List.filteri (fun index _ -> index >= position) xs) right
      done)
    inputs

(* NEGATIVE CONTROL: this deliberately incorrect expected sequence must fail
   when executed.  It verifies that the assertion mechanism detects an ordering
   error; it is not an upstream example and must never be enabled for a passing
   candidate-test run. *)
let negative_control_wrong_order () =
  assert_equal_int_list "NEGATIVE CONTROL — intentionally wrong expectation"
    [1; 2; 9] (oracle_insert_valid_position 1 9 [1; 2])

let has_flag flag =
  Array.exists (fun argument -> argument = flag) Sys.argv

let () =
  if has_flag "--negative-control" then
    negative_control_wrong_order ()
  else begin
    test_oracle_examples ();
    test_oracle_small_exhaustive_properties ();
    prerr_endline
      "SKIPPED Generated candidate calls: authoritative source did not state an OCaml entrypoint/signature."
  end
