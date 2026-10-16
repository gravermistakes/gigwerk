(*
   Independent semantic test harness for exercise 032_gcd.

   Expected candidate boundary:
     module Generated : sig val gcd : int -> int -> int end

   This file deliberately contains no candidate implementation.  Its reference
   oracle is test-only and is not an input to Synquid or to a future lowering
   backend.  The stated domain is positive OCaml integers; non-positive inputs
   are intentionally not tested because the authoritative exercise gives no
   behavior for them.
*)

open Generated

let fail label message = failwith (label ^ ": " ^ message)

let assert_int label expected actual =
  if actual <> expected then
    fail label
      (Printf.sprintf "expected %d but got %d" expected actual)

(* Test oracle only: Euclid's recurrence, kept isolated from synthesis inputs. *)
let reference_gcd a b =
  if a <= 0 || b <= 0 then invalid_arg "reference_gcd: positive inputs required";
  let rec loop x y = if y = 0 then x else loop y (x mod y) in
  loop a b

let check_gcd_laws a b =
  let actual = gcd a b in
  if actual <= 0 then
    fail "positive-result law"
      (Printf.sprintf "gcd %d %d returned non-positive %d" a b actual);
  if a mod actual <> 0 then
    fail "first-divisibility law"
      (Printf.sprintf "%d does not divide %d" actual a);
  if b mod actual <> 0 then
    fail "second-divisibility law"
      (Printf.sprintf "%d does not divide %d" actual b);
  assert_int
    (Printf.sprintf "greatestness/oracle law for gcd %d %d" a b)
    (reference_gcd a b) actual;
  assert_int
    (Printf.sprintf "symmetry law for gcd %d %d" a b)
    actual (gcd b a)

let test_official_examples () =
  assert_int "official example gcd 13 27" 1 (gcd 13 27);
  assert_int "official example gcd 20536 7826" 2 (gcd 20536 7826)

let test_edges () =
  List.iter
    (fun (a, b, expected) ->
      assert_int (Printf.sprintf "edge gcd %d %d" a b) expected (gcd a b);
      check_gcd_laws a b)
    [
      (1, 1, 1);
      (1, 997, 1);
      (997, 1, 1);
      (99991, 99991, 99991);
      (12, 18, 6);
      (54, 24, 6);
      (1_000_000_000, 600_000_000, 200_000_000);
    ]

let test_small_exhaustive_domain () =
  for a = 1 to 64 do
    for b = 1 to 64 do
      check_gcd_laws a b
    done
  done

let () =
  test_official_examples ();
  test_edges ();
  test_small_exhaustive_domain ();
  print_endline "032_gcd semantic tests: PASS"
