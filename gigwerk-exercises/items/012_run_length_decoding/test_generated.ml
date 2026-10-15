(* Independent semantic tests for Generated.decode.
   This test file deliberately contains its own oracle and is not a synthesis input.
   It uses only the OCaml standard library. *)
open Generated

let fail name = failwith ("decode test failed: " ^ name)

let check_equal name expected actual =
  if expected <> actual then fail name

(* Oracle restricted to the positive run counts exercised below.  It intentionally
   makes no claim about malformed codes, whose behavior is absent from the source
   statement available to this benchmark item. *)
let rec oracle_repeat n x =
  if n = 0 then [] else x :: oracle_repeat (n - 1) x

let rec oracle_decode = function
  | [] -> []
  | One x :: rest -> x :: oracle_decode rest
  | Many (n, x) :: rest -> oracle_repeat n x @ oracle_decode rest

let test_empty_code () =
  check_equal "empty code decodes to empty list" [] (decode [])

let test_one_segment () =
  check_equal "One preserves its single element" ["z"] (decode [One "z"])

let test_official_example () =
  let code =
    [ Many (4, "a"); One "b"; Many (2, "c"); Many (2, "a");
      One "d"; Many (4, "e") ]
  in
  let expected =
    [ "a"; "a"; "a"; "a"; "b"; "c"; "c"; "a"; "a"; "d";
      "e"; "e"; "e"; "e" ]
  in
  check_equal "official example preserves run order and multiplicity" expected
    (decode code)

let test_adjacent_and_nonadjacent_runs () =
  let code = [Many (2, "b"); One "a"; Many (3, "b"); One "c"] in
  check_equal "same value in nonadjacent runs remains in encounter order"
    ["b"; "b"; "a"; "b"; "b"; "b"; "c"]
    (decode code)

let atoms = ["a"; "b"]
let valid_segments =
  List.concat
    [ List.map (fun x -> One x) atoms;
      List.concat
        [ List.map (fun x -> Many (2, x)) atoms;
          List.map (fun x -> Many (3, x)) atoms ] ]

let rec codes_of_length n =
  if n = 0 then [[]]
  else
    List.concat
      (List.map
         (fun head -> List.map (fun tail -> head :: tail) (codes_of_length (n - 1)))
         valid_segments)

let test_exhaustive_small_valid_codes () =
  for length = 0 to 4 do
    List.iter
      (fun code ->
        check_equal
          "exhaustive positive-count codes agree with independent oracle"
          (oracle_decode code) (decode code))
      (codes_of_length length)
  done

(* DELIBERATE NEGATIVE CONTROL: this expected value is intentionally wrong.
   It is opt-in because a correct decoder must make this assertion fail.  It
   demonstrates that this harness can reject a semantic mismatch; it is not a
   requirement imposed on Generated.decode. *)
let negative_control_intentionally_wrong_expectation () =
  check_equal "NEGATIVE CONTROL (this must fail)"
    ["a"; "a"]
    (decode [Many (3, "a")])

let () =
  test_empty_code ();
  test_one_segment ();
  test_official_example ();
  test_adjacent_and_nonadjacent_runs ();
  test_exhaustive_small_valid_codes ();
  match Sys.getenv_opt "RUN_NEGATIVE_CONTROL" with
  | Some "1" -> negative_control_intentionally_wrong_expectation ()
  | _ -> ()
