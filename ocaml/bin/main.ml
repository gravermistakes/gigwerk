(* gigwerk -- Phase 1: a capability-scoped task runner.
 *
 *   gigwerk run echo   --message "hello"
 *   gigwerk run critic --artifact notes.txt
 *   gigwerk caps
 *   gigwerk introspect list
 *   gigwerk doctor
 *
 * There is no gate yet. Compositions are read from the store and constructed;
 * nothing is validated beyond what the schema's foreign keys enforce. That is
 * Phase 2, and until it exists this is a runner, not a harness.
 *
 * The one Phase-2 piece that IS wired here is memory: `introspect` gives the AI
 * its notebook, persisted through Persist so it survives a restart (see the
 * cmd_introspect comment for exactly how the read-then-write rule is honored). *)

open Gigwerk

let usage () =
  prerr_string
    "gigwerk propose <echo|critic|scribe> [--grant read,query] [--budget N]\n\
    \              [--for SECS] [--support N] [--refute N]\n\
    \              [--message S] [--artifact PATH] [--db FILE]\n\
     gigwerk run <echo|critic> [--message S] [--artifact PATH] [--db FILE]\n\
     gigwerk review --gig N --held yes|partial|no [--critic pass|fail]\n\
    \              [--judge clear|refuted]\n\
     gigwerk forms [--db FILE]\n\
     gigwerk caps [--entity NAME]\n\
     gigwerk introspect list|read <id>|add|forget <id>|rewrite <id>\n\
    \\              [--text S] [--tag a,b] [--link 1,2] [--db FILE]\n\
     gigwerk doctor\n\
   \n\
   propose runs the whole path -- conditions, terms, kit fit, then the gig.\n\
   run skips it and calls the behavior directly; it is the pre-gate runner and\n\
   is kept only so the two can be compared.\n\
   introspect is the AI's notebook. It is read and written ONLY by the AI and\n\
   survives a restart because Persist round-trips it to the store. Every write\n\
   is preceded by a read (the token rule in introspect.ml is the point, not\n\
   boilerplate -- see that module for the drawer-vs-notebook argument).\n";
  exit 2

let arg name default argv =
  let rec go = function
    | a :: v :: _ when a = name -> v
    | _ :: t -> go t
    | [] -> default
  in
  go argv

(* Build exactly the capabilities the composition claims. A claim the store does
   not carry produces no field, and the behavior that needs it cannot be
   applied -- that is the type system refusing, not a runtime check. *)
let build_critic_caps ~entity =
  let claims = Store.claims ~entity in
  let find n = List.assoc_opt n claims in
  match find "fs_read", find "sqlite_query" with
  | Some root, Some db ->
      let db = if db = "" then !Store.db_path else db in
      Some Behaviors.{ root = Caps.fs_read ~root; ledger = Caps.sqlite_ro ~db }
  | _ -> None

(* `matched` answers "did the actor do its job", NOT "was the artifact good".
   A critic that correctly reports a bad artifact is a MATCHED prediction: the
   prediction was about the actor's behavior. A critic that could not read at
   all is unmatched, because it produced no verdict.

   This distinction was wrong on the first pass and only showed up in the
   ledger. It matters more than it looks: `matched` is what feeds the
   confidence rule, so mislabeling here silently corrupts every band. *)
let classify (o : Actor.outcome) =
  match o with
  | Actor.Completed d ->
      let is p = String.length d >= String.length p && String.sub d 0 (String.length p) = p in
      if is "pass" then ("completed", "yes", 0)
      else if is "fail|unreadable" then ("failed", "no", 2)
      else ("completed", "yes", 1)   (* a real verdict that happens to be fail *)
  | Actor.Budget_exceeded _ -> ("budget_exceeded", "no", 3)
  | Actor.Failed _ -> ("failed", "no", 2)
  | Actor.Crashed _ -> ("failed", "no", 2)

let report ~entity ~gig_id (o : Actor.outcome) =
  let outcome, matched, code = classify o in
  Store.close_gig ~gig_id ~outcome ~matched ~note:(Actor.outcome_detail o);
  Printf.printf "%-10s %-16s matched=%-4s gig=%s\n%s\n"
    entity outcome matched gig_id (Actor.outcome_detail o);
  code

