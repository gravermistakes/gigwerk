(* What the world answered since the last session.
 *
 * A session starts cold. It inherits the code and the predictions written into
 * the store, and nothing tells it how those predictions came out. This prints
 * every answer (a commission_outcome beside the commission_prediction it
 * settles, see v_answer) that has not yet been delivered, oldest first, exactly
 * as stored, and records the delivery in the same transaction, so each answer
 * goes out once and none is skipped.
 *
 * Raw means raw: sqlite3's own line mode, NULL printed as NULL. A refusal with
 * no words shows note = NULL, not a reason someone reconstructed for it.
 *
 * sqlite3 is run through Proc, with the statements as one argv element: no
 * shell, nothing to re-split. *)

type delivery =
  | No_store of string
  | Unanswerable of string      (* the store predates v_answer *)
  | Delivered of { raw : string; on_record : int }

let sql ~db ?(mode = [||]) statements =
  let o = Proc.run ~root:(Sys.getcwd ()) ~timeout_s:10.
      (Array.concat [ [| "sqlite3"; "-bail" |]; mode; [| db; statements |] ]) in
  match o.Proc.exit_status with
  | Some 0 when String.trim o.Proc.stderr = "" -> Ok o.Proc.stdout
  | Some 0 -> Error (String.trim o.Proc.stderr)
  | Some n -> Error (Printf.sprintf "sqlite3 exit %d: %s" n (String.trim o.Proc.stderr))
  | None -> Error "sqlite3 timed out"

(* delivered_at is left out of the printout: on these rows it is NULL only
   until this transaction commits, and printing NULL would say "undelivered"
   about the very answer being delivered. *)
let undelivered =
  "SELECT commission_id, entity, shape, tier, soul_version, predicts, \
          falsifiable_by, predicted_at, outcome, matched, note, observed_at \
   FROM v_answer WHERE delivered_at IS NULL \
   ORDER BY observed_at, commission_id"

let deliver ~db =
  if not (Sys.file_exists db) then Ok (No_store db)
  else
    let ( let* ) = Result.bind in
    let* has_view =
      sql ~db "SELECT count(*) FROM sqlite_master WHERE type = 'view' AND name = 'v_answer';" in
    if String.trim has_view <> "1" then Ok (Unanswerable db)
    else
      let* raw =
        sql ~db ~mode:[| "-line"; "-nullvalue"; "NULL" |]
          (Printf.sprintf
             "BEGIN IMMEDIATE; %s; \
              INSERT INTO answer_delivery (commission_id, delivered_at) \
              SELECT commission_id, strftime('%%s','now') FROM v_answer \
              WHERE delivered_at IS NULL; \
              COMMIT;" undelivered) in
      let* n = sql ~db "SELECT count(*) FROM v_answer;" in
      let on_record = try int_of_string (String.trim n) with _ -> 0 in
      Ok (Delivered { raw; on_record })

let render = function
  | No_store db ->
      Printf.sprintf "gigwerk answers: no store at %s, so no commission has been answered here.\n" db
  | Unanswerable db ->
      Printf.sprintf
        "gigwerk answers: %s has no v_answer view; it predates answer delivery \
         (sql/schema.sql). Nothing was delivered.\n" db
  | Delivered { raw; on_record } when String.trim raw = "" ->
      Printf.sprintf
        "gigwerk answers: nothing new. %d answer%s on record, all delivered before.\n"
        on_record (if on_record = 1 then "" else "s")
  | Delivered { raw; _ } ->
      "gigwerk answers: what the world said since the last session, oldest first, \
       as stored. Read these before the plans.\n\n" ^ raw
