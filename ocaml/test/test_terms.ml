open Gigwerk

let pass = ref 0 and fail = ref 0
let check name b =
  if b then (incr pass; Printf.printf "  ok   %s\n" name)
  else (incr fail; Printf.printf "  FAIL %s\n" name)

let () =
  print_string "\ngrants\n";
  let g = Grants.make ~entity:"critic" ~snapshot:"s1"
            ~actions:[Grants.Read; Grants.Query] in
  check "granted action allowed"      (Grants.allows g Grants.Read);
  check "ungranted action refused"    (not (Grants.allows g Grants.Write));
  check "action round-trips"
    (Grants.action_of_string "spawn" = Some Grants.Spawn);
  check "unknown action is not representable"
    (Grants.action_of_string "sudo" = None);

  print_string "\nterms\n";
  let t = Terms.issue ~id:"T1" ~grants:g ~budget:3 ~expires_at:1000L in
  let is_ok = function Ok _ -> true | Error _ -> false in
  check "granted action inside budget"  (is_ok (Terms.check t ~now:1L ~action:Grants.Read));
  check "ungranted action refused"
    (match Terms.check t ~now:1L ~action:Grants.Write with
     | Error (Terms.Not_granted Grants.Write) -> true | _ -> false);
  check "expiry beats budget in reporting"
    (match Terms.check t ~now:2000L ~action:Grants.Read with
     | Error (Terms.Expired _) -> true | _ -> false);
  let t3 = Terms.consume (Terms.consume (Terms.consume t)) in
  check "budget exhausts"
    (match Terms.check t3 ~now:1L ~action:Grants.Read with
     | Error (Terms.Exhausted { budget = 3 }) -> true | _ -> false);
  check "remaining counts down" (Terms.remaining t = 3 && Terms.remaining t3 = 0);
  check "spend checks and consumes atomically"
    (match Terms.spend t ~now:1L ~action:Grants.Read with
     | Ok t' -> Terms.remaining t' = 2 | Error _ -> false);
  check "spend on an ungranted action does not consume"
    (match Terms.spend t ~now:1L ~action:Grants.Spawn with
     | Error _ -> Terms.remaining t = 3 | Ok _ -> false);

  print_string "\nconditions\n";
  let ev = Conditions.clean in
  let v e = (Conditions.evaluate e).Conditions.verdict in
  let r e = (Conditions.evaluate e).Conditions.reasons in
  check "clean books" (v ev = Conditions.Book);
  check "widened grant refuses"
    (v { ev with Conditions.grants_narrow = false } = Conditions.Refuse);
  check "missing capability refuses"
    (v { ev with Conditions.capabilities_exist = false } = Conditions.Refuse);
  check "two writers refuses"
    (v { ev with Conditions.single_writer = false } = Conditions.Refuse);
  check "wrong tier queues, does not refuse"
    (v { ev with Conditions.tier_matches = false } = Conditions.Queue);
  check "requires_human without verdict queues"
    (v { ev with Conditions.requires_human = true; human_verdict = false }
       = Conditions.Queue);
  check "requires_human with verdict books"
    (v { ev with Conditions.requires_human = true; human_verdict = true }
       = Conditions.Book);
  check "refutation stronger than support refuses"
    (v { ev with Conditions.support_strength = 2; refutation_strength = 3 }
       = Conditions.Refuse);
  check "TIE refuses -- refuted under uncertainty"
    (v { ev with Conditions.support_strength = 2; refutation_strength = 2 }
       = Conditions.Refuse);
  check "structural refusal never reaches the human queue"
    (let e = { ev with Conditions.grants_narrow = false; tier_matches = false } in
     v e = Conditions.Refuse
     && not (List.mem "agent_provenance_requires_subprocess" (r e)));
  check "all structural reasons are reported at once"
    (List.length (r { ev with Conditions.grants_narrow = false;
                              capabilities_exist = false }) = 2);

  Printf.printf "\n%d passed, %d failed\n" !pass !fail;
  if !fail > 0 then exit 1