let cmd_run argv =
  let entity = match argv with e :: _ when e <> "" && e.[0] <> '-' -> e | _ -> usage () in
  Store.db_path := arg "--db" !Store.db_path argv;
  if not (Store.entity_exists ~entity) then begin
    Printf.eprintf "no entity %S in %s -- seed it first\n" entity !Store.db_path;
    exit 3
  end;
  let wall_ms = Store.budget ~entity in
  let tier = if Store.provenance ~entity = "agent" then "subprocess" else "in_process" in
  match entity with
  | "echo" ->
      let msg = arg "--message" "" argv in
      let gig_id = Store.open_gig ~entity ~sig_:"echo/0" ~tier
          ~predicts:"echo returns the message unchanged"
          ~falsifiable_by:"returned detail differs from input" in
      let o = Actor.run_gig ~wall_ms ~work:(fun () ->
          Behaviors.verdict_to_string (Behaviors.echo () ~msg)) in
      exit (report ~entity ~gig_id o)
  | "critic" ->
      let artifact = arg "--artifact" "" argv in
      if artifact = "" then usage ();
      (match build_critic_caps ~entity with
       | None ->
           Printf.eprintf
             "critic requires fs_read and sqlite_query; composition claims: %s\n"
             (String.concat ", " (List.map fst (Store.claims ~entity)));
           exit 3
       | Some caps ->
           let gig_id = Store.open_gig ~entity ~sig_:"critic/2" ~tier
               ~predicts:"critic emits a verdict on the artifact"
               ~falsifiable_by:"critic produces no verdict (unreadable, crash, or budget kill)" in
           let o = Actor.run_gig ~wall_ms ~work:(fun () ->
               Behaviors.verdict_to_string (Behaviors.critic caps ~artifact)) in
           exit (report ~entity ~gig_id o))
  | e -> Printf.eprintf "unknown behavior %S\n" e; exit 2

(* ======================================================================= *)
(* propose: the whole path.                                                  *)
(*                                                                           *)
(* The envelope comes from THE HUMAN'S FLAGS, not from the entity's claims.   *)
(* That is the point of the ordering: if --grant defaulted to whatever the    *)
(* composition already claimed, the envelope would be derived from the thing  *)
(* it is supposed to bound, and every proposal would fit by construction.     *)
(* So the default is nothing, and `propose critic` refuses until a human      *)
(* authors an envelope that covers it. The refusal is the mechanism working.  *)
(* ======================================================================= *)

let int_arg name default argv =
  match int_of_string_opt (arg name (string_of_int default) argv) with
  | Some n -> n | None -> default

let parse_grants s =
  String.split_on_char ',' s
  |> List.map String.trim
  |> List.filter (fun x -> x <> "")
  |> List.fold_left
       (fun acc w ->
         match (acc, Grants.action_of_string w) with
         | Error e, _ -> Error e
         | Ok l, Some a -> Ok (a :: l)
         | Ok _, None -> Error w)
       (Ok [])
  |> Result.map List.rev

let kit_for = function
  | "echo" -> Some Kit.echo
  | "critic" -> Some Kit.critic
  | "scribe" -> Some Kit.scribe
  | _ -> None

(* The work thunk. `scribe` is absent on purpose -- see kit.ml. *)
let work_for ~entity ~msg ~artifact =
  match entity with
  | "echo" ->
      Some (fun (_ : Terms.t) ->
          let phase, payload = Behaviors.echo_step () ~msg in
          Booking.emit ~phase payload)
  | "critic" -> (
      match build_critic_caps ~entity with
      | None -> None
      | Some caps ->
          Some (fun (_ : Terms.t) ->
              let phase, payload = Behaviors.critic_step caps ~artifact in
              Booking.emit ~phase payload))
  | _ -> None

