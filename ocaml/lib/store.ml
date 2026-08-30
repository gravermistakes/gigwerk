(* Store access. Shells out to the sqlite3 CLI rather than binding libsqlite3,
 * which keeps Phase 1 free of opam. Replace with ocaml-sqlite3 when the
 * dependency is worth having; every call site goes through here. *)

let db_path = ref "gigwerk.db"

let sh cmd =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 1024 in
  (try while true do Buffer.add_channel buf ic 1 done with End_of_file -> ());
  ignore (Unix.close_process_in ic);
  Buffer.contents buf

let query sql =
  sh (Printf.sprintf "sqlite3 -noheader -separator '|' %s %s"
        (Filename.quote !db_path) (Filename.quote sql))
  |> String.split_on_char '\n'
  |> List.filter_map (fun l ->
         let l = String.trim l in
         if l = "" then None else Some (String.split_on_char '|' l))

let exec sql =
  ignore (sh (Printf.sprintf "sqlite3 %s %s 2>&1"
                (Filename.quote !db_path) (Filename.quote sql)))

(* `exec` captures stderr and then throws it away, so a CHECK violation or a
 * typo'd column fails with no OCaml-visible signal at all -- the row simply is
 * not there, and the next read reports absence rather than error. That is
 * tolerable for a fire-and-forget note and intolerable for a booking verdict:
 * the refusals are the training signal, and a silently dropped refusal reads
 * downstream as "this composition was never proposed".
 *
 * sqlite3 exits nonzero on error but also prints; both are checked, because a
 * CHECK constraint failure prints "Runtime error" on some builds while still
 * exiting 0 inside a transaction that then rolls back. *)
let exec_checked sql =
  let cmd = Printf.sprintf "sqlite3 -bail %s %s 2>&1"
              (Filename.quote !db_path) (Filename.quote sql) in
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 256 in
  (try while true do Buffer.add_channel buf ic 1 done with End_of_file -> ());
  let status = Unix.close_process_in ic in
  let out = String.trim (Buffer.contents buf) in
  match status with
  | Unix.WEXITED 0 when out = "" -> Ok ()
  | Unix.WEXITED 0 -> Error out
  | Unix.WEXITED n -> Error (Printf.sprintf "sqlite3 exit %d: %s" n out)
  | Unix.WSIGNALED n -> Error (Printf.sprintf "sqlite3 killed by signal %d" n)
  | Unix.WSTOPPED n -> Error (Printf.sprintf "sqlite3 stopped %d" n)

let esc s =
  String.concat "''" (String.split_on_char '\'' s)

(* Capability claims for an entity, as (name, scope) pairs. This is the build
   instruction list -- the runtime constructs exactly these and nothing else. *)
let claims ~entity =
  query (Printf.sprintf
    "SELECT cc.capability, COALESCE(cc.scope,'') FROM c_capability cc \
     JOIN entity e ON e.id = cc.entity_id WHERE e.name = '%s' ORDER BY 1"
    (esc entity))
  |> List.filter_map (function [ n; s ] -> Some (n, s) | _ -> None)

let policies ~entity =
  query (Printf.sprintf
    "SELECT cp.predicate FROM c_policy cp JOIN entity e ON e.id = cp.entity_id \
     WHERE e.name = '%s' ORDER BY 1" (esc entity))
  |> List.filter_map (function [ p ] -> Some p | _ -> None)

let budget ~entity =
  match query (Printf.sprintf
    "SELECT b.wall_ms FROM c_budget b JOIN entity e ON e.id = b.entity_id \
     WHERE e.name = '%s'" (esc entity)) with
  | [ [ w ] ] -> (try int_of_string (String.trim w) with _ -> 30000)
  | _ -> 30000

let provenance ~entity =
  match query (Printf.sprintf "SELECT provenance FROM entity WHERE name = '%s'"
                 (esc entity)) with
  | [ [ p ] ] -> String.trim p
  | _ -> "human"

let entity_exists ~entity =
  match query (Printf.sprintf "SELECT 1 FROM entity WHERE name = '%s'"
                 (esc entity)) with
  | [ _ ] -> true | _ -> false

(* Prediction is written BEFORE the gig runs and outcome after, in separate
   statements, because a log of what happened without a log of what was expected
   is history rather than an error signal. *)
(* One connection, both statements: last_insert_rowid() is per-connection, and
   the sqlite3 CLI opens a new one per invocation. Splitting these silently
   yielded gig_id=0 and orphaned every outcome row. *)
