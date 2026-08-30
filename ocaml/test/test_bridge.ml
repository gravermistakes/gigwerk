(* Exercises Bridge against the real elpi and swipl binaries when they are
   present in this container, and forces the unavailable-engine and
   malformed-output paths deterministically either way (see the final report
   for whether each binary actually was present in this run). No assertion
   here holds regardless of the code under it -- every one was checked by
   mutation: break the thing it tests, watch it fail, restore. See the report
   for exactly which mutations were tried. *)
open Gigwerk

let pass = ref 0 and fail = ref 0
let check name b =
  if b then (incr pass; Printf.printf "  ok   %s\n" name)
  else (incr fail; Printf.printf "  FAIL %s\n" name)

let contains hay needle =
  let n = String.length needle and h = String.length hay in
  let rec go i = i + n <= h && (String.sub hay i n = needle || go (i + 1)) in go 0

let has_binary name =
  Sys.command (Printf.sprintf "command -v %s >/dev/null 2>&1" (Filename.quote name)) = 0

let write_file path contents =
  let oc = open_out path in
  output_string oc contents; close_out oc

let remove_quietly path = try Sys.remove path with Sys_error _ -> ()

(* ---------------------------------------------------------------- fixtures *)

(* Same catalog as elpi/facts_test.elpi, so the real end-to-end results below
   can be checked against the decisions elpi/README.md's own table already
   documents for these shapes. *)
let catalog =
  [ Bridge.{ name = "fs_read"; ctor = "Caps.fs_read"; envelope = "/srv/gigwerk";
             side_effecting = false; requires_booking = false };
    Bridge.{ name = "fs_write"; ctor = "Caps.fs_write"; envelope = "/srv/gigwerk";
             side_effecting = true; requires_booking = true } ]

let good = Bridge.{ clean_composition with entity = "good";
                     claims = [ ("fs_read", "/srv/gigwerk/work") ] }

(* THE classic bug from elpi/README.md: /srv/gigwerk-evil string-prefix-matches
   /srv/gigwerk but is not beneath it as a path. This is the load-bearing case:
   if segment splitting ever regressed to character- or string-level
   comparison, this is the composition that would silently start booking. *)
let sneaky = Bridge.{ clean_composition with entity = "sneaky";
                       claims = [ ("fs_read", "/srv/gigwerk-evil") ] }

let () =
  print_string "\ngenerator -- segment splitting is load-bearing\n";
  let two_seg = Bridge.{ clean_composition with entity = "gen_test";
                          claims = [ ("fs_read", "/foo/bar") ] } in
  let facts = Bridge.gate_facts ~capabilities:[] two_seg in
  check "a two-segment scope splits into a proper elpi segment list"
    (contains facts "claim \"gen_test\" \"fs_read\" [\"foo\",\"bar\"].");
  check "segments_of_path drops empty segments from leading/trailing/double slashes"
    (Bridge.segments_of_path "/a//b/" = [ "a"; "b" ]);
  let cat2 = [ Bridge.{ name = "x"; ctor = "c"; envelope = "/a/b";
                        side_effecting = false; requires_booking = false } ] in
  let facts2 = Bridge.gate_facts ~capabilities:cat2 Bridge.clean_composition in
  check "the capability catalog's envelope is segmented the same way as claim scopes"
    (contains facts2 "[\"a\",\"b\"]");
  let with_policy = Bridge.{ clean_composition with entity = "p";
                              policies = [ "some_unusual_policy_name" ] } in
  let facts3 = Bridge.gate_facts ~capabilities:[] with_policy in
  check "policy names are accepted on the composition but gate.elpi has no fact for them"
    (not (contains facts3 "some_unusual_policy_name"));
  check "a nested state shape parenthesises exactly like facts_test2.elpi's own fixture"
    (Bridge.elpi_shape_arg
       (Bridge.Tarrow (Bridge.Tunit, Bridge.Tlist (Bridge.Tarrow (Bridge.Tstring, Bridge.Tint))))
     = "(tarrow tunit (tlist (tarrow tstring tint)))");
  check "an atomic state shape needs no parens, matching facts_test.elpi's tunit"
    (Bridge.elpi_shape_arg Bridge.Tunit = "tunit")

let () =
  print_string "\nadversarial tie-break -- layered on top of elpi, not inside it\n";
  check "a tie between support and refutation escalates book to refuse"
    (let c = Bridge.{ clean_composition with support_strength = 2; refutation_strength = 2 } in
     match Bridge.apply_adversarial_tie c (Bridge.Book, []) with
     | { decision = Bridge.Refuse; reasons = [ r ] } ->
         r = "refutation_at_least_as_strong_as_support"
     | _ -> false);
  check "elpi's own hard refusal is never overridden by a strong support count"
    (let c = Bridge.{ clean_composition with support_strength = 0; refutation_strength = 100 } in
     match Bridge.apply_adversarial_tie c (Bridge.Refuse, [ "scope widens envelope for fs_read" ]) with
     | { decision = Bridge.Refuse; reasons = [ "scope widens envelope for fs_read" ] } -> true
     | _ -> false);
  check "support strictly exceeding refutation leaves elpi's queue decision alone"
    (let c = Bridge.{ clean_composition with support_strength = 3; refutation_strength = 1 } in
     match Bridge.apply_adversarial_tie c (Bridge.Queue, [ "x" ]) with
     | { decision = Bridge.Queue; reasons = [ "x" ] } -> true
     | _ -> false);
  check "zero refutation never escalates, even against zero support"
    (let c = Bridge.{ clean_composition with support_strength = 0; refutation_strength = 0 } in
     match Bridge.apply_adversarial_tie c (Bridge.Book, []) with
     | { decision = Bridge.Book; reasons = [] } -> true
     | _ -> false)