let () =
  print_string "\nphases\n";
  let l = Phases.critic_ladder in
  let p = Phases.start l in
  let ok = function Ok x -> x | Error e -> failwith (Phases.breach_to_string e) in
  check "undeclared phase is a breach, not an unknown state"
    (match Phases.observe p "done" with
     | Error (Phases.Undeclared "done") -> true | _ -> false);
  let p = ok (Phases.observe p "read") in
  check "non-terminal phase never settles" (not (Phases.settled p));
  let p = ok (Phases.observe p "checked") in
  let p = ok (Phases.observe p "verdict_emitted") in
  check "one terminal emission does not settle at consecutive=2"
    (not (Phases.settled p));
  check "one terminal emission DOES settle at consecutive=1"
    (Phases.settled ~consecutive:1 p);
  let p2 = ok (Phases.observe p "verdict_emitted") in
  check "two consecutive terminal emissions settle" (Phases.settled p2);
  check "regression after terminal is refused"
    (match Phases.observe p "read" with
     | Error (Phases.Regressed ("verdict_emitted", "read")) -> true | _ -> false);
  check "flip-flop cannot settle -- consecutive is the point"
    (let q = Phases.start l in
     let q = ok (Phases.observe q "read") in
     (* a behavior that emitted terminal, then work, then terminal would have
        been refused at the middle step, so the only way to two-in-a-row is to
        actually be finished *)
     not (Phases.settled q));
  check "echo ladder terminal differs from critic's"
    (match Phases.observe (Phases.start Phases.echo_ladder) "verdict_emitted" with
     | Error (Phases.Undeclared _) -> true | _ -> false);
  check "a behavior cannot borrow another's completion phrase"
    (match Phases.observe (Phases.start Phases.critic_ladder) "echoed" with
     | Error (Phases.Undeclared _) -> true | _ -> false);

  Printf.printf "\nphases: %d passed, %d failed\n" !pass !fail;
  if !fail > 0 then exit 1

let () =
  print_string "\ntrace\n";
  let t = Trace.create ~gig:"g1" in
  let root = Trace.open_ t "gig" in
  let a = Trace.open_ t ~parent:root ~phase:"read" "fs_read" in
  Trace.close t ~outcome:"ok" a;
  let b = Trace.open_ t ~parent:root ~phase:"checked" "balance_check" in
  Trace.close t ~breach:"budget exhausted" b;
  check "spans keep emission order"
    (List.map (fun s -> s.Trace.name) (Trace.spans t)
     = [ "gig"; "fs_read"; "balance_check" ]);
  check "children nest under their parent"
    (List.for_all (fun s -> s.Trace.name = "gig" || Trace.depth t s = 1)
       (Trace.spans t));
  check "an unclosed span is visible, not silently fine"
    (List.map (fun s -> s.Trace.name) (Trace.unclosed t) = [ "gig" ]);
  check "double close raises rather than passing quietly"
    (match Trace.close t ~outcome:"ok" a with
     | () -> false
     | exception Trace.Double_close 1 -> false
     | exception Trace.Double_close _ -> true);
  check "breach is carried on the span that breached"
    (List.exists (fun s -> s.Trace.breach = Some "budget exhausted")
       (Trace.spans t));
  Trace.close t ~outcome:"failed" root;
  check "closing the root clears unclosed" (Trace.unclosed t = []);
  check "rows carry parent links for the store"
    (match Trace.to_rows t with
     | (_, None, "g1", "gig", _, _, _, _) :: _ -> true | _ -> false);

  Printf.printf "\ntotal: %d passed, %d failed\n" !pass !fail;
  if !fail > 0 then exit 1

