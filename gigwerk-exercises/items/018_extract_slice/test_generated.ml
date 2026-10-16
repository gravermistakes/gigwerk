(* Independent semantic tests for Generated.slice.
   Oracle code is test-only and is not a synthesis component. *)
open Generated

let fail label expected actual =
  failwith
    (Printf.sprintf "%s: expected %s but got %s" label expected actual)

let assert_int_list label expected actual =
  if expected <> actual then
    fail label
      (String.concat ";" (List.map string_of_int expected))
      (String.concat ";" (List.map string_of_int actual))

let assert_string_list label expected actual =
  if expected <> actual then
    fail label
      (String.concat ";" expected)
      (String.concat ";" actual)

(* The reference follows the public 0-based, inclusive-index definition and
   is intentionally separate from the synthesized artifact.  Calls are made
   only on the stated valid-input domain: 0 <= i <= k < List.length xs. *)
let reference_slice xs i k =
  let rec walk index acc = function
    | [] -> List.rev acc
    | x :: rest ->
        if index > k then List.rev acc
        else if index >= i then walk (index + 1) (x :: acc) rest
        else walk (index + 1) acc rest
  in
  walk 0 [] xs

let check_int_case label xs i k =
  assert_int_list label (reference_slice xs i k) (slice xs i k)

let check_string_case label xs i k =
  assert_string_list label (reference_slice xs i k) (slice xs i k)

let binary_lists max_length =
  let rec of_length n =
    if n = 0 then [ [] ]
    else
      List.concat_map
        (fun suffix -> [ 0 :: suffix; 1 :: suffix ])
        (of_length (n - 1))
  in
  List.concat_map of_length (List.init (max_length + 1) Fun.id)

let test_official_example () =
  check_string_case "official example" 
    [ "a"; "b"; "c"; "d"; "e"; "f"; "g"; "h"; "i"; "j" ] 2 6

let test_boundaries_and_multiplicity () =
  check_int_case "whole singleton" [ 42 ] 0 0;
  check_int_case "first singleton" [ 8; 6; 7; 5 ] 0 0;
  check_int_case "last singleton" [ 8; 6; 7; 5 ] 3 3;
  check_int_case "whole list" [ 8; 6; 7; 5 ] 0 3;
  check_int_case "duplicate values preserve count and order" [ 1; 2; 2; 3; 2; 4 ] 1 4

let test_small_exhaustive_valid_domain () =
  List.iter
    (fun xs ->
      let n = List.length xs in
      for i = 0 to n - 1 do
        for k = i to n - 1 do
          check_int_case
            (Printf.sprintf "binary exhaustive n=%d i=%d k=%d" n i k)
            xs i k
        done
      done)
    (binary_lists 5)

(* Negative control: a candidate that reverses the chosen window would return
   [4; 3; 2] here.  The required traversal is original left-to-right order. *)
let test_negative_control_rejects_reverse_order () =
  let actual = slice [ 1; 2; 3; 4; 5 ] 1 3 in
  assert_int_list "negative control: reverse-order output must be rejected" [ 2; 3; 4 ] actual;
  if actual = [ 4; 3; 2 ] then
    failwith "negative control failed: implementation returned reverse-order output"

let () =
  test_negative_control_rejects_reverse_order ();
  test_official_example ();
  test_boundaries_and_multiplicity ();
  test_small_exhaustive_valid_domain ();
  print_endline "slice semantic tests passed"
