(* Independent semantic tests for the benchmark interface.
   Oracle logic is deliberately isolated from Synquid inputs. *)
open Generated

let failf fmt = Printf.ksprintf failwith fmt

let equal_option eq left right =
  match (left, right) with
  | None, None -> true
  | Some x, Some y -> eq x y
  | _ -> false

let assert_option ~label ~eq expected actual =
  if not (equal_option eq expected actual) then
    failf "%s: expected %s, got %s" label
      (match expected with None -> "None" | Some _ -> "Some <value>")
      (match actual with None -> "None" | Some _ -> "Some <value>")

let rec oracle_at index = function
  | [] -> None
  | x :: xs -> if index = 0 then Some x else oracle_at (index - 1) xs

let () =
  (* Official examples: indexing is zero-based. *)
  assert_option ~label:"official: index 2" ~eq:String.equal
    (Some "c") (at 2 ["a"; "b"; "c"; "d"; "e"]);
  assert_option ~label:"official: too-large index" ~eq:String.equal
    None (at 2 ["a"]);

  (* Boundary, order, and multiplicity checks. *)
  assert_option ~label:"head" ~eq:Int.equal (Some 10) (at 0 [10; 20; 30]);
  assert_option ~label:"last" ~eq:Int.equal (Some 30) (at 2 [10; 20; 30]);
  assert_option ~label:"empty" ~eq:Int.equal None (at 0 []);
  assert_option ~label:"past end" ~eq:Int.equal None (at 3 [10; 20; 30]);
  assert_option ~label:"duplicates preserve position" ~eq:Int.equal
    (Some 7) (at 1 [4; 7; 7; 9]);
  assert_option ~label:"polymorphic payload" ~eq:( = )
    (Some ("second", 2)) (at 1 [("first", 1); ("second", 2)]);

  (* Small exhaustive property check over the source-specified, nonnegative
     zero-based domain. The public statement does not state behavior for
     negative OCaml integers, so this harness intentionally does not assert it. *)
  let samples =
    [ []; [0]; [0; 1]; [1; 0]; [0; 1; 0]; [2; 1; 0] ]
  in
  List.iteri
    (fun sample_no xs ->
      List.iter
        (fun index ->
          assert_option
            ~label:(Printf.sprintf "exhaustive sample=%d index=%d" sample_no index)
            ~eq:Int.equal (oracle_at index xs) (at index xs))
        [0; 1; 2; 3; 4])
    samples;

  (* Deliberate negative control: this expectation must be false for any
     conforming implementation. It protects the harness against an off-by-one
     specification accidentally declaring index 2 to mean the second item. *)
  if equal_option String.equal (Some "b") (at 2 ["a"; "b"; "c"]) then
    failwith "NEGATIVE CONTROL triggered: index 2 must not select the second item";

  print_endline "semantic tests passed"