let open_gig ~entity ~sig_ ~tier ~predicts ~falsifiable_by =
  let script = Printf.sprintf
    "BEGIN; \
     INSERT INTO gig (entity_id, composition_sig, booked_at, started_at, tier) \
     SELECT id, '%s', strftime('%%s','now'), strftime('%%s','now'), '%s' \
       FROM entity WHERE name = '%s'; \
     INSERT INTO gig_prediction (gig_id, predicts, falsifiable_by, made_at) \
     VALUES (last_insert_rowid(), '%s', '%s', strftime('%%s','now')); \
     SELECT gig_id FROM gig_prediction ORDER BY gig_id DESC LIMIT 1; \
     COMMIT;"
    (esc sig_) (esc tier) (esc entity) (esc predicts) (esc falsifiable_by) in
  let out = sh (Printf.sprintf "sqlite3 %s %s 2>&1"
                  (Filename.quote !db_path) (Filename.quote script)) in
  String.trim out

let close_gig ~gig_id ~outcome ~matched ~note =
  exec (Printf.sprintf
    "UPDATE gig SET ended_at = strftime('%%s','now') WHERE id = %s; \
     INSERT INTO gig_outcome (gig_id, outcome, matched, observed_at, note) \
     VALUES (%s, '%s', '%s', strftime('%%s','now'), '%s');"
    gig_id gig_id (esc outcome) (esc matched) (esc note))

(* --------------------------------------------------------------- reviews *)

(* The human's review is the source of confidence. Nothing else writes this
 * table: not the critic (mechanical, already recorded as gig_outcome.matched),
 * not the AI (its rank is stored beside a verdict, never instead of one).
 *
 * form_review has an FK to form(sig). The FK is not enforced by default in
 * sqlite, but the join in v_form_confidence is -- an orphaned review is simply
 * invisible to every band, which is how three reviews once "passed" while
 * silently inserting nothing. So the form row is created first, in the same
 * connection, and the whole thing is one transaction. *)
let write_review ~form_sig ~gig_id ~held ~critic_passed ~judge_refuted ~soul_version =
  exec_checked (Printf.sprintf
    "BEGIN; \
     INSERT INTO form_review \
       (form_sig, gig_id, prediction_held, critic_passed, judge_refuted, \
        human_reviewed, soul_version, at) \
     SELECT '%s', %s, '%s', %d, %d, 1, %s, strftime('%%s','now') \
     WHERE EXISTS (SELECT 1 FROM form WHERE sig = '%s'); \
     COMMIT;"
    (esc form_sig)
    (match gig_id with Some g -> g | None -> "NULL")
    (esc held) (if critic_passed then 1 else 0) (if judge_refuted then 1 else 0)
    (match soul_version with Some s -> "'" ^ esc s ^ "'" | None -> "NULL")
    (esc form_sig))

let gig_form ~gig_id =
  match query (Printf.sprintf
    "SELECT composition_sig FROM gig WHERE id = %s" gig_id) with
  | [ [ s ] ] -> Some (String.trim s)
  | _ -> None

(* Rows in the exact shape Bridge.confidence wants, so the CLI does not reshape
   them and the two cannot drift. *)
let reviews ~form_sig : Bridge.review list =
  query (Printf.sprintf
    "SELECT prediction_held, critic_passed, judge_refuted, at FROM form_review \
     WHERE form_sig = '%s' ORDER BY at" (esc form_sig))
  |> List.filter_map (function
       | [ held; cp; jr; at ] ->
           let prediction = match String.trim held with
             | "yes" -> Bridge.Held
             | "partial" -> Bridge.Partial
             | _ -> Bridge.Not_held
           in
           Some { Bridge.form_sig; prediction;
                  critic_passed = String.trim cp = "1";
                  judge_refuted = String.trim jr = "1";
                  at = (try int_of_string (String.trim at) with _ -> 0) }
       | _ -> None)

let forms () =
  query "SELECT f.sig, f.cap_set, f.state_shape, \
         (SELECT count(*) FROM form_review r WHERE r.form_sig = f.sig) \
         FROM form f ORDER BY f.first_seen"
  |> List.filter_map (function
       | [ s; c; sh; n ] ->
           Some (String.trim s, String.trim c, String.trim sh,
                 (try int_of_string (String.trim n) with _ -> 0))
       | _ -> None)
