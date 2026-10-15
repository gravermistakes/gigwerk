(* Independent black-box tests for Generated.duplicate.
   Oracle code in this file is test-only and is never supplied to Synquid. *)
open Generated

let rec oracle_duplicate = function
  | [] -> []
  | x :: xs -> x :: x :: oracle_duplicate xs

let rec equal_list eq xs ys =
  match (xs, ys) with
  | [], [] -> true
  | x :: xs', y :: ys' -> eq x y && equal_list eq xs' ys'
  | _ -> false

let string_of_int_list xs =
  let body = String.concat "; " (List.map string_of_int xs) in
  "[" ^ body ^ "]"

let assert_int_list_equal name expected actual =
  if not (equal_list ( = ) expected actual) then
    failwith
      (name ^ "\n  expected: " ^ string_of_int_list expected ^ "\n  actual:   "
     ^ string_of_int_list actual)

let assert_string_list_equal name expected actual =
  if not (equal_list String.equal expected actual) then
    failwith (name ^ "\n  output does not preserve the required ordered sequence")

let rec lists_of_length alphabet n =
  if n = 0 then [ [] ]
  else
    let tails = lists_of_length alphabet (n - 1) in
    let rec attach_head x = function
      | [] -> []
      | tail :: rest -> (x :: tail) :: attach_head x rest
    in
    let rec for_alphabet = function
      | [] -> []
      | x :: rest -> attach_head x tails @ for_alphabet rest
    in
    for_alphabet alphabet

let test_empty () =
  assert_int_list_equal "empty list" [] (duplicate [])

let test_official_example () =
  assert_string_list_equal "official example"
    [ "a"; "a"; "b"; "b"; "c"; "c"; "c"; "c"; "d"; "d" ]
    (duplicate [ "a"; "b"; "c"; "c"; "d" ])

let test_one_element () =
  assert_int_list_equal "one element" [ 42; 42 ] (duplicate [ 42 ])

let test_order_and_existing_multiplicity () =
  assert_int_list_equal "order and existing multiplicity"
    [ 3; 3; 1; 1; 3; 3; 2; 2 ]
    (duplicate [ 3; 1; 3; 2 ])

let test_small_exhaustive () =
  let alphabet = [ 0; 1 ] in
  let rec check_lengths n =
    if n > 5 then ()
    else begin
      List.iter
        (fun input ->
          assert_int_list_equal
            ("exhaustive binary input of length " ^ string_of_int n)
            (oracle_duplicate input) (duplicate input))
        (lists_of_length alphabet n);
      check_lengths (n + 1)
    end
  in
  check_lengths 0

(* NEGATIVE CONTROL: an identity implementation would preserve this input,
   but the required output must not. This guards against tests that only
   inspect length weakly or accidentally accept unchanged inputs. *)
let test_negative_control_identity_is_rejected () =
  let input = [ 7; 8; 7 ] in
  let deliberately_incorrect_identity_output = input in
  if equal_list ( = ) (oracle_duplicate input) deliberately_incorrect_identity_output then
    failwith "NEGATIVE CONTROL unexpectedly accepted the identity transformation"

let run name test =
  try
    test ();
    Printf.printf "ok - %s\n%!" name
  with Failure message ->
    Printf.eprintf "FAIL - %s\n%s\n%!" name message;
    exit 1

let () =
  run "empty" test_empty;
  run "official example" test_official_example;
  run "one element" test_one_element;
  run "order and multiplicity" test_order_and_existing_multiplicity;
  run "small exhaustive exact behavior" test_small_exhaustive;
  run "NEGATIVE CONTROL rejects identity" test_negative_control_identity_is_rejected
