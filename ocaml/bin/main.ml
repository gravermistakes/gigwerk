(* gigwerk -- Phase 1: a capability-scoped task runner.
 *
 *   gigwerk run echo   --message "hello"
 *   gigwerk run critic --artifact notes.txt
 *   gigwerk caps
 *   gigwerk doctor
 *
 * There is no gate yet. Compositions are read from the store and constructed;
 * nothing is validated beyond what the schema's foreign keys enforce. That is
 * Phase 2, and until it exists this is a runner, not a harness. *)

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
     gigwerk context [--floor N] [--immediate N] [--working N] [--render] [--db FILE]\n\
     gigwerk caps [--entity NAME]\n\
     gigwerk doctor\n\
   \n\
   propose runs the whole path -- conditions, terms, kit fit, then the gig.\n\
   run skips it and calls the behavior directly; it is the pre-gate runner and\n\
   is kept only so the two can be compared.\n";
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

(* ======================================================================= *)
(* context: assemble the active working memory from the store.               *)
(*                                                                           *)
(* This is the wiring for MEMORY.md's band 2. It calls Context.assemble,     *)
(* which is the first path in the running program to read SARCASM back        *)
(* (Persist.load_store) and the first to invoke the condensing process on    *)
(* live material. Bands default to 64k immediate / 128k working; the human    *)
(* can shrink them to watch material spill and condense.                     *)
(* ======================================================================= *)

let cmd_context argv =
  Store.db_path := arg "--db" !Store.db_path argv;
  let ctx =
    Context.assemble
      ~floor:(int_arg "--floor" 64_000 argv)
      ~immediate_ceiling:(int_arg "--immediate" 64_000 argv)
      ~working_ceiling:(int_arg "--working" 128_000 argv)
      ()
  in
  print_string (Working.context_report ctx);
  print_newline ();
  if List.mem "--render" argv then begin
    print_newline ();
    print_string (Working.render ctx);
    print_newline ()
  end
  else begin
    (* One line per slot: the shape, not the dump. A digest's first line, with
       newlines flattened so a single slot cannot spill across rows. *)
    let preview s =
      let s = String.map (fun c -> if c = '\n' then ' ' else c) s in
      if String.length s <= 64 then s else String.sub s 0 61 ^ "..."
    in
    List.iter
      (fun sl ->
        Printf.printf "  immediate %6d tok        %s\n"
          sl.Working.item.Working.tokens (preview sl.Working.item.Working.text))
      ctx.Working.immediate;
    List.iter
      (fun sl ->
        Printf.printf "  working   %6d tok r=%.2f %s\n"
          sl.Working.item.Working.tokens sl.Working.ratio
          (preview sl.Working.item.Working.text))
      ctx.Working.working
  end

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

let cmd_doctor () =
  Printf.printf "openat2 + RESOLVE_BENEATH : %s\n"
    (if Caps.have_openat2 () then "available" else "MISSING - capability roots are not enforced");
  Printf.printf "sqlite3 CLI               : %s\n"
    (if Sys.command "sqlite3 -version > /dev/null 2>&1" = 0 then "found" else "MISSING");
  Printf.printf "store                     : %s\n" !Store.db_path

let () =
  match Array.to_list Sys.argv with
  | _ :: "propose" :: rest -> cmd_propose rest
  | _ :: "run" :: rest -> cmd_run rest
  | _ :: "review" :: rest -> cmd_review rest
  | _ :: "forms" :: rest -> cmd_forms rest
  | _ :: "context" :: rest -> cmd_context rest
  | _ :: "caps" :: rest -> cmd_caps rest
  | _ :: "doctor" :: _ -> cmd_doctor ()
  | _ -> usage ()
