(* Independent semantic test suite for Exercise 033.
   Compile with a candidate module named Generated that exports:
     val coprime : int -> int -> bool

   This file deliberately opens Generated and contains no implementation of the
   exercise. Its reference oracle is test-only and is not synthesis input.
*)

open Generated

exception Test_failure of string

let failf fmt = Printf.ksprintf (fun message -> raise (Test_failure message)) fmt

let expect_bool label expected actual =
  if actual <> expected then
    failf "%s: expected %b, got %b" label expected actual

(* Test-only Euclidean oracle. Calls are restricted below to positive ints, so
   OCaml's integer remainder convention is immaterial to the benchmark domain. *)
let rec gcd_oracle a b =
  if b = 0 then a else gcd_oracle b (a mod b)

let reference_coprime a b = gcd_oracle a b = 1

let passed = ref 0
let failed = ref 0

let run label f =
  try
    f ();
    incr passed;
    Printf.printf "PASS %s\n%!" label
  with
  | Test_failure message ->
      incr failed;
      Printf.printf "FAIL %s: %s\n%!" label message
  | exn ->
      incr failed;
      Printf.printf "FAIL %s: unexpected exception %s\n%!" label
        (Printexc.to_string exn)

let check_pair label a b =
  expect_bool label (reference_coprime a b) (coprime a b)

let () =
  run "official example: 13 and 27 are coprime" (fun () ->
      expect_bool "coprime 13 27" true (coprime 13 27));

  run "official example: 20536 and 7826 are not coprime" (fun () ->
      expect_bool "coprime 20536 7826" false (coprime 20536 7826));

  run "unit boundary values" (fun () ->
      check_pair "coprime 1 1" 1 1;
      check_pair "coprime 1 97" 1 97;
      check_pair "coprime 97 1" 97 1);

  (* NEGATIVE CONTROL WITNESS: the explicitly labelled companion stub returns
     true for every input. It must fail this semantic expectation. *)
  run "negative-control witness: equal integers greater than one are not coprime"
    (fun () -> expect_bool "coprime 2 2" false (coprime 2 2));

  run "representative shared-factor pairs" (fun () ->
      check_pair "coprime 14 21" 14 21;
      check_pair "coprime 12 18" 12 18;
      check_pair "coprime 64 96" 64 96;
      check_pair "coprime 101 202" 101 202);

  run "representative coprime pairs" (fun () ->
      check_pair "coprime 17 29" 17 29;
      check_pair "coprime 35 64" 35 64;
      check_pair "coprime 1009 1024" 1009 1024);

  run "exhaustive positive grid 1..64 against independent oracle" (fun () ->
      for a = 1 to 64 do
        for b = 1 to 64 do
          check_pair (Printf.sprintf "grid (%d,%d)" a b) a b
        done
      done);

  run "symmetry over selected positive pairs" (fun () ->
      let pairs = [ (2, 3); (14, 21); (35, 64); (63, 81); (20536, 7826) ] in
      List.iter
        (fun (a, b) ->
          expect_bool (Printf.sprintf "symmetry (%d,%d)" a b)
            (coprime a b) (coprime b a))
        pairs);

  Printf.printf "SUMMARY passed=%d failed=%d\n%!" !passed !failed;
  if !failed <> 0 then exit 1
