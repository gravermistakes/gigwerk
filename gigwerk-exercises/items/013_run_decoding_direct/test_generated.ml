(*
   Independent semantic tests for exercise 013.

   This file is deliberately not a solution module.  It opens Generated, whose
   [encode] implementation is supplied later by a deterministic backend.  The
   reference oracle below is test-only and is never supplied to Synquid.
*)
open Generated

let fail name message =
  prerr_endline ("FAIL " ^ name ^ ": " ^ message);
  exit 1

let assert_equal name expected actual =
  if actual <> expected then fail name "semantic result differs from expectation"

let assert_true name condition =
  if not condition then fail name "semantic predicate is false"

let encode_or_fail name input =
  try encode input with
  | exn -> fail name ("encode raised " ^ Printexc.to_string exn)

let assert_encoding name input expected =
  assert_equal name expected (encode_or_fail name input)

(* Test-only oracle.  It makes maximal consecutive equality-runs and emits the
   canonical One/Many representation.  It is isolated in this test file and
   is not synthesis input. *)
let reference_encode xs =
  let node count value = if count = 1 then One value else Many (count, value) in
  let rec take_run count value = function
    | y :: ys when y = value -> take_run (count + 1) value ys
    | rest -> (count, rest)
  in
  let rec loop reversed_output = function
    | [] -> List.rev reversed_output
    | x :: xs ->
        let count, remaining = take_run 1 x xs in
        loop (node count x :: reversed_output) remaining
  in
  loop [] xs

let decode_for_test encoded =
  let rec copies n x reversed =
    if n = 0 then reversed else copies (n - 1) x (x :: reversed)
  in
  let rec loop reversed = function
    | [] -> List.rev reversed
    | One x :: rest -> loop (x :: reversed) rest
    | Many (n, x) :: rest -> loop (copies n x reversed) rest
  in
  loop [] encoded

let canonical encoded =
  let value = function One x | Many (_, x) -> x in
  let node_is_canonical = function One _ -> true | Many (n, _) -> n >= 2 in
  let rec distinct_neighbours = function
    | [] | [ _ ] -> true
    | left :: (right :: _ as tail) -> value left <> value right && distinct_neighbours tail
  in
  List.for_all node_is_canonical encoded && distinct_neighbours encoded

let all_lists_up_to alphabet max_length =
  let rec exact_length length =
    if length = 0 then [ [] ]
    else
      List.concat_map
        (fun suffix -> List.map (fun element -> element :: suffix) alphabet)
        (exact_length (length - 1))
  in
  let rec collect length =
    if length > max_length then [] else exact_length length @ collect (length + 1)
  in
  collect 0

let () =
  assert_encoding "empty list" ([] : int list) [];
  assert_encoding "singleton is One" [ 7 ] [ One 7 ];
  assert_encoding "one two-element run is Many" [ 7; 7 ] [ Many (2, 7) ];
  assert_encoding "one long run is Many" [ 7; 7; 7; 7 ] [ Many (4, 7) ];
  assert_encoding "alternating elements remain distinct singleton runs"
    [ 1; 2; 1; 2 ] [ One 1; One 2; One 1; One 2 ];
  assert_encoding "separated equal values do not merge across a different value"
    [ 1; 1; 2; 2; 1; 1 ] [ Many (2, 1); Many (2, 2); Many (2, 1) ];
  assert_encoding "official example"
    [ "a"; "a"; "a"; "a"; "b"; "c"; "c"; "a"; "a"; "d"; "e"; "e"; "e"; "e" ]
    [ Many (4, "a"); One "b"; Many (2, "c"); Many (2, "a"); One "d"; Many (4, "e") ];

  (* NEGATIVE CONTROL: this expectation is intentionally wrong: it merges the
     two non-adjacent runs of 1.  A conforming encoder must not produce it. *)
  let negative_control_input = [ 1; 1; 2; 2; 1; 1 ] in
  let deliberately_incorrect_expectation = [ Many (4, 1); Many (2, 2) ] in
  let observed = encode_or_fail "negative control (must execute)" negative_control_input in
  assert_true "negative control rejects non-consecutive-run merge"
    (observed <> deliberately_incorrect_expectation);

  (* Exhaustively cover all 364 integer lists over {0,1,2} of length at most 5.
     This checks exact ordering, multiplicity, maximality, and representation. *)
  let exhaustive_inputs = all_lists_up_to [ 0; 1; 2 ] 5 in
  List.iteri
    (fun index input ->
      let name = "exhaustive case " ^ string_of_int index in
      let observed = encode_or_fail name input in
      assert_equal name (reference_encode input) observed;
      assert_true (name ^ " canonical One/Many and maximal boundaries") (canonical observed);
      assert_equal (name ^ " decodes to original sequence") input (decode_for_test observed))
    exhaustive_inputs;
  print_endline "PASS: direct run-length encoding semantic suite"
