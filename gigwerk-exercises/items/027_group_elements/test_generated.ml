(*
   Independent tests for OCaml.org exercise 27, "Group the Elements of a Set
   Into Disjoint Subsets".  This file intentionally contains no implementation
   of Generated.group.  The small finite oracle below is test-only and is not a
   synthesis input: it enumerates labelled bucket assignments independently of
   any candidate implementation.
*)

open Generated

let failf fmt = Printf.ksprintf failwith fmt

let string_of_int_list_list_list xss =
  let one_group xs =
    "[" ^ String.concat "; " (List.map string_of_int xs) ^ "]"
  in
  let one_grouping groups =
    "[" ^ String.concat "; " (List.map one_group groups) ^ "]"
  in
  "[" ^ String.concat "; " (List.map one_grouping xss) ^ "]"

let assert_equal_int_groupings label expected actual =
  if expected <> actual then
    failf "%s: expected %s but got %s" label
      (string_of_int_list_list_list expected)
      (string_of_int_list_list_list actual)

let assert_equal_string_groupings label expected actual =
  if expected <> actual then
    failf "%s: exact official ordering/content mismatch" label

let protect thunk =
  try Ok (thunk ()) with exn -> Error (Printexc.to_string exn)

let assert_group_strings label input sizes expected =
  match protect (fun () -> group input sizes) with
  | Ok actual -> assert_equal_string_groupings label expected actual
  | Error raised ->
      failf "%s: semantic assertion failed because group raised %s" label raised

let canonicalize xss = List.sort compare xss

(* A deliberately independent finite oracle.  Each input occurrence is either
   unused or placed in one labelled bucket.  Buckets retain input order; a
   result is emitted exactly when every requested positive capacity is filled.
   Test cases use distinct inputs and strictly positive requested sizes, so they
   are within the unambiguous "set" / "group size" portion of the statement. *)
let reference_groupings (input : int list) (sizes : int list) =
  let capacities = Array.of_list sizes in
  let buckets = Array.make (Array.length capacities) [] in
  let found = ref [] in
  let rec visit = function
    | [] ->
        if Array.for_all (fun remaining -> remaining = 0) capacities then
          found := Array.to_list (Array.map List.rev buckets) :: !found
    | value :: rest ->
        (* The occurrence may be left outside the requested groups. *)
        visit rest;
        for bucket = 0 to Array.length capacities - 1 do
          if capacities.(bucket) > 0 then begin
            capacities.(bucket) <- capacities.(bucket) - 1;
            buckets.(bucket) <- value :: buckets.(bucket);
            visit rest;
            buckets.(bucket) <- List.tl buckets.(bucket);
            capacities.(bucket) <- capacities.(bucket) + 1
          end
        done
  in
  visit input;
  !found

let assert_complete_finite_set label input sizes =
  match protect (fun () -> group input sizes) with
  | Error raised ->
      failf "%s: semantic assertion failed because group raised %s" label raised
  | Ok actual ->
      assert_equal_int_groupings label
        (canonicalize (reference_groupings input sizes))
        (canonicalize actual)

let official_example_expected =
  [
    [["a"; "b"]; ["c"]]; [["a"; "c"]; ["b"]];
    [["b"; "c"]; ["a"]]; [["a"; "b"]; ["d"]];
    [["a"; "c"]; ["d"]]; [["b"; "c"]; ["d"]];
    [["a"; "d"]; ["b"]]; [["b"; "d"]; ["a"]];
    [["a"; "d"]; ["c"]]; [["b"; "d"]; ["c"]];
    [["c"; "d"]; ["a"]]; [["c"; "d"]; ["b"]]
  ]

let () =
  (* The supplied example is an exact sequence contract, not merely a set/count. *)
  assert_group_strings "official example" ["a"; "b"; "c"; "d"] [2; 1]
    official_example_expected;

  (* Small exhaustive grid: all listed positive size vectors against distinct
     input prefixes of lengths zero through four.  Canonicalization here is
     deliberately only for cases where the upstream statement supplies no
     general enumeration-order rule beyond its displayed example. *)
  let inputs = [[]; [0]; [0; 1]; [0; 1; 2]; [0; 1; 2; 3]] in
  let size_vectors = [[1]; [2]; [3]; [1; 1]; [1; 2]; [2; 1]; [2; 2]] in
  List.iter
    (fun input ->
      List.iter
        (fun sizes ->
          assert_complete_finite_set
            (Printf.sprintf "finite set: input length %d, sizes length %d"
               (List.length input) (List.length sizes))
            input sizes)
        size_vectors)
    inputs;

  (* Edge cases within the positive-size domain: capacity equal to input and
     requested capacity exceeding input. *)
  assert_complete_finite_set "all elements in one group" [0; 1; 2] [3];
  assert_complete_finite_set "impossible capacity has no groupings" [0; 1; 2] [4];

  (* NEGATIVE CONTROL: this intentionally wrong expected sequence reverses the
     official answer.  A correct candidate must reject it; accepting it means
     the exact-order test above is not discriminating. *)
  let intentionally_wrong = List.rev official_example_expected in
  match protect (fun () -> group ["a"; "b"; "c"; "d"] [2; 1]) with
  | Error raised ->
      failf "negative control semantic assertion failed because group raised %s" raised
  | Ok actual ->
      if actual = intentionally_wrong then
        failwith
          "negative control was accepted: official canonical traversal was not enforced";

  print_endline "group exercise tests passed"