let () =
  print_string "\ngate -- real elpi, end to end\n";
  if has_binary "elpi" then begin
    check "a scope beneath its envelope books, with no reasons (elpi/README.md's own 'good')"
      (match Bridge.gate ~capabilities:catalog good with
       | Ok { decision = Bridge.Book; reasons = [] } -> true
       | _ -> false);
    check "a widened scope refuses -- gigwerk-evil vs gigwerk, exactly elpi/README.md's 'sneaky'"
      (match Bridge.gate ~capabilities:catalog sneaky with
       | Ok { decision = Bridge.Refuse; reasons = [ "scope widens envelope for fs_read" ] } -> true
       | _ -> false)
  end else
    print_string "  SKIP  elpi is not installed in this container\n"

let () =
  print_string "\ngate -- unavailable engine\n";
  let r = Bridge.gate ~elpi_bin:"/nonexistent/bin/elpi" ~capabilities:catalog good in
  check "a missing elpi binary is a typed Engine_missing, not an exception"
    (match r with Error (Bridge.Engine_missing _) -> true | _ -> false);
  check "the documented fail-safe for an unavailable gate is refuse"
    (Bridge.gate_fail_safe = Bridge.Refuse)

let () =
  print_string "\ngate -- malformed output (real elpi, a fixture program standing in for gate.elpi)\n";
  if has_binary "elpi" then begin
    let fixture = Filename.temp_file "bridge_test_bad_gate_" ".elpi" in
    (* Declares the same fact/shape signatures as the real gate.elpi (so the
       facts `gate_facts` generates for `good` still typecheck -- omitting
       these turned this into an Engine_failed typecheck error instead of the
       Bad_output this test wants, caught by running it and reading the real
       error), but never runs `decide`: `main` always prints an unrecognised
       decision word regardless of the entity it is asked about. *)
    write_file fixture
      "type capability string -> string -> list string -> bool -> bool -> prop.\n\
       type claim string -> string -> list string -> prop.\n\
       type provenance string -> string -> prop.\n\
       type tier string -> string -> prop.\n\
       type state_shape string -> ty -> prop.\n\
       type system_owns string -> string -> prop.\n\
       type human_verdict string -> prop.\n\
       type refused string -> prop.\n\
       kind ty type.\n\
       type tunit ty. type tstring ty. type tint ty.\n\
       type tlist ty -> ty. type tpair ty -> ty -> ty. type tarrow ty -> ty -> ty.\n\
       pred main i:list string.\n\
       main _ :- print \"decision: maybe\".\n";
    let r = Bridge.gate ~gate_file:fixture ~capabilities:catalog good in
    check "an elpi program that prints an unrecognised decision word is a typed Bad_output"
      (match r with Error (Bridge.Bad_output _) -> true | _ -> false);
    remove_quietly fixture
  end else
    print_string "  SKIP  elpi is not installed in this container\n"

let () =
  print_string "\nconfidence -- real swipl, end to end\n";
  if has_binary "swipl" then begin
    (* 14 clean reviews (at 1..14) plus one recent failure (at 1001) -- same
       shape as confidence.pl's own one_recent_failure_blocks_autopass test,
       verified by hand: band b_last_review, certainty 14/15 = 0.9333. *)
    let reviews =
      List.init 14 (fun i ->
          Bridge.{ form_sig = "bridge_b"; prediction = Held; critic_passed = true;
                   judge_refuted = false; at = i + 1 })
      @ [ Bridge.{ form_sig = "bridge_b"; prediction = Not_held; critic_passed = true;
                   judge_refuted = false; at = 1001 } ]
    in
    check "14/15 with the one failure most recent lands in b_last_review at ~0.9333"
      (match Bridge.confidence ~form_sig:"bridge_b" reviews with
       | Ok { band = Bridge.B_last_review; certainty } -> Float.abs (certainty -. (14. /. 15.)) < 0.001
       | _ -> false)
  end else
    print_string "  SKIP  swipl is not installed in this container\n"

let () =
  print_string "\nconfidence -- unavailable engine\n";
  let r = Bridge.confidence ~swipl_bin:"/nonexistent/bin/swipl" ~form_sig:"whatever" [] in
  check "a missing swipl binary is a typed Engine_missing, not an exception"
    (match r with Error (Bridge.Engine_missing _) -> true | _ -> false);
  check "the documented fail-safe for unavailable confidence is needs_review"
    (Bridge.confidence_fail_safe = Bridge.C_needs_review)

let () =
  print_string "\nconfidence -- malformed output (real swipl, a fixture standing in for confidence.pl)\n";
  if has_binary "swipl" then begin
    let fixture = Filename.temp_file "bridge_test_bad_conf_" ".pl" in
    write_file fixture ":- module(confidence, [band/3]).\nband(_, weird_unexpected_band, 0.42).\n";
    let r = Bridge.confidence ~confidence_file:fixture ~form_sig:"whatever" [] in
    check "a confidence.pl that reports an unrecognised band is a typed Bad_output"
      (match r with Error (Bridge.Bad_output _) -> true | _ -> false);
    remove_quietly fixture
  end else
    print_string "  SKIP  swipl is not installed in this container\n"

let () =
  Printf.printf "\n%d passed, %d failed\n" !pass !fail;
  if !fail > 0 then exit 1
