(*
   Independent benchmark tests for exercise 007_flatten_list.

   These tests open only the future mechanically lowered candidate module.
   The oracle below is test-only and must never be supplied as a synthesis
   component or represented as a generated candidate.
*)
open Generated

let failf fmt = Printf.ksprintf failwith fmt

let string_of_int_list xs =
  "[" ^ String.concat "; " (List.map string_of_int xs) ^ "]"

let string_of_string_list xs =
  "[" ^ String.concat "; " (List.map (Printf.sprintf "%S") xs) ^ "]"

let assert_int_list ~case expected actual =
  if expected <> actual then
    failf "%s: expected %s, got %s"
      case (string_of_int_list expected) (string_of_int_list actual)

let assert_string_list ~case expected actual =
  if expected <> actual then
    failf "%s: expected %s, got %s"
      case (string_of_string_list expected) (string_of_string_list actual)

let assert_true ~case condition =
  if not condition then failf "%s: assertion failed" case

(* Test-only denotational oracle.  It is deliberately isolated from Synquid
   inputs and from Generated; it states the depth-first, left-to-right leaf
   sequence against which bounded exhaustive inputs are compared. *)
let rec oracle_flatten_nodes = function
  | [] -> []
  | One x :: rest -> x :: oracle_flatten_nodes rest
  | Many children :: rest -> oracle_flatten_nodes children @ oracle_flatten_nodes rest

let test_official_example () =
  let input =
    [ One "a";
      Many [One "b"; Many [One "c"; One "d"]; One "e"] ]
  in
  assert_string_list
    ~case:"official example"
    ["a"; "b"; "c"; "d"; "e"]
    (flatten input)

let test_empty_top_level_list () =
  assert_int_list ~case:"empty top-level list" [] (flatten [])

let test_empty_many_nodes_contribute_no_leaf () =
  assert_int_list
    ~case:"empty nested lists"
    []
    (flatten [Many []; Many [Many []; Many []]])

let test_depth_first_left_to_right_order () =
  assert_int_list
    ~case:"depth-first left-to-right traversal"
    [1; 2; 3; 4; 5]
    (flatten [Many [One 1; Many [One 2; Many [One 3]]]; One 4; Many [One 5]])

let test_multiplicity_is_preserved () =
  assert_int_list
    ~case:"multiplicity preserved"
    [7; 7; 7; 2; 7]
    (flatten [One 7; Many [One 7; Many [One 7; One 2]]; One 7])

(* Deliberately chosen negative control expectation: an implementation that
   reverses encountered leaves must fail this exact-order assertion. *)
let test_negative_control_reversed_order_is_rejected () =
  let input = [Many [One 1; Many [One 2; One 3]]; One 4] in
  let expected = [1; 2; 3; 4] in
  let reversed_wrong_answer = [4; 3; 2; 1] in
  assert_true
    ~case:"negative control precondition: reversed result is semantically distinct"
    (reversed_wrong_answer <> expected);
  assert_int_list
    ~case:"negative control: generated flatten must not reverse leaf order"
    expected
    (flatten input)

let rec bounded_nodes depth =
  if depth = 0 then [One 0; One 1]
  else
    let smaller = bounded_nodes (depth - 1) in
    let singleton_children = List.map (fun node -> Many [node]) smaller in
    let pair_children =
      List.concat
        (List.map
           (fun left -> List.map (fun right -> Many [left; right]) smaller)
           smaller)
    in
    One 0 :: One 1 :: Many [] :: singleton_children @ pair_children

let bounded_top_level_lists nodes =
  []
  :: List.map (fun node -> [node]) nodes
  @ List.concat
      (List.map
         (fun left -> List.map (fun right -> [left; right]) nodes)
         nodes)

let test_bounded_exhaustive_semantics () =
  let inputs = bounded_top_level_lists (bounded_nodes 2) in
  List.iteri
    (fun index input ->
       assert_int_list
         ~case:(Printf.sprintf "bounded exhaustive case %d" index)
         (oracle_flatten_nodes input)
         (flatten input))
    inputs

let tests =
  [ "official example", test_official_example;
    "empty top-level", test_empty_top_level_list;
    "empty nested", test_empty_many_nodes_contribute_no_leaf;
    "depth-first order", test_depth_first_left_to_right_order;
    "multiplicity", test_multiplicity_is_preserved;
    "negative control", test_negative_control_reversed_order_is_rejected;
    "bounded exhaustive", test_bounded_exhaustive_semantics ]

let () =
  List.iter
    (fun (name, test) ->
       test ();
       Printf.printf "PASS %s\n%!" name)
    tests
