(* Durable form for the four modules that otherwise lose everything on exit:
 * Embed (via the vectors embedded in a Reconstruct.doc), Reconstruct,
 * Introspect and Trace. Every statement here goes through Store.query,
 * Store.exec and Store.esc -- nothing new was added to Store, so this file
 * inherits Store's shelling-out design whole, including three sharp edges
 * that are not obvious from reading store.ml alone. Each is worked around
 * HERE, in the SQL this file writes, because store.ml itself is out of
 * bounds:
 *
 * 1. NULL and '' ARE THE SAME STRING ON THE WAY OUT.
 *    `Store.query` shells out to `sqlite3 -noheader -separator '|'` with no
 *    `.nullvalue` set, and sqlite's default nullvalue is ''. A NULL column
 *    and a column holding the empty string print identically, so a plain
 *    `SELECT full FROM sarcasm_doc` cannot tell "no full form was kept"
 *    apart from "a full form was kept and it is empty". Every nullable TEXT
 *    column read back in this file is therefore selected as a pair --
 *    `CASE WHEN col IS NULL THEN 0 ELSE 1 END, COALESCE(col, '')` -- so the
 *    presence bit travels separately from the value. A nullable INTEGER
 *    column (`span.parent`) does not need the pair: no valid integer ever
 *    prints as '', so '' is unambiguously NULL there.
 *
 * 2. SQLITE'S OWN `printf('%g', ...)` CANNOT BE ASKED FOR ENOUGH PRECISION.
 *    sqlite's default text rendering of a REAL truncates to `%.15g`, and
 *    fifteen significant digits is not always enough to round-trip an
 *    IEEE754 double -- seventeen is the proven worst-case bound. The obvious
 *    fix, asking sqlite's `printf('%!.17g', col)` SQL function for more
 *    digits, does NOT work: measured directly, plain `%.Ng` in sqlite's
 *    printf caps out around sixteen significant digits no matter how large N
 *    is -- `%.17g`, `%.20g` and `%.30g` all produced the IDENTICAL, still-
 *    truncated string for a value that genuinely needs its 17th digit, and
 *    that string reparses to a DIFFERENT double than the one stored (found
 *    by hand while building this file: a real, not a theoretical, failure --
 *    see the report). What actually works is sqlite's own `!` printf flag --
 *    `printf('%!.17g', col)` -- which is documented sqlite-specific behavior
 *    telling it to compute genuine digits out to the requested precision
 *    instead of its normal fast (and here, wrong) path. Every affect tone
 *    and every `at` timestamp is read back through `%!.17g`, never bare and
 *    never through plain `%g`. `vec` does not need any of this:
 *    Embed.to_string/of_string already own that encoding end to end, as
 *    plain text, never touching sqlite's REAL affinity at all.
 *
 * 3. A ROW THAT PRINTS AS ALL EMPTY COLUMNS DOES NOT COME BACK.
 *    `Store.query` trims each output line and drops it if the trim is ''.
 *    A row whose only selected column happens to render as '' -- NULL,
 *    or a genuinely empty string, or (with (2) fixed) never a truncated
 *    float -- is therefore indistinguishable from no row at all: the query
 *    returns [] instead of [[ "" ]]. Every query in this file keeps at
 *    least one column that can never itself be empty (an id, a position, a
 *    0/1 flag), purely so the row cannot vanish this way.
 *
 * A fourth limitation is NOT worked around, because doing so would mean
 * inventing a second text encoding on top of plain SQL strings: `query`
 * splits on raw '\n' between rows and raw '|' between columns, with no
 * escaping. A digest, a full text, or an introspection entry that contains
 * a literal newline or pipe will misparse on the way back out. Nothing here
 * can fix that without changing store.ml, which is out of scope; it is
 * reported instead of patched around. Keep persisted prose to text without
 * embedded newlines or pipes until store.ml grows a real serialization. *)

let sql_str s = "'" ^ Store.esc s ^ "'"
let sql_opt_str = function None -> "NULL" | Some s -> sql_str s
let sql_float f = Printf.sprintf "%.17g" f   (* see limitation (2) above *)

let join_list sep xs = String.concat (String.make 1 sep) xs
let split_list sep s = if s = "" then [] else String.split_on_char sep s

(* ===================================================================== *)
(* SARCASM: Reconstruct.doc, and the [[links]] pulled out of its digest.  *)
(* ===================================================================== *)

