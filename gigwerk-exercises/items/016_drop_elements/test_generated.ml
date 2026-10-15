(* Independent OCaml semantic tests for exercise 016.
   The system under test must provide [Generated.drop : 'a list -> int -> 'a list].
   This file deliberately does not contain a candidate implementation. *)
open Generated

let fail name detail =
  Printf.eprintf "FAIL %s: %s\n%!" name detail;
  exit 1

let check_equal name expected actual =
  if actual <> expected then
    fail name
      (Printf.sprintf "expected [%s], got [%s]"
         (String.concat "; " (List.map string_of_int expected))
         (String.concat "; " (List.map string_of_int actual)))

let check_equal_string name expected actual =
  if actual <> expected then
    fail name "result differs from the required ordered list"

let call_drop name xs n =
  try drop xs n with
  | exn -> fail name ("raised " ^ Printexc.to_string exn)

(* Oracle kept isolated from synthesis inputs.  It is intentionally a test
   helper, not a source for lowering into Generated. *)
let oracle_drop_every_nth xs n =
  if n <= 0 then invalid_arg "oracle_drop_every_nth: n must be positive";
  let rec go position = function
    | [] -> []
    | x :: rest ->
        if position = n then go 1 rest
        else x :: go (position + 1) rest
  in
  go 1 xs

let range lo hi =
  let rec loop i acc = if i < lo then acc else loop (i - 1) (i :: acc) in
  loop hi []

(* This detects the common wrong algorithm "return input unchanged".  It is
   a deliberate NEGATIVE CONTROL; it must not be used as an implementation. *)
let negative_control_unchanged xs _n = xs

let () =
  (* Official example. *)
  check_equal_string "official-example"
    ["a"; "b"; "d"; "e"; "g"; "h"; "j"]
    (call_drop "official-example"
       ["a"; "b"; "c"; "d"; "e"; "f"; "g"; "h"; "i"; "j"] 3);

  (* Edge cases and periodic-boundary cases. *)
  check_equal "empty" [] (call_drop "empty" [] 1);
  check_equal "n-is-one" [] (call_drop "n-is-one" [1; 2; 3; 4] 1);
  check_equal "n-exceeds-length" [1; 2; 3] (call_drop "n-exceeds-length" [1; 2; 3] 4);
  check_equal "exact-boundary" [1; 2; 4; 5]
    (call_drop "exact-boundary" [1; 2; 3; 4; 5; 6] 3);
  check_equal "multiple-boundaries" [1; 3; 5; 7]
    (call_drop "multiple-boundaries" [1; 2; 3; 4; 5; 6; 7; 8] 2);
  check_equal "duplicates-preserved" [7; 7; 7; 7]
    (call_drop "duplicates-preserved" [7; 7; 7; 7; 7; 7] 3);

  (* Small exhaustive oracle comparison; values are distinct so order errors
     cannot be masked by equality, and duplicate-specific coverage appears above. *)
  for n = 1 to 7 do
    for length = 0 to 8 do
      let xs = range 1 length in
      check_equal (Printf.sprintf "exhaustive-n=%d-length=%d" n length)
        (oracle_drop_every_nth xs n)
        (call_drop (Printf.sprintf "exhaustive-n=%d-length=%d" n length) xs n)
    done
  done;

  (* Deliberately incorrect NEGATIVE CONTROL expectation: an unchanged list
     must be rejected for the official input with n = 3. *)
  if negative_control_unchanged [1; 2; 3; 4; 5; 6] 3 = [1; 2; 4; 5] then
    fail "negative-control-unchanged" "bad control unexpectedly satisfies spec";

  print_endline "PASS exercise 016 semantic tests"
