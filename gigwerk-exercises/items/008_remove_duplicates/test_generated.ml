(* Independent semantic tests for benchmark 008.  This file intentionally
   opens the future mechanically lowered candidate module; it contains no
   implementation of [compress]. *)
open Generated

let fail name detail =
  failwith ("FAIL " ^ name ^ ": " ^ detail)

let check_equal name expected actual =
  if actual <> expected then fail name "unexpected output"

let check_raises_invalid_argument name thunk =
  try
    ignore (thunk ());
    fail name "expected Invalid_argument from OCaml polymorphic equality"
  with
  | Invalid_argument _ -> ()

(* Independent oracle, deliberately isolated in tests rather than synthesis input. *)
let reference_compress xs =
  let rec go previous = function
    | [] -> []
    | x :: rest ->
        match previous with
        | Some p when p = x -> go previous rest
        | _ -> x :: go (Some x) rest
  in
  go None xs

let assert_oracle name xs =
  check_equal name (reference_compress xs) (compress xs)

let rec words alphabet n =
  if n = 0 then [ [] ]
  else
    let tails = words alphabet (n - 1) in
    List.concat
      (List.map (fun x -> List.map (fun suffix -> x :: suffix) tails) alphabet)

let assert_float_list name expected actual =
  let equal_float x y =
    (Float.is_nan x && Float.is_nan y) || x = y
  in
  if not (List.for_all2 equal_float expected actual) then
    fail name "unexpected float output"

let () =
  (* Official upstream example. *)
  check_equal "official example"
    ["a"; "b"; "c"; "a"; "d"; "e"]
    (compress ["a"; "a"; "a"; "a"; "b"; "c"; "c"; "a"; "a"; "d"; "e"; "e"; "e"; "e"]);

  (* Empty, singleton, one-run, and run-boundary cases. *)
  check_equal "empty" ([] : int list) (compress []);
  check_equal "singleton" [7] (compress [7]);
  check_equal "one maximal run" [7] (compress [7; 7; 7; 7]);
  check_equal "alternating values remain" [1; 2; 1; 2] (compress [1; 2; 1; 2]);
  check_equal "separated equal values are not globally deduplicated" [1; 2; 1]
    (compress [1; 1; 2; 2; 1; 1]);
  check_equal "run transitions" [0; 1; 0; 2; 3]
    (compress [0; 0; 1; 1; 0; 0; 2; 3; 3]);

  (* All finite words over a small alphabet through length 6: 1,093 cases. *)
  for n = 0 to 6 do
    List.iter (assert_oracle ("exhaustive ternary length " ^ string_of_int n))
      (words [0; 1; 2] n)
  done;

  (* Equality boundaries inherited from OCaml (=). *)
  let nan = 0. /. 0. in
  assert_float_list "nan values do not collapse"
    [nan; nan; 1.; nan; nan]
    (compress [nan; nan; 1.; 1.; nan; nan]);
  check_equal "zero and negative zero share a run" [0.; 2.]
    (compress [0.; -0.; 2.]);
  let f x = x in
  check_raises_invalid_argument "function values use OCaml equality" (fun () -> compress [f; f]);

  (* NEGATIVE CONTROL: this is deliberately the wrong global-dedup expectation.
     A conforming implementation must reject it by producing [1;2;1]. *)
  let negative_control_wrong_global_dedup_expectation = [1; 2] in
  let actual = compress [1; 1; 2; 2; 1; 1] in
  if actual = negative_control_wrong_global_dedup_expectation then
    fail "NEGATIVE CONTROL global dedup" "incorrect expectation unexpectedly held";

  print_endline "PASS benchmark 008 semantic tests"
