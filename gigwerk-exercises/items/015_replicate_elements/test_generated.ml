(**
  Independent semantic tests for Generated.replicate.

  Required unit under test:
    Generated.replicate : 'a list -> int -> 'a list

  The source statement gives an example only for a positive count.  These tests
  deliberately exercise counts >= 1; they do not invent behavior for zero or
  negative counts.  [reference_replicate] is a test-only oracle, isolated from
  synthesis inputs, and is not a proposed Generated implementation.
*)

open Generated

let show_int_list xs =
  "[" ^ String.concat "; " (List.map string_of_int xs) ^ "]"

let check_int_list ~name ~expected ~actual =
  if expected <> actual then
    failwith
      (name ^ "\n  expected: " ^ show_int_list expected ^
       "\n  actual:   " ^ show_int_list actual)

(* Test-only oracle.  Callers below provide only strictly positive counts. *)
let reference_replicate xs count =
  let rec copies value remaining =
    if remaining = 0 then [] else value :: copies value (remaining - 1)
  in
  let rec go = function
    | [] -> []
    | value :: rest -> copies value count @ go rest
  in
  go xs

let test_official_example () =
  let actual = replicate ["a"; "b"; "c"] 3 in
  let expected = ["a"; "a"; "a"; "b"; "b"; "b"; "c"; "c"; "c"] in
  if actual <> expected then
    failwith "official example: elements, grouping, or order differs"

let test_empty_input () =
  check_int_list ~name:"empty input repeated five times is empty"
    ~expected:[] ~actual:(replicate [] 5)

let test_one_copy_is_identity () =
  let input = [3; 1; 3; 2] in
  check_int_list ~name:"one copy preserves the entire original list"
    ~expected:input ~actual:(replicate input 1)

let test_duplicates_are_multiplied_not_deduplicated () =
  check_int_list ~name:"duplicate source values retain both multiplicity and groups"
    ~expected:[1; 1; 1; 1; 2; 2]
    ~actual:(replicate [1; 1; 2] 2)

let test_negative_control_expectation () =
  (* Deliberately incorrect expectation: whole-list repetition would produce
     [1; 2; 1; 2], but the required per-element grouping is [1; 1; 2; 2]. *)
  let deliberately_wrong = [1; 2; 1; 2] in
  let actual = replicate [1; 2] 2 in
  if actual = deliberately_wrong then
    failwith "negative control: accepted whole-list repetition instead of per-element replication"

let rec lists_of_length alphabet length =
  if length = 0 then [[]]
  else
    let tails = lists_of_length alphabet (length - 1) in
    List.concat (List.map (fun value -> List.map (fun tail -> value :: tail) tails) alphabet)

let all_lists alphabet maximum_length =
  let rec lengths n =
    if n > maximum_length then [] else lists_of_length alphabet n @ lengths (n + 1)
  in
  lengths 0

let test_small_exhaustive_cases () =
  List.iter
    (fun input ->
       List.iter
         (fun count ->
            check_int_list
              ~name:("exhaustive input=" ^ show_int_list input ^
                     ", positive count=" ^ string_of_int count)
              ~expected:(reference_replicate input count)
              ~actual:(replicate input count))
         [1; 2; 3; 4])
    (all_lists [0; 1] 3)

let () =
  test_official_example ();
  test_empty_input ();
  test_one_copy_is_identity ();
  test_duplicates_are_multiplied_not_deduplicated ();
  test_negative_control_expectation ();
  test_small_exhaustive_cases ();
  print_endline "replicate contract tests: passed"