let cmd_propose argv =
  let entity =
    match argv with e :: _ when e <> "" && e.[0] <> '-' -> e | _ -> usage ()
  in
  Store.db_path := arg "--db" !Store.db_path argv;
  if not (Store.entity_exists ~entity) then begin
    Printf.eprintf "no entity %S in %s -- run: sqlite3 %s \".read sql/seed.sql\"\n"
      entity !Store.db_path !Store.db_path;
    exit 3
  end;
  let grants =
    match parse_grants (arg "--grant" "" argv) with
    | Ok g -> g
    | Error w -> Printf.eprintf "unknown action %S in --grant\n" w; exit 2
  in
  let claims = Store.claims ~entity in
  let cap_set = List.map fst claims in
  let policy_set = Store.policies ~entity in
  let state_shape =
    match Store.query (Printf.sprintf
      "SELECT s.shape FROM c_state s JOIN entity e ON e.id = s.entity_id \
       WHERE e.name = '%s'" (Store.esc entity)) with
    | [ [ sh ] ] -> String.trim sh
    | _ -> ""
  in
  let widen_epoch = int_arg "--widen-epoch" 0 argv in
  let sig_ =
    Booking.form_sig ~cap_set ~policy_set ~state_shape ~widen_epoch
  in
  let tier = if Store.provenance ~entity = "agent" then "subprocess" else "in_process" in
  let kit = match kit_for entity with
    | Some k -> k
    | None -> Printf.eprintf "no kit for %S\n" entity; exit 2
  in
  let kit_grants = match kit with Ok k -> k.Kit.grants | Error _ -> [] in
  let evidence =
    Booking.evidence_of_store ~entity ~sig_ ~tier ~kit_grants
      ~support_strength:(int_arg "--support" 1 argv)
      ~refutation_strength:(int_arg "--refute" 0 argv)
  in
  let now = Int64.of_float (Unix.time ()) in
  let envelope =
    Terms.issue ~id:("env/" ^ entity)
      ~grants:(Grants.make ~entity ~snapshot:sig_ ~actions:grants)
      ~budget:(int_arg "--budget" 5 argv)
      ~expires_at:(Int64.add now (Int64.of_int (int_arg "--for" 300 argv)))
  in
  let request =
    { Booking.entity; evidence; cap_set; policy_set; state_shape; widen_epoch;
      envelope; kit }
  in
  Printf.printf "form      %s\n" sig_;
  match Booking.book ~now request with
  | Error r ->
      (match Booking.record_refusal ~entity ~sig_ r with
       | Ok () -> ()
       | Error e -> Printf.eprintf "WARN could not record verdict: %s\n" e);
      Printf.printf "decision  %s\n%s\n"
        (Booking.decision_of_refusal r) (Booking.refusal_to_string r);
      exit (if Booking.decision_of_refusal r = "queue" then 4 else 5)
  | Ok b ->
      (match Booking.ensure_form b ~cap_set ~policy_set ~widen_epoch with
       | Ok () -> () | Error e -> Printf.eprintf "WARN form: %s\n" e);
      (match Booking.record_booking b with
       | Ok () -> () | Error e -> Printf.eprintf "WARN verdict: %s\n" e);
      Printf.printf
        "decision  book\nkit       %s\nwall_ms   %d\ngig_terms %s budget=%d\nenvelope  %d/%d spent\n"
        b.Booking.kit.Kit.name b.Booking.wall_ms
        (Grants.to_string (Terms.grants b.Booking.gig_terms))
        (Terms.budget b.Booking.gig_terms)
        (Terms.consumed b.Booking.envelope) (Terms.budget b.Booking.envelope);
      let msg = arg "--message" "" argv in
      let artifact = arg "--artifact" "" argv in
      (match work_for ~entity ~msg ~artifact with
       | None ->
           Printf.printf
             "no behavior wired for %S -- booked, not run\n" entity;
           exit 0
       | Some work ->
           let gig_id =
             Store.open_gig ~entity ~sig_ ~tier
               ~predicts:(Printf.sprintf "%s settles on its terminal phase" b.Booking.kit.Kit.name)
               ~falsifiable_by:"no phase emitted, an undeclared phase, or a non-completed outcome"
           in
           let c = Booking.run b ~work in
           let outcome = Booking.outcome_word c and matched = Booking.matched c in
           Store.close_gig ~gig_id ~outcome ~matched ~note:c.Booking.payload;
           Printf.printf "gig       %s\noutcome   %s\nmatched   %s\nphase     %s%s\n%s\n"
             gig_id outcome matched
             (match Phases.current c.Booking.progress with Some p -> p | None -> "-")
             (match c.Booking.breach with
              | Some br -> " BREACH: " ^ Phases.breach_to_string br
              | None -> if c.Booking.settled then " (settled)" else "")
             c.Booking.payload;
           exit (if matched = "yes" then 0 else 1))

