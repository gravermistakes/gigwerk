(*
   Independent semantic test suite for exercise 005, Reverse a List.

   Compile only with a module Generated that supplies:
     val rev : 'a list -> 'a list

   This file is intentionally independent of Synquid inputs and contains no
   candidate implementation.  The reference oracle is test-only.
*)
open Generated

exception Test_failure of string

let failf fmt = Printf.ksprintf (fun message -> raise (Test_failure message)) fmt

let show_int_list xs =
  "[" ^ String.concat "; " (List.map string_of_int xs) ^ "]"

let show_string_list xs =
  "[" ^ String.concat "; " (List.map (Printf.sprintf "%S") xs) ^ "]"

(* Test-only oracle: this definition is deliberately isolated from synthesis. *)
let reference_reverse xs =
  List.fold_left (fun reversed x -> x :: reversed) [] xs

let run_case name test =
  try
    test ();
    Printf.printf "PASS %s\n%!" name;
    true
  with
  | Test_failure message ->
      Printf.printf "FAIL %s: %s\n%!" name message;
      false
  | exn ->
      Printf.printf "FAIL %s: unexpected exception %s\n%!" name
        (Printexc.to_string exn);
      false

let result_or_failure thunk =
  try Ok (thunk ()) with exn -> Error (Printexc.to_string exn)

let assert_int_reverse name input =
  let expected = reference_reverse input in
  match result_or_failure (fun () -> rev input) with
  | Error exn ->
      failf "%s: expected exact reverse %s, but rev raised %s"
        name (show_int_list expected) exn
  | Ok actual when actual = expected -> ()
  | Ok actual ->
      failf "%s: expected exact reverse %s, got %s"
        name (show_int_list expected) (show_int_list actual)

let assert_string_reverse name input =
  let expected = reference_reverse input in
  match result_or_failure (fun () -> rev input) with
  | Error exn ->
      failf "%s: expected exact reverse %s, but rev raised %s"
        name (show_string_list expected) exn
  | Ok actual when actual = expected -> ()
  | Ok actual ->
      failf "%s: expected exact reverse %s, got %s"
        name (show_string_list expected) (show_string_list actual)

let assert_function_reverse name input expected =
  match result_or_failure (fun () -> rev input) with
  | Error exn ->
      failf "%s: expected a returned function list, but rev raised %s" name exn
  | Ok actual ->
      if List.length actual <> List.length expected then
        failf "%s: expected list length %d, got %d" name
          (List.length expected) (List.length actual);
      if not (List.for_all2 ( == ) actual expected) then
        failf "%s: functions were not returned in exact reverse order" name

let rec lists_of_length alphabet n =
  if n = 0 then [ [] ]
  else
    List.concat
      (List.map
         (fun head -> List.map (fun tail -> head :: tail) (lists_of_length alphabet (n - 1)))
         alphabet)

let exhaustive_lists alphabet max_length =
  let rec loop n acc =
    if n > max_length then List.rev acc
    else loop (n + 1) (List.rev_append (lists_of_length alphabet n) acc)
  in
  loop 0 []

let test_exhaustive_small_lists () =
  let cases = exhaustive_lists [ -1; 0; 1 ] 5 in
  List.iteri
    (fun index input ->
      assert_int_reverse (Printf.sprintf "exhaustive case %d" index) input)
    cases

let test_involution () =
  let cases = exhaustive_lists [ 0; 1; 2 ] 4 in
  List.iteri
    (fun index input ->
      match result_or_failure (fun () -> rev input) with
      | Error exn -> failf "involution case %d: first rev raised %s" index exn
      | Ok once ->
          (match result_or_failure (fun () -> rev once) with
          | Error exn -> failf "involution case %d: second rev raised %s" index exn
          | Ok twice when twice = input -> ()
          | Ok twice ->
              failf "involution case %d: expected %s after two calls, got %s"
                index (show_int_list input) (show_int_list twice)))
    cases

let test_negative_control_identity_is_rejected () =
  (* NEGATIVE CONTROL: an identity implementation would return [1; 2; 3].
     This assertion specifically rejects that known-wrong behavior. *)
  let input = [ 1; 2; 3 ] in
  let forbidden_identity = input in
  match result_or_failure (fun () -> rev input) with
  | Error exn ->
      failf "negative control: rev must return [3; 2; 1], not raise %s" exn
  | Ok actual when actual <> forbidden_identity -> ()
  | Ok actual ->
      failf "negative control: identity output %s was incorrectly accepted"
        (show_int_list actual)

let tests =
  [
    ("official example: strings", fun () ->
      assert_string_reverse "official example" [ "a"; "b"; "c" ]);
    ("empty list", fun () -> assert_int_reverse "empty" []);
    ("singleton list", fun () -> assert_int_reverse "singleton" [ 42 ]);
    ("duplicate multiplicity and order", fun () ->
      assert_int_reverse "duplicates" [ 1; 2; 1; 3; 2 ]);
    ("negative control: reject identity", test_negative_control_identity_is_rejected);
    ("polymorphism: preserve function identities", fun () ->
      let first x = x + 1 in
      let second x = x * 2 in
      let third x = x - 3 in
      assert_function_reverse "function values" [ first; second; third ]
        [ third; second; first ]);
    ("exhaustive lists over {-1,0,1}, lengths 0..5", test_exhaustive_small_lists);
    ("involution over {0,1,2}, lengths 0..4", test_involution);
  ]

let () =
  let failures =
    List.fold_left
      (fun count (name, test) -> if run_case name test then count else count + 1)
      0 tests
  in
  if failures <> 0 then begin
    Printf.eprintf "%d semantic test(s) failed.\n%!" failures;
    exit 1
  end
