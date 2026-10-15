(* Independent semantic tests for GigWerk exercise 006_palindrome.
   This file intentionally contains no implementation of [Generated.is_palindrome].
   The reference below is test-only and is isolated from the Synquid contract. *)

open Generated

let fail name expected actual =
  failwith
    (Printf.sprintf "%s: expected %b but got %b" name expected actual)

let check name expected actual =
  if actual <> expected then fail name expected actual

(* Test-only oracle: exact structural equality against the reversed finite list. *)
let expected_palindrome xs = xs = List.rev xs

let check_against_oracle name xs =
  check name (expected_palindrome xs) (is_palindrome xs)

let rec words alphabet length =
  if length = 0 then [ [] ]
  else
    let tails = words alphabet (length - 1) in
    List.concat
      (List.map
         (fun x -> List.map (fun tail -> x :: tail) tails)
         alphabet)

let () =
  (* NEGATIVE CONTROL: an incorrect [fun _ -> true] implementation must fail here. *)
  check "negative-control: not always true" false (is_palindrome [ 7; 8 ]);

  (* Official examples. *)
  check "official: xam ax" true (is_palindrome [ "x"; "a"; "m"; "a"; "x" ]);
  check "official: ab is not a palindrome" false (is_palindrome [ "a"; "b" ]);

  (* Empty, singleton, even, odd, duplicate, and positional edge cases. *)
  check "empty" true (is_palindrome ([] : int list));
  check "singleton" true (is_palindrome [ 42 ]);
  check "even length" true (is_palindrome [ 1; 2; 2; 1 ]);
  check "odd length" true (is_palindrome [ 1; 2; 3; 2; 1 ]);
  check "same elements but wrong positions" false (is_palindrome [ 1; 2; 1; 2 ]);
  check "duplicate multiplicity matters" false (is_palindrome [ 1; 1; 2; 1 ]);
  check "late mismatch" false (is_palindrome [ 0; 1; 2; 3; 2; 0 ]);

  (* Ordinary strings and finite floats exercise the polymorphic list interface. *)
  check "string values" true (is_palindrome [ "red"; "blue"; "red" ]);
  check "float values" true (is_palindrome [ 1.5; -0.0; 1.5 ]);
  check "float mismatch" false (is_palindrome [ 1.5; 0.0; 2.5 ]);

  (* Exhaustive finite property set: all ternary integer lists of lengths 0 through 6. *)
  for length = 0 to 6 do
    List.iteri
      (fun index xs ->
        check_against_oracle
          (Printf.sprintf "exhaustive length=%d case=%d" length index)
          xs)
      (words [ 0; 1; 2 ] length)
  done;

  print_endline "palindrome semantic tests passed"