(* ======================================================================= *)
(* review: the human's verdict, which is the ONLY source of confidence.      *)
(*                                                                           *)
(* Three fields because matched = prediction held AND critic passed AND judge *)
(* failed to refute, and collapsing them to one boolean throws away which of  *)
(* the three burned the slot. The critic's mechanical verdict is already in    *)
(* gig_outcome; asking for it again here is not redundant -- this is the       *)
(* human's reading of it, and the two disagreeing is the signal that routes    *)
(* to a human next time.                                                      *)
(* ======================================================================= *)

let cmd_review argv =
  Store.db_path := arg "--db" !Store.db_path argv;
  let gig_id = arg "--gig" "" argv in
  if gig_id = "" then usage ();
  let held = arg "--held" "" argv in
  if not (List.mem held [ "yes"; "partial"; "no" ]) then begin
    prerr_string "--held must be yes, partial or no\n"; exit 2
  end;
  let critic_passed = arg "--critic" "pass" argv = "pass" in
  let judge_refuted = arg "--judge" "clear" argv = "refuted" in
  match Store.gig_form ~gig_id with
  | None -> Printf.eprintf "no gig %s in %s\n" gig_id !Store.db_path; exit 3
  | Some form_sig -> (
      match
        Store.write_review ~form_sig ~gig_id:(Some gig_id) ~held ~critic_passed
          ~judge_refuted ~soul_version:None
      with
      | Error e -> Printf.eprintf "could not write review: %s\n" e; exit 3
      | Ok () ->
          let n = List.length (Store.reviews ~form_sig) in
          Printf.printf "recorded review %d for form %s\n" n form_sig;
          (* A review that lands but changes no band is a review that did not
             reach the form -- the FK-orphan failure. Reading the band back is
             the cheapest proof it landed. *)
          (match Bridge.confidence ~form_sig (Store.reviews ~form_sig) with
           | Ok { band; certainty } ->
               Printf.printf "band      %s  certainty %.4f\n"
                 (Bridge.band_to_string band) certainty
           | Error e ->
               Printf.printf "band      %s (fail-safe)\n%s\n"
                 (Bridge.band_to_string Bridge.confidence_fail_safe)
                 (Bridge.engine_error_to_string e)))

let cmd_forms argv =
  Store.db_path := arg "--db" !Store.db_path argv;
  let rows = Store.forms () in
  if rows = [] then print_string "no forms yet -- run `gigwerk propose`\n"
  else
    List.iter
      (fun (sig_, caps, shape, n) ->
        let band =
          if n = 0 then "c_needs_review (no reviews)"
          else
            match Bridge.confidence ~form_sig:sig_ (Store.reviews ~form_sig:sig_) with
            | Ok { band; certainty } ->
                Printf.sprintf "%-14s %.4f" (Bridge.band_to_string band) certainty
            | Error _ ->
                Printf.sprintf "%-14s (engine unreachable)"
                  (Bridge.band_to_string Bridge.confidence_fail_safe)
        in
        Printf.printf "%s  n=%-3d %-28s caps=%-24s shape=%s\n"
          sig_ n band (if caps = "" then "-" else caps) shape)
      rows

let cmd_caps argv =
  Store.db_path := arg "--db" !Store.db_path argv;
  let entity = arg "--entity" "" argv in
  if entity = "" then
    List.iter (function
        | [ n; env; se; rb ] ->
            Printf.printf "%-14s envelope=%-24s side_effecting=%s requires_booking=%s\n" n env se rb
        | _ -> ())
      (Store.query "SELECT name, envelope, side_effecting, requires_booking FROM capability ORDER BY name")
  else
    List.iter (fun (n, s) -> Printf.printf "%-14s scope=%s\n" n s)
      (Store.claims ~entity)

(* ------------------------------------------------------------------ memory *)
(* The AI's notebook. introspect.ml is the ONLY module that may read or write
 * this space, and the CLI door is the harness handing the AI that access --
 * which is precisely the "no CLI door; the AI cannot reach it" gap STATUS.md
 * names. The round-trip to the store is Persist.load_introspect / save_introspect;
 * nothing here re-implements the encoding (store.ml's `-separator '|'` is the
 * reason entries must avoid embedded newlines and pipes -- see persist.ml).
 *
 * TOKEN DISCIPLINE, HONESTLY. A write needs a token, and only a read mints one.
 * So `add`/`forget`/`rewrite` here begin by reading (Introspect.all), which is
 * the "to write you must read" rule being obeyed rather than bypassed: the CLI
 * does not manufacture a token out of thin air. `list`/`read` use `peek`, which
 * earns nothing, because looking is not writing. *)

let require_introspect_table () =
  match Store.query "SELECT name FROM sqlite_master WHERE type='table' AND name='introspect_entry'" with
  | [ [ _ ] ] -> ()
  | _ ->
      Printf.eprintf
        "store %s has no introspect_entry table -- load sql/persist.sql:\\n\
         \\  sqlite3 %s \".read sql/schema.sql\" \".read sql/persist.sql\"\n"
        !Store.db_path !Store.db_path;
      exit 3

let fmt_entry (e : Introspect.entry) =
  Printf.sprintf "%d  at=%.3f  tags=[%s]  links=[%s]  %s"
    e.Introspect.id e.Introspect.at
    (String.concat "," e.Introspect.tags)
    (String.concat "," (List.map string_of_int e.Introspect.links))
    e.Introspect.text

(* The first non-flag argument. Flags in this door all take exactly one value
   (--db PATH, --text S, --tag a,b, --link 1,2), so a bare token that is not a
   known flag name and is not immediately after one is the positional operand.
   This is separate from `arg` above because `arg` only finds named flags; here
   the id is positional and flags may legally appear before or after it. *)
let first_pos idx argv =
  let flags = [ "--db"; "--text"; "--tag"; "--link" ] in
  let is_flag = fun x -> List.mem x flags in
  let rec go = function
    | [] -> None
    | a :: rest when is_flag a ->
        (* skip the flag AND its value *)
        (match rest with _ :: tl -> go tl | [] -> None)
    | a :: rest when a <> "" && a.[0] <> '-' ->
        if idx = 0 then Some a else go rest
    | _ :: rest -> go rest
  in
  go argv

(* argv[0] is the subcommand ("read"/"forget"/"rewrite"); the id is the first
   non-flag token after it. Drop argv[0] so the subcommand is never taken as id. *)
let int_id argv =
  match argv with
  | _ :: rest ->
      (match first_pos 0 rest with
       | None -> None
       | Some s -> int_of_string_opt s)
  | [] -> None

let cmd_introspect argv =
  Store.db_path := arg "--db" !Store.db_path argv;
  require_introspect_table ();
  let sub = match argv with s :: _ when s <> "" && s.[0] <> '-' -> s | _ -> usage () in
  let notebook = Persist.load_introspect () in
  let persist_then ok_msg code =
    (* Save back so the entry survives this process. `save_introspect` runs
       through Store and can itself fail; report rather than exit cleanly
       pretending a memory was kept. *)
    match (try Ok (Persist.save_introspect notebook) with exn -> Error (Printexc.to_string exn)) with
    | Error msg -> Printf.eprintf "WARN could not persist notebook: %s\n" msg; exit 3
    | Ok () -> (if ok_msg <> "" then Printf.printf "%s\n" ok_msg); exit code
  in
  match sub with
  | "list" ->
      let entries = Introspect.peek notebook in
      if entries = [] then print_string "(notebook is empty)\n"
      else
        List.iter (fun e -> print_string (fmt_entry e ^ "\n")) entries;
      exit 0
  | "read" ->
      (match int_id argv with
       | None -> Printf.eprintf "introspect read needs a numeric id\n"; exit 2
       | Some id ->
           (match Introspect.peek_one notebook id with
            | None -> Printf.eprintf "no entry %d\n" id; exit 3
            | Some e -> print_string (fmt_entry e ^ "\n"); exit 0))
  | "add" ->
      let text = arg "--text" "" argv in
      if text = "" then begin prerr_string "introspect add needs --text\n"; exit 2 end;
      let tags =
        String.split_on_char ',' (arg "--tag" "" argv)
        |> List.map String.trim |> List.filter (fun x -> x <> "")
      in
      let links =
        String.split_on_char ',' (arg "--link" "" argv)
        |> List.filter_map int_of_string_opt
      in
      (* The read that mints the token -- see the discipline comment. *)
      let _, tok = Introspect.all notebook in
      (match Introspect.write notebook tok ~tags ~links ~now:(Unix.time ()) text with
       | Error Introspect.Stale_token ->
           Printf.eprintf "WARN write refused: stale token (unexpected here)\n"; exit 3
       | Error Introspect.Token_spent ->
           Printf.eprintf "WARN write refused: token already spent\n"; exit 3
       | Ok e -> persist_then (Printf.sprintf "wrote entry %d" e.Introspect.id) 0)
  | "forget" ->
      (match int_id argv with
       | None -> Printf.eprintf "introspect forget needs a numeric id\n"; exit 2
       | Some id ->
           let _, tok = Introspect.all notebook in
           (match Introspect.forget notebook tok ~id with
            | Error _ -> Printf.eprintf "WARN forget refused (bad token or unknown id %d)\n" id; exit 3
            | Ok () -> persist_then (Printf.sprintf "forgot entry %d" id) 0))
  | "rewrite" ->
      (match int_id argv with
       | None -> Printf.eprintf "introspect rewrite needs a numeric id\n"; exit 2
       | Some id ->
           let text = arg "--text" "" argv in
           if text = "" then begin prerr_string "introspect rewrite needs --text\n"; exit 2 end;
           let tags =
             String.split_on_char ',' (arg "--tag" "" argv)
             |> List.map String.trim |> List.filter (fun x -> x <> "")
           in
           let links =
             String.split_on_char ',' (arg "--link" "" argv)
             |> List.filter_map int_of_string_opt
           in
           let _, tok = Introspect.all notebook in
           (match Introspect.rewrite notebook tok ~id ~tags ~links ~now:(Unix.time ()) text with
            | Error _ -> Printf.eprintf "WARN rewrite refused (bad token or unknown id %d)\n" id; exit 3
            | Ok () -> persist_then (Printf.sprintf "rewrote entry %d" id) 0))
  | _ -> usage ()

let cmd_doctor argv =
  Store.db_path := arg "--db" !Store.db_path argv;
  Printf.printf "openat2 + RESOLVE_BENEATH : %s\n"
    (if Caps.have_openat2 () then "available" else "MISSING - capability roots are not enforced");
  Printf.printf "sqlite3 CLI               : %s\n"
    (if Sys.command "sqlite3 -version > /dev/null 2>&1" = 0 then "found" else "MISSING");
  Printf.printf "store                     : %s\n" !Store.db_path;
  Printf.printf "persist (introspect)       : %s\n"
    (match Store.query "SELECT name FROM sqlite_master WHERE type='table' AND name='introspect_entry'" with
     | [ [ _ ] ] -> "wired"
     | _ -> "unwired (load sql/persist.sql)")

let () =
  match Array.to_list Sys.argv with
  | _ :: "propose" :: rest -> cmd_propose rest
  | _ :: "run" :: rest -> cmd_run rest
  | _ :: "review" :: rest -> cmd_review rest
  | _ :: "forms" :: rest -> cmd_forms rest
  | _ :: "caps" :: rest -> cmd_caps rest
  | _ :: "introspect" :: rest -> cmd_introspect rest
  | _ :: "doctor" :: rest -> cmd_doctor rest
  | _ -> usage ()