let doc_select_cols =
  "id, digest, CASE WHEN full IS NULL THEN 0 ELSE 1 END, COALESCE(full,''), vec, \
   printf('%!.17g', affect_surprise), printf('%!.17g', affect_hazard), \
   printf('%!.17g', affect_novelty), printf('%!.17g', affect_cost), \
   printf('%!.17g', affect_dissonance), printf('%!.17g', affect_valence)"

(* Same eleven columns whether one row was asked for or all of them, so
   load_doc and load_store cannot drift into parsing rows two different
   ways. *)
let parse_doc_row = function
  | [ id; digest; full_flag; full_val; vec_s; sur; haz; nov; cost; dis; vale ] ->
      let full =
        match full_flag with
        | "1" -> Some full_val
        | "0" -> None
        | f -> failwith (Printf.sprintf "persist: bad full-flag %s for doc %s" f id)
      in
      { Reconstruct.id; digest; full;
        vec = Embed.of_string vec_s;
        affect = { Affect.surprise   = float_of_string sur;
                   hazard     = float_of_string haz;
                   novelty    = float_of_string nov;
                   cost       = float_of_string cost;
                   dissonance = float_of_string dis;
                   valence    = float_of_string vale } }
  | row ->
      failwith (Printf.sprintf "persist: sarcasm_doc row has %d fields, expected 11"
                  (List.length row))

(* Upserts the doc row, then WIPES AND REBUILDS its outgoing sarcasm_link
   rows from Reconstruct.links. Delete-then-reinsert, never an incremental
   diff, because sarcasm_link is a projection of `digest` (see persist.sql):
   the only way it can never say something `digest` does not is to be
   rebuilt from `digest` in full on every save, not patched. All of it goes
   through one Store.exec call, matching how store.ml itself bundles
   related statements (open_gig/close_gig) rather than risking a partial
   write split across two shelled-out connections. *)
let save_doc (d : Reconstruct.doc) : unit =
  let a = d.Reconstruct.affect in
  let id = Store.esc d.Reconstruct.id in
  let links = Reconstruct.links d in
  let link_sql =
    if links = [] then ""
    else
      let value i target =
        Printf.sprintf "('%s', %s, %d)" id (sql_str target) i in
      Printf.sprintf
        "INSERT INTO sarcasm_link (from_id, to_id, position) VALUES %s;"
        (String.concat ", " (List.mapi value links))
  in
  Store.exec (Printf.sprintf
    "INSERT OR REPLACE INTO sarcasm_doc \
       (id, digest, full, vec, affect_surprise, affect_hazard, affect_novelty, \
        affect_cost, affect_dissonance, affect_valence) \
     VALUES ('%s', %s, %s, %s, %s, %s, %s, %s, %s, %s); \
     DELETE FROM sarcasm_link WHERE from_id = '%s'; \
     %s"
    id (sql_str d.Reconstruct.digest) (sql_opt_str d.Reconstruct.full)
    (sql_str (Embed.to_string d.Reconstruct.vec))
    (sql_float a.Affect.surprise) (sql_float a.Affect.hazard)
    (sql_float a.Affect.novelty) (sql_float a.Affect.cost)
    (sql_float a.Affect.dissonance) (sql_float a.Affect.valence)
    id link_sql)

let load_doc (id : string) : Reconstruct.doc option =
  match Store.query (Printf.sprintf
      "SELECT %s FROM sarcasm_doc WHERE id = %s;" doc_select_cols (sql_str id)) with
  | [] -> None
  | [ row ] -> Some (parse_doc_row row)
  | _ -> failwith ("persist: more than one sarcasm_doc row for id " ^ id)

(* The ids a doc links to, in the order they appear in its digest --
   `position` rides along as the query's non-empty guard column (limitation
   (3) above); to_id alone could in principle be '' if a digest ever
   contained a literal "[[]]", and would then vanish from the result
   instead of coming back as "". *)
let doc_links (from_id : string) : string list =
  Store.query (Printf.sprintf
    "SELECT position, to_id FROM sarcasm_link WHERE from_id = %s ORDER BY position;"
    (sql_str from_id))
  |> List.map (function
      | [ _pos; to_id ] -> to_id
      | row -> failwith (Printf.sprintf "persist: sarcasm_link row has %d fields, expected 2"
                           (List.length row)))

