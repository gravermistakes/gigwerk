(* lib/answers.ml against a real store: every answer is delivered once, in
 * order, as stored, and a refusal is its own outcome whose missing words stay
 * missing. sqlite3 is driven through Proc, not a shell. *)
open Gigwerk

let pass = ref 0 and fail = ref 0
let check name b =
  if b then (incr pass; Printf.printf "  ok   %s\n" name)
  else (incr fail; Printf.printf "  FAIL %s\n" name)

let find_repo_file relpath =
  let rec go dir =
    if Sys.file_exists (Filename.concat dir relpath) then Filename.concat dir relpath
    else
      let parent = Filename.dirname dir in
      if parent = dir then failwith ("test_answers: no " ^ relpath)
      else go parent
  in
  go (Sys.getcwd ())

let schema_sql = find_repo_file "sql/schema.sql"
let seed_sql = find_repo_file "sql/seed.sql"

let sqlite db args =
  Proc.run ~root:(Sys.getcwd ()) ~timeout_s:10.
    (Array.concat [ [| "sqlite3"; "-bail"; db |]; args ])

let ok_sql db s =
  let o = sqlite db [| s |] in
  if o.Proc.exit_status <> Some 0 || String.trim o.Proc.stderr <> "" then
    failwith ("test_answers: " ^ s ^ ": " ^ o.Proc.stderr);
  String.trim o.Proc.stdout

let temp () =
  let db = Filename.temp_file "gigwerk_answers" ".sqlite3" in
  Sys.remove db; at_exit (fun () -> try Sys.remove db with _ -> ()); db

let fresh () =
  let db = temp () in
  ignore (ok_sql db ("SELECT 1;"));
  let o = sqlite db [| ".read " ^ schema_sql; ".read " ^ seed_sql |] in
  if o.Proc.exit_status <> Some 0 then failwith ("test_answers: load: " ^ o.Proc.stderr);
  db

let contains s sub =
  let n = String.length sub in
  let rec go i = i + n <= String.length s && (String.sub s i n = sub || go (i + 1)) in
  go 0

let index s sub =
  let n = String.length sub in
  let rec go i = if i + n > String.length s then -1
    else if String.sub s i n = sub then i else go (i + 1) in
  go 0

let commission db ~id ~at ?prediction ~outcome ~matched ~note () =
  ignore (ok_sql db (Printf.sprintf
    "INSERT INTO commission (id, entity_id, composition_sig, booked_at, tier) \
     SELECT %d, id, 'sig%d', %d, 'subprocess' FROM entity ORDER BY id LIMIT 1;" id id at));
  (match prediction with
   | Some (p, f) -> ignore (ok_sql db (Printf.sprintf
       "INSERT INTO commission_prediction VALUES (%d, '%s', '%s', %d);" id p f at))
   | None -> ());
  ignore (ok_sql db (Printf.sprintf
    "INSERT INTO commission_outcome VALUES (%d, '%s', '%s', %d, %s);"
    id outcome matched (at + 10)
    (match note with Some n -> "'" ^ n ^ "'" | None -> "NULL")))

let delivered db =
  match Answers.deliver ~db with
  | Ok (Answers.Delivered { raw; on_record }) -> Some (raw, on_record)
  | _ -> None

let () =
  print_endline "answers -- what the world said, delivered once";

  let missing = temp () in
  check "with no store there is nothing to deliver, and nothing is created"
    (Answers.deliver ~db:missing = Ok (Answers.No_store missing)
     && not (Sys.file_exists missing));

  let old = temp () in
  ignore (ok_sql old "CREATE TABLE t (x);");
  check "a store without v_answer is reported as predating it, not read as empty"
    (Answers.deliver ~db:old = Ok (Answers.Unanswerable old));

  let db = fresh () in
  check "a store with no outcomes has nothing new and nothing on record"
    (delivered db = Some ("", 0));

  (* Commission 2 was answered BEFORE commission 1, so "oldest first" and
     "lowest id first" disagree, and only the first passes. *)
  commission db ~id:2 ~at:100
    ~prediction:("synthesis reaches tests_passed", "any halt short of tests_passed")
    ~outcome:"refused" ~matched:"no" ~note:None ();
  commission db ~id:1 ~at:200
    ~prediction:("echo settles on its terminal phase", "no phase emitted")
    ~outcome:"completed" ~matched:"yes" ~note:(Some "pass") ();
  (match delivered db with
   | Some (raw, 2) ->
       check "every undelivered answer is printed, the falsifier beside the outcome"
         (contains raw "commission_id = 1" && contains raw "commission_id = 2"
          && contains raw "falsifiable_by = any halt short of tests_passed");
       check "oldest first, by when the world answered, not by id"
         (index raw "commission_id = 2" >= 0
          && index raw "commission_id = 2" < index raw "commission_id = 1");
       check "a refusal is printed as refused, and its absent words as NULL"
         (contains raw "outcome = refused" && contains raw "note = NULL");
       check "the row being delivered does not claim to be undelivered"
         (not (contains raw "delivered_at"))
   | _ -> check "the first delivery happened" false);
  check "a second session is told there is nothing new, not shown the same answers"
    (delivered db = Some ("", 2));

  commission db ~id:3 ~at:300 ~outcome:"failed" ~matched:"no" ~note:(Some "x") ();
  (match delivered db with
   | Some (raw, 3) ->
       check "only the answer that arrived since is delivered next time"
         (contains raw "commission_id = 3" && not (contains raw "commission_id = 1"));
       check "an outcome that settles no prediction still shows, its prediction NULL"
         (contains raw "predicts = NULL")
   | _ -> check "the third delivery happened" false);
  check "one delivery row per answer, none twice"
    (ok_sql db "SELECT count(*), count(DISTINCT commission_id) FROM answer_delivery;" = "3|3");

  print_endline "\nrefused -- range, not failure";
  check "an outcome word nobody declared is rejected by the store"
    ((sqlite db [| "INSERT INTO commission_outcome VALUES (3, 'declined', 'no', 1, NULL);" |])
       .Proc.exit_status <> Some 0);
  check "Aleph sees a refusal as neither a good nor a bad example of its shape"
    (ok_sql db "SELECT outcome || ':' || coalesce(good, 'unknown') FROM v_aleph_facts \
                ORDER BY commission_id;"
     = "completed:1\nrefused:unknown\nfailed:0");
  ignore (ok_sql db
    "INSERT INTO span (id, commission_id, name, phase, duration_ms) VALUES \
     (1, 1, 's', 'p', 5), (1, 2, 's', 'p', 5), (1, 3, 's', 'p', 5);");
  check "a declined part is not counted against the phase's completion rate"
    (ok_sql db "SELECT completion_rate FROM v_phase_cost WHERE phase = 'p';" = "0.5");

  Printf.printf "answers: %d passed, %d failed\n" !pass !fail;
  if !fail <> 0 then exit 1