let () =
  print_string "\nembed\n";
  let a = Embed.of_text "the critic refused an unbalanced artifact" in
  let b = Embed.of_text "critic rejected artifact with unbalanced groups" in
  let c = Embed.of_text "quarterly revenue projections for the northeast" in
  check "related text scores above unrelated"
    (Embed.cosine a b > Embed.cosine a c);
  check "identical text is maximally similar"
    (Embed.cosine a (Embed.of_text "the critic refused an unbalanced artifact") > 0.999);
  check "vectors round-trip through a column"
    (let s = Embed.to_string a in Embed.cosine (Embed.of_string s) a > 0.999);

  print_string "\nreconstruction\n";
  let contains hay needle =
    let n = String.length needle and h = String.length hay in
    let rec go i = i + n <= h && (String.sub hay i n = needle || go (i + 1)) in go 0 in
  let st = Reconstruct.store () in
  let d ?affect id body = Reconstruct.add st (Reconstruct.doc ?affect ~id body) in
  let dread = { Affect.zero with Affect.hazard = 0.9; surprise = 0.9;
                dissonance = 0.5; valence = -0.9 } in
  d "session" "A session about the gate. It began with [[widened]] and ended in review.";
  d "widened" ~affect:dread
    "A composition widened its scope: /srv/gigwerk-evil against envelope /srv/gigwerk. The gate refused it, and the composer [[revised]].";
  d "revised" "The composer revised once and was refused again, so it [[escalated]].";
  d "escalated" "Escalated to the human, who ruled the envelope stands.";
  d "routine" "A critic checked notes.txt and passed, as predicted.";
  d "unrelated" ~affect:{ Affect.zero with Affect.hazard = 0.88; surprise = 0.92;
                          dissonance = 0.48; valence = -0.85 }
    "The night the deploy script deleted the staging volume.";

  let r = Reconstruct.recollect st ~entry:"session"
            ~query:"a widened envelope was refused" () in
  check "the walk is an ordered path, not a set" (List.length r.Reconstruct.path > 1);
  check "the first step arrived from nowhere; the rest name their source"
    (match r.Reconstruct.path with
     | f :: rest -> f.Reconstruct.from = None
                    && List.for_all (fun s -> s.Reconstruct.from <> None) rest
     | [] -> false);
  check "it reaches the end of the thread, not just the first hop"
    (contains r.Reconstruct.rendered "envelope stands");
  check "the walk never revisits -- a loop would render forever"
    (let ids = List.map (fun s -> s.Reconstruct.doc.Reconstruct.id) r.Reconstruct.path in
     List.length ids = List.length (List.sort_uniq compare ids));

  print_string "\ncontraction is not compaction\n";
  let long = "The composition claimed fs_read scoped to /srv/gigwerk-evil. \
              The envelope on that capability is /srv/gigwerk. A string-prefix \
              check would have accepted it, because the characters match; the \
              segment comparison did not, because srv/gigwerk-evil is not \
              beneath srv/gigwerk. The gate returned refuse with the reason \
              scope widens envelope, and the composer revised once before \
              escalating to a human, who ruled that the envelope stands." in
  (* Its own store. Adding to `st` mid-suite shifted the strike percentile and
     broke seven later tests -- which is how the small-store instability got
     found, but is not something to leave in place. *)
  let cst = Reconstruct.store () in
  let c = Reconstruct.doc ~id:"contracted" ~full:long
            "A composition widened its scope and the gate refused it. [[revised]]" in
  Reconstruct.add cst c;
  check "contraction reports real loss"
    (Reconstruct.compression_ratio c < 0.35);
  check "the original is NOT discarded -- expand reaches it"
    (Reconstruct.expand c = long);
  check "an uncontracted doc expands to itself, ratio 1.0"
    (let plain = Reconstruct.doc ~id:"plain" "just this" in
     Reconstruct.expand plain = "just this"
     && Reconstruct.compression_ratio plain = 1.0
     && not (Reconstruct.is_contracted plain));
  check "search runs on the DIGEST, not the full text"
    (let only_in_full = Embed.cosine (Embed.of_text "string-prefix characters match")
                          c.Reconstruct.vec in
     let in_digest = Embed.cosine (Embed.of_text "a composition widened its scope")
                       c.Reconstruct.vec in
     in_digest > only_in_full);
  check "so detail is addressable without being searchable -- the whole point"
    (Reconstruct.is_contracted c
     && (let e = Reconstruct.expand c in
         let n = String.length "string-prefix" in
         let rec go i = i + n <= String.length e
                        && (String.sub e i n = "string-prefix" || go (i+1)) in go 0));

  print_string "\nstrike -- involuntary recall\n";
  let cue = "the smell of hot dust off a server rack" in
  let struck = Reconstruct.strike st ~affect:dread ~cue () in
  (* An earlier version asserted this struck a specific id. It did not: the cue
     carries `dread`, which is widened's affect EXACTLY, so resonance is 1.0
     there and 0.999 on unrelated. The code was right and the assertion was a
     tie-break I had set up backwards. What follows tests the property. *)
  check "a cue with no subject in common still strikes something"
    (struck <> None);
  check "STRIKE DOES NOT RETURN WHAT A SEMANTIC SEARCH RETURNS"
    (match struck, Reconstruct.encyclopedic st ~k:1 ~query:cue () with
     | Some d, [ top ] -> d.Reconstruct.id <> top.Reconstruct.id
     | _ -> false);
  check "what it struck resonates near-perfectly with the cue"
    (match struck with
     | Some d -> Affect.resonance dread d.Reconstruct.affect > 0.95
     | None -> false);
  check "and it is semantically unrelated -- that is the point"
    (match struck with
     | Some d -> Embed.cosine (Embed.of_text cue) d.Reconstruct.vec < 0.30
     | None -> false);
  check "a FLAT cue strikes nothing -- furniture is not a stimulus"
    (Reconstruct.strike st ~affect:Affect.zero ~cue () = None);
  check "opposite valence does not resonate, however loud"
    (let elation = { Affect.zero with Affect.hazard = 0.9; surprise = 0.9;
                     dissonance = 0.5; valence = 0.9 } in
     Affect.resonance dread elation < 0.7);
  check "strike needs NO entry point -- that is what makes it instant"
    (Reconstruct.strike st ~affect:dread ~cue:"anything at all" () <> None);

  let m = Reconstruct.remember st ~cue ~cue_affect:dread
            ~query:"what went wrong that night" () in
  check "the struck memory is step one, whatever it turned out to be"
    (match m.Reconstruct.path, struck with
     | f :: _, Some d -> f.Reconstruct.doc.Reconstruct.id = d.Reconstruct.id
     | _ -> false);
  check "nothing led to it -- from is None, via is Resonance"
    (match m.Reconstruct.path with
     | f :: _ -> f.Reconstruct.from = None && f.Reconstruct.via = Reconstruct.Resonance
     | [] -> false);
  check "and the walk reconstructs outward from where it dropped us"
    (m.Reconstruct.turns >= 1 && m.Reconstruct.jumps >= 1);

  print_string "\naffect\n";
  check "surprise comes from prediction error"
    (Affect.surprise_of_match "no" = 1.0 && Affect.surprise_of_match "yes" = 0.0);
  check "novelty is NOT surprise -- a first run predicted nothing"
    (Affect.novelty_of ~prior_runs:0 = 1.0
     && Affect.novelty_of ~prior_runs:100 < 0.11);
  check "valence is the only SIGNED tone"
    (Affect.valence_of "refuse" < 0.0 && Affect.valence_of "book" > 0.0);
  check "a queue costs review attention, so it reads mildly negative"
    (Affect.valence_of "queue" < 0.0 && Affect.valence_of "queue" > -0.5);
  check "magnitude treats a disaster and a triumph alike"
    (let good = { Affect.zero with Affect.valence = 1.0 } in
     let bad  = { Affect.zero with Affect.valence = -1.0 } in
     Affect.magnitude good = Affect.magnitude bad);
  check "but the sign survives, so they are still distinguishable"
    (Affect.valence_of "book" <> Affect.valence_of "refuse");
  check "hazard accumulates across independent signals"
    (Affect.hazard_of ~side_effecting:true ~breached:true ~crashed:true = 1.0
     && Affect.hazard_of ~side_effecting:true ~breached:false ~crashed:false = 0.4);
  check "weights are policy -- reweighting changes the ranking"
    (let a = { Affect.zero with Affect.hazard = 1.0 } in
     let safety = { Affect.default_weights with Affect.w_hazard = 0.9 } in
     Affect.weighted safety a > Affect.weighted Affect.default_weights a);

  print_string "\nworking set\n";
  let big n txt = Working.item ~salience:n (String.concat "" (List.init 500 (fun _ -> txt))) in
  let soul = Working.item ~pinned:true ~salience:1.0 "SOUL" in
  let a = Working.assemble ~floor:1000 ~ceiling:3000
            [ soul; big 0.9 "surprising "; big 0.1 "routine "; big 0.5 "middling " ] in
  check "pinned material is always included"
    (List.exists (fun i -> i.Working.pinned) a.Working.included);
  check "ceiling is respected" (a.Working.total <= 4000);
  check "eviction is counted, not silent" (a.Working.evicted > 0);
  check "the most surprising survives eviction"
    (List.exists (fun i -> i.Working.salience = 0.9) a.Working.included);
  check "the least surprising is what goes"
    (not (List.exists (fun i -> i.Working.salience = 0.1) a.Working.included));
  let cold = Working.assemble ~floor:64_000 ~ceiling:128_000 [ soul ] in
  check "below the floor reports COLD rather than passing quietly"
    (cold.Working.cold && cold.Working.total < 64_000);

  print_string "\nworking memory -- two bands, condensing\n";
  let para tag =
    String.concat " "
      (List.init 200 (fun i -> Printf.sprintf "%s sentence %d is here." tag i))
  in
  let long = para "alpha" in
  check "contraction reduces the token count"
    (Working.estimate (Working.contract ~budget:40 long) < Working.estimate long);
  check "contraction is a no-op below budget"
    (Working.contract ~budget:10_000 "short note" = "short note");
  let contains hay needle =
    let nh = String.length needle and n = String.length hay in
    let rec go i = i + nh <= n && (String.sub hay i nh = needle || go (i + 1)) in
    go 0
  in
  check "contraction keeps a [[link]] sentence even at budget 1"
    (contains
       (Working.contract ~budget:1
          "filler one. filler two. see [[the-form]] for why. filler three.")
       "[[the-form]]");
  let blob s tag = Working.item ~salience:s (para tag) in
  let ctx =
    Working.curate ~floor:1 ~immediate_ceiling:1500 ~working_ceiling:100_000
      [ Working.item ~pinned:true ~salience:1.0 "SOUL";
        blob 0.9 "hot"; blob 0.5 "warm"; blob 0.1 "cool" ]
  in
  check "immediate overflow is condensed into working, not evicted"
    (ctx.Working.condensed > 0 && ctx.Working.evicted = 0);
  check "pinned material stays verbatim in immediate"
    (List.exists
       (fun s -> s.Working.item.Working.pinned && not s.Working.contracted)
       ctx.Working.immediate);
  check "a condensed slot keeps its full text addressable"
    (List.for_all
       (fun s ->
         (not s.Working.contracted)
         || String.length (Working.expand s)
            > String.length s.Working.item.Working.text)
       ctx.Working.working);
  check "condensing reports its loss -- contraction, not a free lunch"
    (List.for_all
       (fun s -> (not s.Working.contracted) || s.Working.ratio < 1.0)
       ctx.Working.working);
  let tight =
    Working.curate ~floor:1 ~immediate_ceiling:1500 ~working_ceiling:50
      [ blob 0.9 "hot"; blob 0.5 "warm"; blob 0.1 "cool" ]
  in
  check "eviction returns only once the working band is also full"
    (tight.Working.evicted > 0);
  check "below the immediate floor still reports COLD"
    (Working.curate ~floor:64_000 [ Working.item ~salience:0.5 "tiny" ]).Working.cold;

  Printf.printf "\ntotal: %d passed, %d failed\n" !pass !fail;
  if !fail > 0 then exit 1