let save_store (s : Reconstruct.store) : unit =
  Hashtbl.iter (fun _ d -> save_doc d) s

let load_store () : Reconstruct.store =
  let s = Reconstruct.store () in
  Store.query (Printf.sprintf "SELECT %s FROM sarcasm_doc;" doc_select_cols)
  |> List.iter (fun row -> Reconstruct.add s (parse_doc_row row));
  s

(* ===================================================================== *)
(* INTROSPECT: read and write solely for the AI.                         *)
(* ===================================================================== *)

(* save_introspect reads with Introspect.peek, not Introspect.read/all. Peek
   takes no token and earns none: saving is a PROJECTION of entries the AI
   already committed, not a new entry, and it must not manufacture a token
   it has no business spending. *)
let save_introspect (t : Introspect.t) : unit =
  let entries = Introspect.peek t in
  let row (e : Introspect.entry) =
    Printf.sprintf "(%d, %s, %s, %s, %s)"
      e.Introspect.id
      (sql_str e.Introspect.text)
      (sql_str (join_list ',' e.Introspect.tags))
      (sql_str (join_list ',' (List.map string_of_int e.Introspect.links)))
      (sql_float e.Introspect.at)
  in
  (* Wipe-then-reinsert, unlike save_doc's upsert: Introspect has `forget`,
     so unlike a doc or a span, an entry that existed at the last save can
     legitimately not exist now. Diffing that correctly buys nothing an
     idle process needs; matching `peek` exactly does. *)
  let insert =
    if entries = [] then ""
    else Printf.sprintf
        "INSERT INTO introspect_entry (id, text, tags, links, at) VALUES %s;"
        (String.concat ", " (List.map row entries))
  in
  Store.exec (Printf.sprintf "DELETE FROM introspect_entry; %s" insert)

let parse_introspect_row = function
  | [ id; text; tags; links; at ] ->
      { Introspect.id = int_of_string id;
        text;
        tags = split_list ',' tags;
        links = List.map int_of_string (split_list ',' links);
        at = float_of_string at }
  | row ->
      failwith (Printf.sprintf "persist: introspect_entry row has %d fields, expected 5"
                  (List.length row))

(* THE TOKEN DISCIPLINE, ON LOAD.
 *
 * introspect.ml's whole design is that a write needs a token, and only
 * `read`/`all` mint one, because minting one for free is what turns the
 * notebook into a drawer nobody re-reads. load_introspect must not be a
 * second door into that: it never calls Introspect.write, never builds an
 * `Introspect.token` value, and never touches `gen` for any reason other
 * than initializing it -- exactly what Introspect.create does for a brand
 * new notebook. `gen` is set to 0 and `next` to one past the highest loaded
 * id, so the returned value behaves precisely like `create ()` would if
 * `create` accepted a starting entry list: the FIRST thing any caller must
 * do to append is call `read` or `all` on THIS value to obtain a token
 * whose `tgen` matches, exactly the sequence test_terms.ml exercises
 * against a freshly created notebook ("a fresh read earns a write").
 *
 * What this does NOT close, and cannot close from persist.ml: introspect.ml
 * ships with no .mli. `type t` and `type token` both expose their fields,
 * so ANY code holding an `Introspect.t` -- not just this loader, and not
 * only after persistence exists -- can already build a valid token by
 * reading the public field directly (`{ Introspect.tgen = t.gen }`) without
 * ever calling `read` or `all`. The read-before-write rule is enforced by
 * naming convention today, not by the type system; that is true of a value
 * from `create ()` as much as one from `load_introspect ()`. This file does
 * not make that hole any wider -- it never constructs a token and never
 * picks a `gen` value chosen to match one -- but it also cannot make the
 * hole narrower, because closing it means sealing introspect.ml behind an
 * .mli that keeps `token` and `t.gen` abstract, and introspect.ml is a file
 * this task does not own. Reported rather than patched. *)
