(* Independent semantic tests for exercise 028.
   This file is intentionally an oracle/test harness, not an implementation of
   either required algorithm. It uses only the OCaml standard library. *)
open Generated

exception Test_failure of string

let failf fmt = Printf.ksprintf (fun message -> raise (Test_failure message)) fmt

let same_outer_multiset left right =
  List.sort Stdlib.compare left = List.sort Stdlib.compare right

let nondecreasing key values =
  let rec loop = function
    | [] | [ _ ] -> true
    | first :: (second :: _ as tail) -> key first <= key second && loop tail
  in
  loop values

let length_frequency input wanted_length =
  List.fold_left
    (fun total inner -> if List.length inner = wanted_length then total + 1 else total)
    0 input

let check_outer_permutation ~case ~input ~actual =
  if not (same_outer_multiset input actual) then
    failf "%s: output is not a multiplicity-preserving permutation of the input" case

let check_length_result ~case ~input ~actual =
  check_outer_permutation ~case ~input ~actual;
  if not (nondecreasing List.length actual) then
    failf "%s: inner-list lengths are not nondecreasing" case

let check_frequency_result ~case ~input ~actual =
  let key inner = length_frequency input (List.length inner) in
  check_outer_permutation ~case ~input ~actual;
  if not (nondecreasing key actual) then
    failf "%s: input frequencies of inner-list lengths are not nondecreasing" case

(* The literal input/output pairs published in the official statement. They are
   checked as illustrations of the relation, while candidate checking below does
   not impose an unstated tie order. *)
let official_input =
  [ [ "a"; "b"; "c" ]; [ "d"; "e" ]; [ "f"; "g"; "h" ]; [ "d"; "e" ];
    [ "i"; "j"; "k"; "l" ]; [ "m"; "n" ]; [ "o" ] ]

let official_length_sort_output =
  [ [ "o" ]; [ "d"; "e" ]; [ "d"; "e" ]; [ "m"; "n" ];
    [ "a"; "b"; "c" ]; [ "f"; "g"; "h" ]; [ "i"; "j"; "k"; "l" ] ]

let official_frequency_sort_output =
  [ [ "i"; "j"; "k"; "l" ]; [ "o" ]; [ "a"; "b"; "c" ];
    [ "f"; "g"; "h" ]; [ "d"; "e" ]; [ "d"; "e" ]; [ "m"; "n" ] ]

let test_official_examples () =
  check_length_result ~case:"official displayed length_sort result"
    ~input:official_input ~actual:official_length_sort_output;
  check_frequency_result ~case:"official displayed frequency_sort result"
    ~input:official_input ~actual:official_frequency_sort_output;
  check_length_result ~case:"official length_sort candidate" ~input:official_input
    ~actual:(length_sort official_input);
  check_frequency_result ~case:"official frequency_sort candidate" ~input:official_input
    ~actual:(frequency_sort official_input)

let test_edge_cases () =
  let cases =
    [ ("empty outer list", []);
      ("one empty inner list", [ [] ]);
      ("several empty inner lists", [ []; []; [] ]);
      ("equal lengths with distinct contents", [ [ 7 ]; [ 8 ]; [ 9 ] ]);
      ("repeated equal inner lists", [ [ 1; 2 ]; []; [ 1; 2 ]; [ 3 ]; [] ]);
      ("mixed lengths and multiplicities", [ [ 0; 0 ]; [ 1 ]; [ 2; 2 ]; [ 3; 3; 3 ]; [ 4 ] ]) ]
  in
  List.iter
    (fun (name, input) ->
      check_length_result ~case:(name ^ " / length_sort") ~input
        ~actual:(length_sort input);
      check_frequency_result ~case:(name ^ " / frequency_sort") ~input
        ~actual:(frequency_sort input))
    cases

let alphabet = [ []; [ 0 ]; [ 0; 1 ]; [ 2; 3; 4 ] ]

let rec words_of_length count =
  if count = 0 then [ [] ]
  else
    List.concat
      (List.map
         (fun tail -> List.map (fun item -> item :: tail) alphabet)
         (words_of_length (count - 1)))

let exhaustive_outer_inputs =
  List.concat (List.map words_of_length [ 0; 1; 2; 3; 4 ])

let test_small_exhaustive_cases () =
  List.iteri
    (fun index input ->
      let label = Printf.sprintf "exhaustive outer case %d" index in
      check_length_result ~case:(label ^ " / length_sort") ~input
        ~actual:(length_sort input);
      check_frequency_result ~case:(label ^ " / frequency_sort") ~input
        ~actual:(frequency_sort input))
    exhaustive_outer_inputs

(* Deliberately incorrect negative control: a candidate that drops every inner
   list must trigger the same semantic assertion used for Generated.length_sort.
   This proves the harness does not merely check output shape or length. *)
let test_negative_control () =
  let mutant _ = [] in
  let input = [ [ 1 ]; [ 2; 3 ]; [ 1 ] ] in
  let rejected =
    try
      check_length_result ~case:"negative-control mutant" ~input ~actual:(mutant input);
      false
    with
    | Test_failure _ -> true
  in
  if not rejected then
    failf "negative-control mutant unexpectedly satisfied the length_sort contract"

let () =
  test_negative_control ();
  test_official_examples ();
  test_edge_cases ();
  test_small_exhaustive_cases ();
  Printf.printf "028_sort_list: semantic tests passed (%d exhaustive outer inputs).\n%!"
    (List.length exhaustive_outer_inputs)
