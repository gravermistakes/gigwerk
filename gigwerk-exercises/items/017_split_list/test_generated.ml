(* Independent semantic tests for exercise 017.
   This file intentionally contains no implementation of Generated.split.
   It uses a separate oracle only for test expectations. *)

open Generated

let fail name detail =
  Printf.eprintf "FAIL %s: %s\n%!" name detail;
  exit 1

let expect_equal name expected actual =
  if actual <> expected then fail name "semantic assertion failed"

let expect_not_equal name forbidden actual =
  if actual = forbidden then fail name "negative-control expectation was accepted"

(* Independent oracle. Calls below use only n >= 0, the source-defined domain. *)
let oracle_split xs n =
  let rec loop remaining count prefix_rev =
    match remaining, count with
    | rest, 0 -> (List.rev prefix_rev, rest)
    | [], _ -> (List.rev prefix_rev, [])
    | x :: rest, k -> loop rest (k - 1) (x :: prefix_rev)
  in
  loop xs n []

let test_official_examples () =
  expect_equal "official: first part length 3"
    (["a"; "b"; "c"], ["d"; "e"; "f"; "g"; "h"; "i"; "j"])
    (split ["a"; "b"; "c"; "d"; "e"; "f"; "g"; "h"; "i"; "j"] 3);
  expect_equal "official: requested length exceeds list"
    (["a"; "b"; "c"; "d"], [])
    (split ["a"; "b"; "c"; "d"] 5)

let test_edges () =
  expect_equal "empty at zero" ([], []) (split ([] : int list) 0);
  expect_equal "empty past end" ([], []) (split ([] : int list) 4);
  expect_equal "zero leaves every element in second part"
    ([], [1; 2; 3]) (split [1; 2; 3] 0);
  expect_equal "exact length consumes input"
    ([1; 2; 3], []) (split [1; 2; 3] 3);
  expect_equal "past end saturates at input length"
    ([1; 2; 3], []) (split [1; 2; 3] 99)

let test_order_and_multiplicity () =
  expect_equal "duplicates and order are preserved"
    ([2; 1; 2], [1; 2]) (split [2; 1; 2; 1; 2] 3);
  expect_equal "contiguous prefix/suffix boundary"
    ([4; 3], [2; 1]) (split [4; 3; 2; 1] 2)

let rec lists_of_length alphabet length =
  if length = 0 then [ [] ]
  else
    let tails = lists_of_length alphabet (length - 1) in
    List.concat (List.map (fun x -> List.map (fun tail -> x :: tail) tails) alphabet)

let test_small_exhaustive () =
  for length = 0 to 5 do
    List.iter
      (fun xs ->
        for n = 0 to length + 3 do
          expect_equal
            (Printf.sprintf "exhaustive length=%d n=%d" length n)
            (oracle_split xs n)
            (split xs n)
        done)
      (lists_of_length [0; 1] length)
  done

let test_negative_control () =
  (* Deliberately incorrect expectation: it preserves the value set but is not
     a contiguous, order-preserving prefix/suffix split. A conforming target
     must not produce it. *)
  let deliberately_incorrect = ([1; 3], [2; 4]) in
  expect_not_equal "NEGATIVE CONTROL rejects scrambled split"
    deliberately_incorrect (split [1; 2; 3; 4] 2)

let () =
  test_official_examples ();
  test_edges ();
  test_order_and_multiplicity ();
  test_small_exhaustive ();
  test_negative_control ();
  Printf.printf "PASS exercise 017 split tests\n%!"