let load_introspect () : Introspect.t =
  let rows =
    Store.query
      "SELECT id, text, tags, links, printf('%!.17g', at) \
       FROM introspect_entry ORDER BY id ASC;"
  in
  let entries_asc = List.map parse_introspect_row rows in
  let next = 1 + List.fold_left (fun acc e -> max acc e.Introspect.id) 0 entries_asc in
  (* `write` prepends (`t.entries <- e :: t.entries`), so the live
     representation is newest-first; `peek`/`all` reverse it back to
     insertion order for anyone reading. Rebuilding that same newest-first
     list here (rather than storing entries_asc as-is) means peek/by_tag/
     linked on a loaded value behave identically to peek/by_tag/linked on a
     value that reached the same state through a real sequence of writes. *)
  { Introspect.entries = List.rev entries_asc; next; gen = 0 }

(* ===================================================================== *)
(* TRACE: Trace.to_rows into the existing `span` table.                  *)
(* ===================================================================== *)

(* save_trace takes gig_id EXPLICITLY rather than reading it off `t`, and
 * that is not a convenience choice.
 *
 * `Trace.t.gig : string` and `span.gig_id : INTEGER NOT NULL REFERENCES
 * gig(id)` are two different kinds of identifier that happen to share a
 * name. Trace was written against a human-readable label (test_terms.ml's
 * own trace uses `Trace.create ~gig:"g1"`); the ledger's `gig` table uses a
 * surrogate integer key nothing in trace.ml ever produces or sees. There is
 * no function anywhere that turns one into the other, so `to_rows`' `gig`
 * field cannot be dropped into `span.gig_id` honestly -- either sqlite
 * stores it as text against an INTEGER-affinity column (silently, since a
 * label like "g1" cannot be cast) or, if the label happens to look
 * numeric, it lands in the ledger under the wrong gig's id entirely. This
 * is a pre-existing mismatch between trace.ml and schema.sql, not
 * something to paper over here: the caller is asked for the real ledger
 * gig_id instead, and `to_rows`' own `gig` string is not used at all. See
 * the report for the fuller version of this. *)
let save_trace ~(gig_id : int) (t : Trace.t) : unit =
  let rows = Trace.to_rows t in
  if rows <> [] then begin
    let row (id, parent, _gig, name, phase, duration_ms, outcome, breach) =
      let iopt = function None -> "NULL" | Some i -> string_of_int i in
      Printf.sprintf "(%d, %d, %s, %s, %s, %d, %s, %s)"
        id gig_id (iopt parent) (sql_str name) (sql_opt_str phase)
        duration_ms (sql_opt_str outcome) (sql_opt_str breach)
    in
    Store.exec (Printf.sprintf
      "INSERT OR REPLACE INTO span \
         (id, gig_id, parent, name, phase, duration_ms, outcome, breach) \
       VALUES %s;"
      (String.concat ", " (List.map row rows)))
  end

(* Raw rows back, not a Trace.t: `to_rows` already discards `started` and
 * `ended` (only their difference, `duration_ms`, survives -- see
 * trace.ml), and the `span` table was never given columns for them either,
 * so there is no absolute timestamp anywhere in this path to rebuild a
 * live span from. Fabricating one (e.g. `started = 0.0`) would be a made-up
 * number wearing a real field's name. The honest thing is the shape
 * `to_rows` itself returns, minus the `gig` string (see save_trace) and
 * with the caller's own gig_id as the lookup key instead. *)
let load_spans ~(gig_id : int)
    : (int * int option * string * string option * int * string option * string option) list =
  Store.query (Printf.sprintf
    "SELECT id, parent, name, \
       CASE WHEN phase IS NULL THEN 0 ELSE 1 END, COALESCE(phase, ''), \
       duration_ms, \
       CASE WHEN outcome IS NULL THEN 0 ELSE 1 END, COALESCE(outcome, ''), \
       CASE WHEN breach IS NULL THEN 0 ELSE 1 END, COALESCE(breach, '') \
     FROM span WHERE gig_id = %d ORDER BY id ASC;" gig_id)
  |> List.map (function
      | [ id; parent; name; pflag; pval; dur; oflag; oval; bflag; bval ] ->
          let opt tag flag value =
            match flag with
            | "1" -> Some value
            | "0" -> None
            | f -> failwith (Printf.sprintf "persist: bad %s-flag %s" tag f)
          in
          ( int_of_string id,
            (if parent = "" then None else Some (int_of_string parent)),
            name,
            opt "phase" pflag pval,
            int_of_string dur,
            opt "outcome" oflag oval,
            opt "breach" bflag bval )
      | row ->
          failwith (Printf.sprintf "persist: span row has %d fields, expected 10"
                      (List.length row)))
