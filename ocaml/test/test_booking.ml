(* The booking path, tested as a path: Conditions -> Terms -> Kit -> Actor.
 *
 * Most of these are properties of ORDERING, which is the part that cannot be
 * read off the types. `book` returning the right answer is not enough -- it has
 * to return it without having spent anything on the way to a refusal, and it
 * has to narrow rather than copy on the way to a booking. *)

open Gigwerk

let pass = ref 0 and fail = ref 0

let check name b =
  if b then (incr pass; Printf.printf "  ok   %s\n" name)
  else (incr fail; Printf.printf "  FAIL %s\n" name)

let is_err f = function Error e -> f e | Ok _ -> false

(* --------------------------------------------------------------- fixtures *)

let now = 1000L
let env_expiry = 1100L   (* 100s of wall clock = 100_000ms *)

let envelope_of ?(budget = 5) ?(expires_at = env_expiry) actions =
  Terms.issue ~id:"env"
    ~grants:(Grants.make ~entity:"e" ~snapshot:"s" ~actions)
    ~budget ~expires_at

let req ?(entity = "e") ?(evidence = Conditions.clean) ?(cap_set = [ "fs_read" ])
    ?(policy_set = [ "bookable" ]) ?(state_shape = "verdict_log")
    ?(widen_epoch = 0) ?(envelope = envelope_of [ Grants.Read; Grants.Query ])
    ?(kit = Kit.critic) () =
  { Booking.entity; evidence; cap_set; policy_set; state_shape; widen_epoch;
    envelope; kit }

