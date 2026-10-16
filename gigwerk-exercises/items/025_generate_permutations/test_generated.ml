(* Independent semantic tests for Exercise 025.
   This file deliberately contains no implementation of Generated.permutation.
   Compile it with an independently supplied Generated module, for example:
     ocamlc -o test_generated generated.ml test_generated.ml && ./test_generated
*)

open Generated

let fail label = raise (Failure label)

let assert_true label condition =
  if not condition then fail label

let rec list_equal eq left right =
  match (left, right) with
  | [], [] -> true
  | x :: xs, y :: ys -> eq x y && list_equal eq xs ys
  | _ -> false

(* Occurrence-sensitive comparison. This removes exactly one matching occurrence
   at a time, so [1; 1; 2] is not treated as equivalent to [1; 2; 2]. *)
let remove_one eq target values =
  let rec go prefix = function
    | [] -> None
    | value :: rest ->
        if eq target value then Some (List.rev_append prefix rest)
        else go (value :: prefix) rest
  in
  go [] values

let is_permutation eq input output =
  let rec consume remaining = function
    | [] -> remaining = []
    | value :: rest ->
        match remove_one eq value remaining with
        | None -> false
        | Some remaining' -> consume remaining' rest
  in
  consume input output

let assert_permutation label eq input =
  let output = permutation input in
  assert_true (label ^ ": length") (List.length output = List.length input);
  assert_true (label ^ ": occurrence-sensitive permutation")
    (is_permutation eq input output)

let () =
  (* Official input: order is not asserted because the exercise says random. *)
  assert_permutation "official example input" String.equal
    ["a"; "b"; "c"; "d"; "e"; "f"];

  (* Empty and singleton boundaries. *)
  assert_permutation "empty list" Int.equal [];
  assert_permutation "singleton" Int.equal [42];

  (* Duplicate-sensitive cases reject implementations that merely preserve a set. *)
  assert_permutation "all duplicates" Int.equal [7; 7; 7; 7];
  assert_permutation "interleaved duplicates" Int.equal [1; 2; 1; 3; 2; 1];
  assert_permutation "strings with repeated value" String.equal
    ["x"; "y"; "x"; "z"; "y"];

  (* Exhaustive inputs over a two-value alphabet through length four. *)
  let rec words alphabet length =
    if length = 0 then [ [] ]
    else
      List.concat_map
        (fun suffix -> List.map (fun item -> item :: suffix) alphabet)
        (words alphabet (length - 1))
  in
  for length = 0 to 4 do
    List.iter
      (fun input -> assert_permutation "exhaustive binary input" Int.equal input)
      (words [0; 1] length)
  done;

  (* Deliberately incorrect NEGATIVE CONTROL expectation: the occurrence-aware
     oracle must reject a same-length output that invents/loses multiplicity. *)
  assert_true "negative control: multiplicity mismatch is rejected"
    (not (is_permutation Int.equal [1; 1; 2] [1; 2; 2]));

  print_endline "permutation semantic tests completed"