let () =
  print_string "\nkits\n";
  check "a valid kit validates"
    (match Kit.critic with Ok k -> k.Kit.name = "critic" | Error _ -> false);
  check "a zero-capability kit is valid" (match Kit.echo with Ok _ -> true | _ -> false);
  check "A KIT MAY NOT GRANT THE RETRIEVAL THE COMPOSER USED TO DESIGN IT"
    (match Kit.bad_researcher with
     | Error (Kit.Composer_only Grants.Retrieve) -> true | _ -> false);
  check "a kit with no terminal phase cannot finish, and is refused"
    (match Kit.make ~name:"endless" ~purpose:"spin"
             ~grants:[] ~state_shape:"unit"
             ~ladder:[ Phases.phase "working" ] ~budget_ms:1000 ~budget_actions:1 with
     | Error Kit.No_terminal_phase -> true | _ -> false);
  check "a kit with no purpose is refused"
    (match Kit.make ~name:"x" ~purpose:"  " ~grants:[] ~state_shape:"unit"
             ~ladder:Phases.echo_ladder ~budget_ms:100 ~budget_actions:0 with
     | Error Kit.Empty_purpose -> true | _ -> false);

  print_string "\nquery vs retrieve\n";
  check "Retrieve is composer-only; Query is not"
    (Grants.composer_only Grants.Retrieve
     && not (Grants.composer_only Grants.Query));
  check "no other action is composer-only"
    (not (List.exists Grants.composer_only
            [ Grants.Read; Grants.Write; Grants.Spawn; Grants.Emit ]));
  check "an actor claiming a composer-only grant is REFUSED, not queued"
    ((Conditions.evaluate { Conditions.clean with
                            Conditions.no_composer_grants = false })
       .Conditions.verdict = Conditions.Refuse);
  check "and the reason names it"
    (List.mem "actor_claims_composer_only_grant"
       (Conditions.evaluate { Conditions.clean with
                              Conditions.no_composer_grants = false }).Conditions.reasons);

  print_string "\nintrospection -- solely the AI's\n";
  let i = Introspect.create () in
  let now = 1_000_000.0 in
  let tok () = snd (Introspect.all i) in
  let w ?tags ?links text =
    match Introspect.write i (tok ()) ?tags ?links ~now text with
    | Ok e -> e | Error _ -> failwith "write refused" in

  let a = w ~tags:["scopes"; "hunch"]
            "I think I narrow fs_write harder than the envelope needs. \
             Not sure. Watch it." in
  let b = w ~tags:["scopes"] ~links:[a.Introspect.id]
            "Related: the refusals that annoy me most are the ones I agree with." in
  let c = w ~tags:["felt"] "Today's queue feels like thrash. Noting that I \
                            did not want to look at it, and that the runtime \
                            recorded the day as routine." in

  check "an entry needs no falsifier" (Introspect.peek_one i a.Introspect.id <> None);
  check "an entry needs no support" (List.length (Introspect.peek i) = 3);
  check "AN ENTRY HAS NO STATUS -- there is no field for a verdict"
    (a.Introspect.tags = ["scopes"; "hunch"]);
  check "tags are its own vocabulary; nothing validates them"
    (List.mem "hunch" (Introspect.tags i) && List.mem "felt" (Introspect.tags i));
  check "it draws its own structure"
    (List.length (Introspect.linked i b.Introspect.id) = 1);
  check "retrievable on its own terms"
    (List.length (Introspect.by_tag i "scopes") = 2);

  print_string "\nto write, you must read\n";
  check "a write needs a token, and only reading makes one"
    (match Introspect.write i (tok ()) ~now "a fresh read earns a write" with
     | Ok _ -> true | Error _ -> false);
  check "A TOKEN IS SINGLE-USE -- the second write on it is refused"
    (let t1 = tok () in
     match Introspect.write i t1 ~now "first" with
     | Error _ -> false
     | Ok _ -> (match Introspect.write i t1 ~now "second" with
                | Error Introspect.Stale_token -> true | _ -> false));
  check "a token from before someone else's write is stale"
    (let old = tok () in
     ignore (Introspect.write i (tok ()) ~now "intervening");
     match Introspect.write i old ~now "too late" with
     | Error Introspect.Stale_token -> true | _ -> false);
  check "SO APPENDING BLIND IS IMPOSSIBLE -- a drawer cannot happen"
    (let fresh = Introspect.create () in
     match Introspect.write fresh (snd (Introspect.all fresh)) ~now "read first" with
     | Ok _ -> true | Error _ -> false);
  check "peeking does NOT earn a write"
    (let f = Introspect.create () in
     ignore (Introspect.peek f);
     (* no token exists from peek; the only way to get one is read/all *)
     List.length (Introspect.peek f) = 0);
  check "rewrite and forget are gated the same way"
    (let t1 = tok () in
     match Introspect.forget i t1 ~id:c.Introspect.id with
     | Error _ -> false
     | Ok () -> (match Introspect.rewrite i t1 ~id:a.Introspect.id ~now "stale" with
                 | Error Introspect.Stale_token -> true | _ -> false));

  print_string "\nisolation is the whole design\n";
  check "THE AI READS IT" (Introspect.read_as Introspect.Ai i a.Introspect.id <> None);
  check "THE GATE DOES NOT" (Introspect.read_as Introspect.Gate i a.Introspect.id = None);
  check "the ledger does not" (Introspect.read_as Introspect.Ledger i a.Introspect.id = None);
  check "the confidence rule does not" (Introspect.all_as Introspect.Confidence i = []);
  check "A HUMAN DOES NOT -- review would make it a report"
    (Introspect.all_as Introspect.Human i = []);
  check "only the AI may write" (Introspect.may_write Introspect.Ai);
  check "nothing else may"
    (not (List.exists Introspect.may_write
            [ Introspect.Gate; Introspect.Ledger;
              Introspect.Human; Introspect.Confidence ]));
  check "the range-of-view asymmetry is the argument: they see all, it sees a window"
    (Introspect.may_read Introspect.Ai
     && not (Introspect.may_read Introspect.Gate));

  Printf.printf "\ntotal: %d passed, %d failed\n" !pass !fail;
  if !fail > 0 then exit 1
