(* Independent semantic tests for OCaml exercise 009.
   Required system under test: module Generated, value pack.
   The oracle below exists only in this test file and is not synthesis input. *)

open Generated

let fail name detail =
  failwith (Printf.sprintf "FAIL [%s]: semantic assertion failed: %s" name detail)

let expect_equal name expected actual =
  if actual <> expected then
    fail name
      (Printf.sprintf "expected %s but got %s"
         (Marshal.to_string expected [] |> String.escaped)
         (Marshal.to_string actual [] |> String.escaped))

(* Test-only oracle. It scans left-to-right, starts a new group precisely when
   the next value differs from the current run representative, and preserves
   values and group order. It is deliberately isolated from contract.sq. *)
let oracle_pack xs =
  let rec consume value reversed_run = function
    | next :: rest when next = value -> consume value (next :: reversed_run) rest
    | remaining -> (List.rev reversed_run, remaining)
  in
  let rec groups = function
    | [] -> []
    | first :: rest ->
        let group, remaining = consume first [first] rest in
        group :: groups remaining
  in
  groups xs

let flatten = List.concat

let all_equal = function
  | [] -> false
  | first :: rest -> List.for_all (fun value -> value = first) rest

let no_adjacent_equal_groups groups =
  let rec loop = function
    | [] | [_] -> true
    | current :: (next :: rest) ->
        List.hd current <> List.hd next && loop (next :: rest)
  in
  loop groups

let assert_packing_invariants name input output =
  if flatten output <> input then fail name "flattened groups do not reproduce the input sequence";
  if not (List.for_all (fun group -> group <> [] && all_equal group) output) then
    fail name "each group must be non-empty and contain only equal values";
  if not (no_adjacent_equal_groups output) then
    fail name "adjacent groups must have different representative values"

let check_case name input expected =
  let actual = pack input in
  expect_equal name expected actual;
  assert_packing_invariants name input actual

let rec words alphabet length =
  if length = 0 then [[]]
  else
    let shorter = words alphabet (length - 1) in
    List.concat (List.map (fun value -> List.map (fun tail -> value :: tail) shorter) alphabet)

let check_exhaustive_small_ints () =
  let alphabet = [0; 1; 2] in
  for length = 0 to 5 do
    List.iter
      (fun input ->
        let actual = pack input in
        expect_equal "exhaustive values 0..2, lengths 0..5" (oracle_pack input) actual;
        assert_packing_invariants "exhaustive values 0..2, lengths 0..5" input actual)
      (words alphabet length)
  done

let () =
  (* NEGATIVE CONTROL: an incorrect implementation that packs all non-empty
     input into one group must fail this exact expectation. *)
  check_case "NEGATIVE CONTROL: separated equal values are not coalesced"
    [1; 2; 1] [[1]; [2]; [1]];
  check_case "empty input" ([] : int list) [];
  check_case "singleton" [42] [[42]];
  check_case "all equal" [7; 7; 7; 7] [[7; 7; 7; 7]];
  check_case "all distinct" [1; 2; 3; 4] [[1]; [2]; [3]; [4]];
  check_case "same value separated by another run" [1; 1; 2; 1; 1] [[1; 1]; [2]; [1; 1]];
  check_case "official string example"
    ["a"; "a"; "a"; "a"; "b"; "c"; "c"; "a"; "a"; "d"; "d"; "e"; "e"; "e"; "e"]
    [["a"; "a"; "a"; "a"]; ["b"]; ["c"; "c"]; ["a"; "a"];
     ["d"; "d"]; ["e"; "e"; "e"; "e"]];
  check_exhaustive_small_ints ();
  print_endline "pack semantic tests: PASS"