let () =
  print_string "\nordering: conditions run before anything is spent\n";

  (* The reason Conditions is first: if terms were debited before the composition
     was checked, a malformed proposal would cost exactly as much as a real one,
     and a composer in a loop could drain an envelope with proposals that were
     never going to book.
     
     Testing this by "the envelope was not debited" does not work and the failed
     attempt is worth recording: Terms is immutable, so the caller's value can
     never change and the assertion cannot fail. It was a test that looked like
     it proved the ordering and proved nothing. What IS falsifiable is
     PRECEDENCE -- construct a request that fails at two stages at once and check
     which stage reports it. *)
  let dead_env = envelope_of ~budget:0 [ Grants.Read; Grants.Query ] in
  let refusing = { Conditions.clean with Conditions.grants_narrow = false } in
  check "structurally refused AND a dead envelope -> conditions reports it"
    (match Booking.book ~now (req ~evidence:refusing ~envelope:dead_env ()) with
     | Error (Booking.Refused _) -> true | _ -> false);
  check "structurally refused AND a kit that cannot fit -> conditions reports it"
    (match
       Booking.book ~now
         (req ~evidence:refusing ~envelope:(envelope_of []) ())
     with
     | Error (Booking.Refused _) -> true | _ -> false);
  check "QUEUED and a dead envelope -> the human is still the one asked"
    (let queueing =
       { Conditions.clean with Conditions.requires_human = true;
                               human_verdict = false } in
     match Booking.book ~now (req ~evidence:queueing ~envelope:dead_env ()) with
     | Error (Booking.Queued _) -> true | _ -> false);
  check "a dead envelope AND a kit that cannot fit -> the envelope reports it"
    (* Terms before Kit, in the order the user named. *)
    (match
       Booking.book ~now
         (req ~envelope:(envelope_of ~budget:0 []) ~kit:Kit.critic ())
     with
     | Error (Booking.Envelope_dead _) -> true | _ -> false);

  let env = envelope_of [ Grants.Read; Grants.Query ] in
  check "a booking debits the envelope, exactly once"
    (match Booking.book ~now (req ~envelope:env ()) with
     | Ok b -> Terms.consumed b.Booking.envelope = 1
     | Error _ -> false);
  check "the debit has to be THREADED -- booking from the returned envelope stacks"
    (* The falsifiable form of "the caller's copy is untouched": a caller that
       forgets to carry the returned envelope forward gets an envelope that never
       runs down, which is the same as having no across-gig bound at all. *)
    (match Booking.book ~now (req ~envelope:env ()) with
     | Error _ -> false
     | Ok b1 -> (
         match Booking.book ~now (req ~envelope:b1.Booking.envelope ()) with
         | Ok b2 -> Terms.consumed b2.Booking.envelope = 2
         | Error _ -> false));
  check "and it runs the envelope down to nothing after its budget of bookings"
    (let rec drain e n =
       match Booking.book ~now (req ~envelope:e ()) with
       | Ok b -> drain b.Booking.envelope (n + 1)
       | Error (Booking.Envelope_dead (Terms.Exhausted _)) -> n
       | Error _ -> -1
     in
     drain (envelope_of ~budget:3 [ Grants.Read; Grants.Query ]) 0 = 3);

  print_string "\nthe envelope is checked as an envelope\n";

  check "an envelope granting retrieve is refused before any kit is consulted"
    (is_err
       (function
         | Booking.Envelope_carries_composer_grant Grants.Retrieve -> true
         | _ -> false)
       (Booking.book ~now
          (req ~envelope:(envelope_of [ Grants.Read; Grants.Retrieve ]) ())));
  check "...and that beats the kit-fit check, which would also have failed"
    (* echo needs nothing, so it fits any envelope. The refusal must still fire,
       which proves the check is on the envelope and not on the pairing. *)
    (is_err
       (function Booking.Envelope_carries_composer_grant _ -> true | _ -> false)
       (Booking.book ~now
          (req ~kit:Kit.echo ~envelope:(envelope_of [ Grants.Retrieve ]) ())));
  check "an expired envelope reports Expired, not a budget figure"
    (is_err
       (function
         | Booking.Envelope_dead (Terms.Expired _) -> true | _ -> false)
       (Booking.book ~now:2000L (req ())));
  check "an exhausted envelope reports Exhausted"
    (is_err
       (function
         | Booking.Envelope_dead (Terms.Exhausted { budget = 0 }) -> true
         | _ -> false)
       (Booking.book ~now
          (req ~envelope:(envelope_of ~budget:0 [ Grants.Read; Grants.Query ]) ())));

  print_string "\nthe kit must FIT the envelope, not define it\n";

  check "a kit needing actions the envelope lacks is refused"
    (is_err
       (function
         | Booking.Kit_exceeds_envelope [ Grants.Read; Grants.Query ] -> true
         | _ -> false)
       (Booking.book ~now (req ~envelope:(envelope_of []) ())));
  check "the excess names ONLY the missing actions"
    (is_err
       (function
         | Booking.Kit_exceeds_envelope [ Grants.Query ] -> true | _ -> false)
       (Booking.book ~now (req ~envelope:(envelope_of [ Grants.Read ]) ())));
  check "a kit needing nothing fits an empty envelope"
    (match Booking.book ~now (req ~kit:Kit.echo ~envelope:(envelope_of []) ()) with
     | Ok _ -> true | Error _ -> false);
  check "an invalid kit is refused with the KIT layer's own reason"
    (is_err
       (function
         | Booking.Kit_rejected (Kit.Composer_only Grants.Retrieve) -> true
         | _ -> false)
       (Booking.book ~now
          (* NOT an envelope carrying Retrieve: that check fires first and
             correctly, which would make this test prove the wrong thing. *)
          (req ~kit:Kit.bad_researcher ~envelope:(envelope_of [ Grants.Read ]) ())));

  (* Kit.t has no signature hiding its fields, so an `Ok` can carry a record
     that never passed through Kit.make. Trusting a constructor that was not
     necessarily used is precisely how a composer-only grant gets in. *)
  let forged =
    Ok { Kit.name = "forged"; purpose = "smuggle retrieval";
         grants = [ Grants.Read; Grants.Retrieve ];
         state_shape = "notes"; ladder = Phases.critic_ladder;
         budget_ms = 1000; budget_actions = 2 }
  in
  check "a FORGED kit record is caught by re-validation at booking"
    (is_err
       (function Booking.Kit_rejected (Kit.Composer_only _) -> true | _ -> false)
       (Booking.book ~now (req ~kit:forged ~envelope:(envelope_of [ Grants.Read ]) ())));
  check "a kit with grants and no action allowance cannot be made at all"
    (match
       Kit.make ~name:"starved" ~purpose:"act with no allowance"
         ~grants:[ Grants.Read ] ~state_shape:"unit"
         ~ladder:Phases.critic_ladder ~budget_ms:100 ~budget_actions:0
     with
     | Error (Kit.Cannot_act _) -> true | _ -> false);

  print_string "\nbooked to match: narrowing, not copying\n";

  (* The single most important line in booking.ml. If gig_terms copied the
     envelope's grants, an actor would hold whatever the human happened to
     authorise rather than what its kit needs -- and every claim about least
     authority in this design would be decoration. *)
  let wide = envelope_of [ Grants.Read; Grants.Query; Grants.Write; Grants.Spawn ] in
  check "the actor's grants are the KIT's, not the envelope's"
    (match Booking.book ~now (req ~envelope:wide ()) with
     | Ok b ->
         let g = Terms.grants b.Booking.gig_terms in
         Grants.allows g Grants.Read && Grants.allows g Grants.Query
         && not (Grants.allows g Grants.Write)
         && not (Grants.allows g Grants.Spawn)
     | Error _ -> false);
  check "the actor's terms cannot outlive the envelope"
    (match Booking.book ~now (req ~envelope:wide ()) with
     | Ok b ->
         Terms.expires_at b.Booking.gig_terms = Terms.expires_at wide
     | Error _ -> false);
  check "the actor's action allowance is the kit's declared number, verbatim"
    (match Booking.book ~now (req ~envelope:wide ()) with
     | Ok b -> Terms.budget b.Booking.gig_terms = 2   (* Kit.critic declares 2 *)
     | Error _ -> false);
  check "a kit with no grants gets a budget of 0, not a flattering 1"
    (* Dead terms are the CORRECT terms for an actor with no permitted action.
       An earlier `max 1` here printed budget=1 for a kit that declared 0. *)
    (match Booking.book ~now (req ~kit:Kit.echo ~envelope:(envelope_of []) ()) with
     | Ok b -> Terms.budget b.Booking.gig_terms = 0
     | Error _ -> false);
  check "the actor's terms snapshot is the form sig, so grants are traceable"
    (match Booking.book ~now (req ~envelope:wide ()) with
     | Ok b ->
         Grants.snapshot (Terms.grants b.Booking.gig_terms) = b.Booking.form_sig
     | Error _ -> false);

  print_string "\nbooked to match: the tighter wall clock wins\n";

  check "kit tighter than terms -> kit"
    (* critic asks 5000ms; the envelope leaves 100_000ms *)
    (match Booking.book ~now (req ()) with
     | Ok b -> b.Booking.wall_ms = 5000 | Error _ -> false);
  check "terms tighter than kit -> terms"
    (match
       Booking.book ~now
         (req ~envelope:(envelope_of ~expires_at:1002L [ Grants.Read; Grants.Query ]) ())
     with
     | Ok b -> b.Booking.wall_ms = 2000 | Error _ -> false);
  (* No_wall_left is reachable only from the KIT side today, and that is worth
     knowing rather than assuming: Terms is second-granular and `live` already
     refuses when now >= expires_at, so the terms side of the min is always at
     least 1000ms by the time it is computed. A kit asking for zero time is the
     one way to reach zero, and booking is the right place to refuse it because
     the wall clock is a property of the PAIRING, not of either side alone. *)
  let no_time =
    Kit.make ~name:"instant" ~purpose:"ask for no time at all" ~grants:[]
      ~state_shape:"unit" ~ladder:Phases.echo_ladder ~budget_ms:0
      ~budget_actions:0
  in
  check "a kit asking for zero wall clock is refused at booking"
    (is_err
       (function Booking.No_wall_left { kit_ms = 0; _ } -> true | _ -> false)
       (Booking.book ~now (req ~kit:no_time ~envelope:(envelope_of []) ())));
  check "...and the refusal reports what each side offered"
    (is_err
       (function
         | Booking.No_wall_left { kit_ms = 0; terms_ms = 100_000 } -> true
         | _ -> false)
       (Booking.book ~now (req ~kit:no_time ~envelope:(envelope_of []) ())));

  print_string "\nform identity\n";

  let sig_ = Booking.form_sig in
  check "claim order does not change identity"
    (sig_ ~cap_set:[ "a"; "b" ] ~policy_set:[ "p" ] ~state_shape:"s" ~widen_epoch:0
     = sig_ ~cap_set:[ "b"; "a" ] ~policy_set:[ "p" ] ~state_shape:"s" ~widen_epoch:0);
  check "policy order does not change identity"
    (sig_ ~cap_set:[ "a" ] ~policy_set:[ "p"; "q" ] ~state_shape:"s" ~widen_epoch:0
     = sig_ ~cap_set:[ "a" ] ~policy_set:[ "q"; "p" ] ~state_shape:"s" ~widen_epoch:0);
  check "a widen_epoch bump IS a different form -- the cold-start escape hatch"
    (sig_ ~cap_set:[ "a" ] ~policy_set:[ "p" ] ~state_shape:"s" ~widen_epoch:0
     <> sig_ ~cap_set:[ "a" ] ~policy_set:[ "p" ] ~state_shape:"s" ~widen_epoch:1);
  check "a different state shape is a different form"
    (sig_ ~cap_set:[ "a" ] ~policy_set:[ "p" ] ~state_shape:"s" ~widen_epoch:0
     <> sig_ ~cap_set:[ "a" ] ~policy_set:[ "p" ] ~state_shape:"t" ~widen_epoch:0);
  check "an added capability is a different form"
    (sig_ ~cap_set:[ "a" ] ~policy_set:[ "p" ] ~state_shape:"s" ~widen_epoch:0
     <> sig_ ~cap_set:[ "a"; "b" ] ~policy_set:[ "p" ] ~state_shape:"s" ~widen_epoch:0);
  check "a delimiter in a name cannot forge a second element"
    (* ["a,b"] and ["a";"b"] must not collide, or one capability whose name
       contains the delimiter silently becomes two -- two different shapes then
       share one confidence record and nothing reports it. *)
    (sig_ ~cap_set:[ "a,b" ] ~policy_set:[] ~state_shape:"s" ~widen_epoch:0
     <> sig_ ~cap_set:[ "a"; "b" ] ~policy_set:[] ~state_shape:"s" ~widen_epoch:0);
  check "...nor across two elements of the same field at equal count"
    (* The count prefix alone does not catch this: ["a,b";"c"] and ["a";"b,c"]
       are both two elements and both render "a,b,c" when joined. Only the
       per-element LENGTH prefix separates them. Found by mutation -- dropping
       the length prefix left every other identity test green. *)
    (sig_ ~cap_set:[ "a,b"; "c" ] ~policy_set:[] ~state_shape:"s" ~widen_epoch:0
     <> sig_ ~cap_set:[ "a"; "b,c" ] ~policy_set:[] ~state_shape:"s" ~widen_epoch:0);
  check "...and a field boundary cannot be forged either"
    (sig_ ~cap_set:[ "a" ] ~policy_set:[ "b" ] ~state_shape:"s" ~widen_epoch:0
     <> sig_ ~cap_set:[ "a"; "b" ] ~policy_set:[] ~state_shape:"s" ~widen_epoch:0);

  print_string "\nwhat a verdict is a fact ABOUT\n";

  (* The regression test for a bug the wiring found: refusing a proposal because
     the envelope was too narrow wrote a 'refuse' row against the FORM, and the
     form -- whose identity deliberately ignores envelopes -- could then never
     book again. A transient refusal killed a shape permanently. *)
  let att r = Booking.attaches_to r in
  check "a structural refusal attaches to the COMPOSITION"
    (is_err (fun r -> att r = "composition")
       (Booking.book ~now (req ~evidence:refusing ())));
  check "an ENVELOPE-shaped refusal attaches to the proposal, not the shape"
    (is_err (fun r -> att r = "proposal")
       (Booking.book ~now (req ~envelope:(envelope_of []) ())));
  check "an expired envelope attaches to the proposal"
    (is_err (fun r -> att r = "proposal") (Booking.book ~now:2000L (req ())));
  check "a skeptical judge attaches to the PROPOSAL -- one judge cannot kill a shape"
    (is_err (fun r -> att r = "proposal")
       (Booking.book ~now
          (req ~evidence:{ Conditions.clean with Conditions.support_strength = 2;
                                                 refutation_strength = 2 } ())));
  check "a queue attaches to the proposal -- being ASKED is not evidence"
    (is_err (fun r -> att r = "proposal")
       (Booking.book ~now
          (req ~evidence:{ Conditions.clean with Conditions.requires_human = true;
                                                 human_verdict = false } ())));
  check "a broken kit attaches to the KIT"
    (is_err (fun r -> att r = "kit")
       (Booking.book ~now
          (req ~kit:Kit.bad_researcher ~envelope:(envelope_of [ Grants.Read ]) ())));
  check "conditions itself distinguishes the two Refuse reasons"
    (let structural =
       Conditions.evaluate { Conditions.clean with Conditions.single_writer = false } in
     let adversarial =
       Conditions.evaluate { Conditions.clean with Conditions.support_strength = 1;
                                                   refutation_strength = 1 } in
     structural.Conditions.verdict = Conditions.Refuse
     && adversarial.Conditions.verdict = Conditions.Refuse
     && structural.Conditions.attaches_to = Conditions.Composition
     && adversarial.Conditions.attaches_to = Conditions.Proposal);

  print_string "\nphases cross the fork; the PARENT decides what counts\n";

  let booked =
    match Booking.book ~now (req ~kit:Kit.echo ~envelope:(envelope_of []) ()) with
    | Ok b -> b
    | Error _ -> failwith "echo must book"
  in
  let run_emitting s = Booking.run booked ~work:(fun _ -> s) in

  check "the terminal phase settles, and matched is yes"
    (let c = run_emitting (Booking.emit ~phase:(Some "echoed") "payload") in
     c.Booking.settled && Booking.matched c = "yes"
     && c.Booking.payload = "payload");
  check "a non-terminal phase is partial credit, not a pass"
    (let c = run_emitting (Booking.emit ~phase:(Some "received") "half") in
     (not c.Booking.settled) && Booking.matched c = "partial");
  check "NO phase is not partial -- it produced nothing"
    (let c = run_emitting (Booking.emit ~phase:None "silent") in
     Booking.matched c = "no" && Phases.emissions c.Booking.progress = 0);
  check "an UNDECLARED phase is a breach, and a breach is never partial credit"
    (* The child chooses what to say; the parent chooses what counts. A behavior
       that can name any string could name the terminal one. *)
    (let c = run_emitting (Booking.emit ~phase:(Some "done") "forged") in
     (match c.Booking.breach with
      | Some (Phases.Undeclared "done") -> true | _ -> false)
     && Booking.matched c = "no");
  check "a breach records NO progress -- the invariant `matched` leans on"
    (* If this ever goes red, the redundant breach arm in `matched` has become
       load-bearing rather than defensive. That is the point of pinning it. *)
    (let c = run_emitting (Booking.emit ~phase:(Some "done") "forged") in
     Phases.emissions c.Booking.progress = 0 && c.Booking.breach <> None);
  check "a phase from ANOTHER kit's ladder is undeclared here"
    (let c = run_emitting (Booking.emit ~phase:(Some "verdict_emitted") "x") in
     c.Booking.breach <> None && Booking.matched c = "no");
  check "a crash is not a breach -- it is an outcome"
    (let c = Booking.run booked ~work:(fun _ -> failwith "boom") in
     c.Booking.breach = None && Booking.matched c = "no"
     && Booking.outcome_word c = "failed");
  check "the wall clock kills a runaway and matched is no"
    (let slow =
       match Booking.book ~now
               (req ~kit:Kit.echo ~envelope:(envelope_of ~expires_at:1002L []) ())
       with Ok b -> b | Error _ -> failwith "must book" in
     let c = Booking.run slow ~work:(fun _ -> Unix.sleep 5; "never") in
     Booking.outcome_word c = "budget_exceeded" && Booking.matched c = "no");
  check "a payload containing the separator does not forge a second phase"
    (let raw = Booking.emit ~phase:(Some "echoed") "a\x1fb" in
     let c = run_emitting raw in
     c.Booking.settled && c.Booking.payload = "a\x1fb");
  check "the phase reported is the one the parent observed, not the one claimed"
    (let c = run_emitting (Booking.emit ~phase:(Some "done") "x") in
     Phases.current c.Booking.progress = None);

  print_string "\nscope narrowing is a segment prefix, not a string prefix\n";

  let n = Booking.scope_narrows in
  check "deeper is narrower" (n ~envelope:"/srv/work" ~scope:"/srv/work/in");
  check "equal is narrow enough" (n ~envelope:"/srv/work" ~scope:"/srv/work");
  check "shallower widens" (not (n ~envelope:"/srv/work" ~scope:"/srv"));
  check "a sibling is not beneath" (not (n ~envelope:"/srv/work" ~scope:"/srv/other"));
  check "STRING prefix is not SEGMENT prefix -- /srv/workshop is not beneath /srv/work"
    (not (n ~envelope:"/srv/work" ~scope:"/srv/workshop"));
  check "an empty scope means the envelope itself" (n ~envelope:"/srv/work" ~scope:"");
  check "trailing slashes do not change the answer"
    (n ~envelope:"/srv/work/" ~scope:"/srv/work/in/");

  Printf.printf "\ntotal: %d passed, %d failed\n" !pass !fail;
  if !fail > 0 then exit 1
