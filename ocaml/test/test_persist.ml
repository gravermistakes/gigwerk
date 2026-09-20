(* Round-trip proof for lib/persist.ml: build real values in memory, save
 * them to a real temp sqlite database (schema.sql then persist.sql), load
 * them back through nothing but Persist's own functions, and check the
 * loaded value against the one that went in -- never against a description
 * of what it should look like. *)
open Gigwerk

let pass = ref 0 and fail = ref 0
let check name b =
  if b then (incr pass; Printf.printf "  ok   %s\n" name)
  else (incr fail; Printf.printf "  FAIL %s\n" name)

(* sql/ lives at the repo root, one level above ocaml/ -- OUTSIDE the dune
   project rooted at ocaml/dune-project. Dune's _build tree only ever mirrors
   what is inside that root, so there is no dune-relative path from a test
   binary's build directory that reaches sql/schema.sql; it is simply not in
   the tree dune manages. The real OS filesystem still has it, though, at
   its ordinary place on disk, so search upward from wherever this process's
   cwd actually is (deep inside _build/default/test under `dune test`, or
   the repo itself if run some other way) until it turns up. *)
let find_repo_file relpath =
  let rec go dir depth =
    if depth > 16 then
      failwith (Printf.sprintf "test_persist: %s not found above %s"
                  relpath (Sys.getcwd ()))
    else if Sys.file_exists (Filename.concat dir relpath) then
      Filename.concat dir relpath
    else
      let parent = Filename.dirname dir in
      if parent = dir then
        failwith (Printf.sprintf "test_persist: %s not found above %s"
                    relpath (Sys.getcwd ()))
      else go parent (depth + 1)
  in
  go (Sys.getcwd ()) 0

let schema_sql = find_repo_file "sql/schema.sql"
let persist_sql = find_repo_file "sql/persist.sql"

(* A fresh, real sqlite file per test run -- not :memory:, because Store
   shells out to a NEW sqlite3 process per call (see store.ml's `sh`), and an
   in-memory database does not survive past the process that created it. A
   real temp file is the only kind of database Store's design can actually
   see twice. *)
let fresh_db () =
  let db = Filename.temp_file "gigwerk_persist_test" ".sqlite3" in
  let cmd = Printf.sprintf "sqlite3 %s %s %s"
      (Filename.quote db)
      (Filename.quote (".read " ^ schema_sql))
      (Filename.quote (".read " ^ persist_sql)) in
  if Sys.command cmd <> 0 then failwith "test_persist: schema load failed";
  Store.db_path := db

let dummy_doc = Reconstruct.doc ~id:"__MISSING__" "__MISSING__"
let or_dummy_doc = function Some d -> d | None -> dummy_doc

let dummy_entry : Introspect.entry =
  { Introspect.id = -1; text = "__MISSING__"; tags = []; links = []; at = -1.0 }
let entry_or_dummy = function Some e -> e | None -> dummy_entry
let find_entry entries id = entry_or_dummy (List.find_opt (fun e -> e.Introspect.id = id) entries)

let () =
  fresh_db ();

  (* =================================================================== *)
  print_string "\npersist: sarcasm_doc -- plain vs contracted\n";
  (* =================================================================== *)

  let plain = Reconstruct.doc ~id:"plain-1" "just a plain digest with no links at all" in
  Persist.save_doc plain;
  let loaded_plain = or_dummy_doc (Persist.load_doc "plain-1") in

  check "a saved doc loads back at all" (Persist.load_doc "plain-1" <> None);
  check "digest survives exactly" (loaded_plain.Reconstruct.digest = plain.Reconstruct.digest);
  check "an uncontracted doc's full loads back as None, not Some \"\""
    (loaded_plain.Reconstruct.full = None);
  check "vector round-trips through the column: to_string is byte-identical"
    (Embed.to_string loaded_plain.Reconstruct.vec = Embed.to_string plain.Reconstruct.vec);
  check "vector round-trips through the column: cosine against itself is ~1.0"
    (Embed.cosine plain.Reconstruct.vec loaded_plain.Reconstruct.vec > 0.999);
  check "a nonexistent id loads back as None" (Persist.load_doc "no-such-doc" = None);

  let long = "The full original text, considerably longer than its digest, \
              with apostrophes like it's and don't to exercise Store.esc." in
  let contracted = Reconstruct.doc ~id:"contracted-1" ~full:long
      "A short digest of the above, with [[plain-1]] linked in." in
  Persist.save_doc contracted;
  let loaded_contracted = or_dummy_doc (Persist.load_doc "contracted-1") in

  check "a contracted doc's full survives exactly, apostrophes and all"
    (loaded_contracted.Reconstruct.full = Some long);
  check "a contracted doc is still reported contracted after loading"
    (Reconstruct.is_contracted loaded_contracted);
  check "expand on the loaded doc reaches the real full text, not the digest"
    (Reconstruct.expand loaded_contracted = long);

  (* =================================================================== *)
  print_string "\npersist: affect tones survive as a vector, not a scalar\n";
  (* =================================================================== *)

  (* Same magnitude, different shape: swapping which single tone carries the
     weight leaves Affect.magnitude tied between the two, so recovering the
     RIGHT shape (not just the right magnitude) after a reload is proof the
     six tones were stored as themselves and not folded into one number. *)
  let shape_a = { Affect.surprise = 0.9; hazard = 0.1;
                  novelty = 0.1; cost = 0.1; dissonance = 0.1; valence = 0.1 } in
  let shape_b = { Affect.surprise = 0.1; hazard = 0.9;
                  novelty = 0.1; cost = 0.1; dissonance = 0.1; valence = 0.1 } in
  check "the two fixtures really do tie on magnitude (or this test proves nothing)"
    (Affect.magnitude shape_a = Affect.magnitude shape_b);

  Persist.save_doc (Reconstruct.doc ~id:"shape-a" ~affect:shape_a "doc a");
  Persist.save_doc (Reconstruct.doc ~id:"shape-b" ~affect:shape_b "doc b");
  let la = (or_dummy_doc (Persist.load_doc "shape-a")).Reconstruct.affect in
  let lb = (or_dummy_doc (Persist.load_doc "shape-b")).Reconstruct.affect in

  check "loaded magnitudes still tie -- a scalar could not have distinguished these"
    (Affect.magnitude la = Affect.magnitude lb);
  check "but the loaded SHAPES differ, correctly, on exactly the swapped tones"
    (la.Affect.surprise = 0.9 && la.Affect.hazard = 0.1
     && lb.Affect.surprise = 0.1 && lb.Affect.hazard = 0.9);
  check "all six tones of shape_a survive individually and exactly"
    (la.Affect.surprise = shape_a.Affect.surprise && la.Affect.hazard = shape_a.Affect.hazard
     && la.Affect.novelty = shape_a.Affect.novelty && la.Affect.cost = shape_a.Affect.cost
     && la.Affect.dissonance = shape_a.Affect.dissonance && la.Affect.valence = shape_a.Affect.valence);

  (* A value that needs more than sqlite's default 15-significant-digit text
     rendering to come back as the SAME double -- see the limitation (2)
     comment in persist.ml. A hand-picked literal like 0.9 would not
     exercise this: it already round-trips at 15 digits because it was
     typed as one. A derived, irrational-looking float is what actually
     tests the printf('%.17g', ...) path instead of getting lucky. *)
  let sharp = Affect.novelty_of ~prior_runs:37 in
  let precise = { Affect.zero with Affect.novelty = sharp; valence = -0.42 } in
  Persist.save_doc (Reconstruct.doc ~id:"precise-1" ~affect:precise "precision fixture");
  let lp = (or_dummy_doc (Persist.load_doc "precise-1")).Reconstruct.affect in
  check "a full-precision derived float survives exactly, not rounded to 15 digits"
    (lp.Affect.novelty = sharp);
  check "an ordinary negative valence survives exactly alongside it"
    (lp.Affect.valence = precise.Affect.valence);

  (* =================================================================== *)
  print_string "\npersist: sarcasm_link -- links survive and point at the right ids\n";
  (* =================================================================== *)

  let walk = Reconstruct.store () in
  let d ?affect id body = Reconstruct.add walk (Reconstruct.doc ?affect ~id body) in
  d "walk-a" "Starts here, mentions [[walk-b]] once, returns to [[walk-b]] again, then [[walk-c]].";
  d "walk-b" "A middle document, linking onward to [[walk-c]].";
  d "walk-c" "The end of the chain, no further links.";
  Persist.save_store walk;

  check "links survive, in original order, duplicates included"
    (Persist.doc_links "walk-a" = [ "walk-b"; "walk-b"; "walk-c" ]);
  check "a doc with exactly one outgoing link reports exactly that one"
    (Persist.doc_links "walk-b" = [ "walk-c" ]);
  check "a doc with no links reports none, not a phantom entry"
    (Persist.doc_links "walk-c" = []);
  check "a link to an id outside the store is still stored (dangling links are not errors)"
    (Persist.save_doc (Reconstruct.doc ~id:"dangling" "points at [[nowhere-at-all]]");
     Persist.doc_links "dangling" = [ "nowhere-at-all" ]);

  (* Re-saving with FEWER links must not leave the old ones behind: sarcasm_link
     is a projection of `digest`, rebuilt whole on every save, not diffed. *)
  Persist.save_doc (Reconstruct.doc ~id:"walk-a" "Now links only to [[walk-c]].");
  check "re-saving with a shorter link list wipes the stale rows, not just adds to them"
    (Persist.doc_links "walk-a" = [ "walk-c" ]);
  (* put walk-a back the way the rest of this section assumes, for load_store below *)
  d "walk-a" "Starts here, mentions [[walk-b]] once, returns to [[walk-b]] again, then [[walk-c]].";
  Persist.save_doc (Reconstruct.doc ~id:"walk-a"
    "Starts here, mentions [[walk-b]] once, returns to [[walk-b]] again, then [[walk-c]].");

  let reloaded_store = Persist.load_store () in
  check "load_store recovers every saved id"
    (List.for_all (fun id -> Reconstruct.get reloaded_store id <> None)
       [ "walk-a"; "walk-b"; "walk-c"; "plain-1"; "contracted-1" ]);
  check "a doc out of load_store's links agree with Persist.doc_links on the same id"
    (match Reconstruct.get reloaded_store "walk-a" with
     | Some rd -> Reconstruct.links rd = Persist.doc_links "walk-a"
     | None -> false);

  (* =================================================================== *)
  print_string "\npersist: introspect -- text, tags and links survive\n";
  (* =================================================================== *)

  let intro = Introspect.create () in
  let now = 1_756_262_400.5 in   (* fractional, so `at` exercises the same precision path as affect *)
  let tok () = snd (Introspect.all intro) in
  let w ?tags ?links text =
    match Introspect.write intro (tok ()) ?tags ?links ~now text with
    | Ok e -> e | Error _ -> failwith "test_persist setup: write refused" in

  let e1 = w ~tags:[ "scope"; "hunch" ] "a first entry, with an apostrophe: it's mine" in
  let e2 = w ~tags:[ "scope" ] ~links:[ e1.Introspect.id ] "a second entry linking the first" in
  let e3 = w "a third entry, no tags, no links" in

  Persist.save_introspect intro;
  let loaded_intro = Persist.load_introspect () in
  let loaded_entries = Introspect.peek loaded_intro in

  check "every entry comes back, none dropped, none duplicated"
    (List.length loaded_entries = 3);
  check "entry text survives, apostrophe included"
    ((find_entry loaded_entries e1.Introspect.id).Introspect.text = e1.Introspect.text);
  check "entry tags survive as an ordered list, not a single joined string"
    ((find_entry loaded_entries e1.Introspect.id).Introspect.tags = [ "scope"; "hunch" ]);
  check "an entry with no tags loads back with none, not [\"\"]"
    ((find_entry loaded_entries e3.Introspect.id).Introspect.tags = []);
  check "entry links survive and point at the right id"
    ((find_entry loaded_entries e2.Introspect.id).Introspect.links = [ e1.Introspect.id ]);
  check "an entry with no links loads back with none, not [0]"
    ((find_entry loaded_entries e1.Introspect.id).Introspect.links = []);
  check "at survives with its fractional part, not truncated to whole seconds"
    ((find_entry loaded_entries e1.Introspect.id).Introspect.at = now);
  check "peek order matches the original write order exactly"
    (List.map (fun e -> e.Introspect.id) loaded_entries
     = List.map (fun e -> e.Introspect.id) (Introspect.peek intro));

  (* ---- the token discipline itself, after a load ---- *)
  check "a loaded notebook still refuses a write against the wrong generation"
    (match Introspect.write loaded_intro { Introspect.tgen = 999 } ~now "wrong generation" with
     | Error Introspect.Stale_token -> true
     | _ -> false);
  let before_ids = List.map (fun e -> e.Introspect.id) (Introspect.peek loaded_intro) in
  check "read-then-write on a loaded notebook works, and gets a non-colliding id"
    (match Introspect.write loaded_intro (snd (Introspect.all loaded_intro)) ~now "earned by reading first" with
     | Ok e -> not (List.mem e.Introspect.id before_ids)
     | Error _ -> false);
  (* Documents a real, pre-existing gap rather than hiding it: introspect.ml
     ships with no .mli, so `token` and `t.gen` are public on ANY Introspect.t
     -- one from create() as much as one from load_introspect(). Guessing the
     generation load_introspect() happens to start at is therefore possible,
     same as it always was; this is checked (not just claimed in a comment)
     so that if introspect.ml ever gains a real .mli, this assertion is the
     thing that goes red and says the comment needs updating. Uses a FRESH
     load so the generation being guessed is really 0, not shifted by writes
     earlier in this file. *)
  let fresh_load = Persist.load_introspect () in
  check "KNOWN GAP (see persist.ml/report): tgen=0 is guessable against a fresh \
         load, because introspect.ml has no .mli -- not introduced by loading"
    (match Introspect.write fresh_load { Introspect.tgen = 0 } ~now "guessed" with
     | Ok _ -> true | Error _ -> false);

  (* =================================================================== *)
  print_string "\npersist: trace spans into the ledger's own span table\n";
  (* =================================================================== *)

  (* span.gig_id is a real foreign key onto gig(id), and gig.entity_id is a
     real foreign key onto entity(id) -- populate both for real, or a
     silently-failed insert would leave this section proving nothing. *)
  Store.exec
    "INSERT INTO entity (id, name, provenance, created_at) \
       VALUES (1, 'trace-test-entity', 'agent', 0); \
     INSERT INTO gig (id, entity_id, composition_sig, booked_at, tier) \
       VALUES (1, 1, 'sig', 0, 'in_process');";
  check "the fixture gig row is really there (or the span rows below are meaningless)"
    (Store.query "SELECT id FROM gig WHERE id = 1;" = [ [ "1" ] ]);

  let tr = Trace.create ~gig:"a human label, not gig.id" in
  let root = Trace.open_ tr "gig" in
  let a = Trace.open_ tr ~parent:root ~phase:"read" "fs_read" in
  Trace.close tr ~outcome:"ok" a;
  let b = Trace.open_ tr ~parent:root ~phase:"checked" "balance_check" in
  Trace.close tr ~breach:"budget exhausted" b;
  (* root is deliberately left unclosed *)

  Persist.save_trace ~gig_id:1 tr;
  let rows = Persist.load_spans ~gig_id:1 in

  check "every span was written -- same count as Trace.to_rows produced"
    (List.length rows = List.length (Trace.to_rows tr));
  check "an unclosed span persists its -1 sentinel, not NULL and not 0"
    (List.exists (fun (id, _, _, _, dur, _, _) -> id = root && dur = -1) rows);
  check "a closed span's outcome survives"
    (List.exists (fun (id, _, _, _, _, outcome, _) -> id = a && outcome = Some "ok") rows);
  check "a breach survives on the span that breached"
    (List.exists (fun (id, _, _, _, _, _, breach) -> id = b && breach = Some "budget exhausted") rows);
  check "a closed-without-breach span's breach is None, not Some \"\""
    (List.exists (fun (id, _, _, _, _, _, breach) -> id = a && breach = None) rows);
  check "parent links survive, and the root's parent is really None"
    (List.exists (fun (id, parent, _, _, _, _, _) -> id = a && parent = Some root) rows
     && List.exists (fun (id, parent, _, _, _, _, _) -> id = root && parent = None) rows);
  check "phase survives"
    (List.exists (fun (id, _, _, phase, _, _, _) -> id = a && phase = Some "read") rows);
  check "span names survive"
    (List.exists (fun (id, _, name, _, _, _, _) -> id = a && name = "fs_read") rows);

  (* =================================================================== *)
  print_string "\npersist -> working: the working band is fed from SARCASM\n";
  (* =================================================================== *)
  fresh_db ();  (* isolate: load_store reads every doc in the db *)

  let wm =
    Reconstruct.doc ~id:"wm-1"
      ~full:
        "A long verbatim original. It has several sentences. See [[wm-2]] for \
         the linked one. And still more filler after that."
      "Digest: see [[wm-2]]."
  in
  Persist.save_doc wm;
  let loaded = Persist.load_store () in
  let items =
    Hashtbl.fold
      (fun _ (d : Reconstruct.doc) acc ->
        let ready =
          if Reconstruct.is_contracted d then Some d.Reconstruct.digest else None
        in
        Working.item ~salience:0.9 ?ready_digest:ready (Reconstruct.expand d) :: acc)
      loaded []
  in
  (* immediate tiny, so the doc cannot stay verbatim and must spill *)
  let ctx = Working.curate ~floor:1 ~immediate_ceiling:1 ~working_ceiling:10_000 items in
  check "a persisted doc reaches the working band as a condensed slot"
    (List.length ctx.Working.working = 1);
  check "the working slot reuses SARCASM's stored digest, not a re-contraction"
    (match ctx.Working.working with
     | [ s ] -> s.Working.item.Working.text = "Digest: see [[wm-2]]."
     | _ -> false);
  check "and the verbatim original is still addressable through the slot"
    (match ctx.Working.working with
     | [ s ] ->
         Working.expand s
         = (match wm.Reconstruct.full with Some f -> f | None -> "")
     | _ -> false);

  Printf.printf "\n%d passed, %d failed\n" !pass !fail;
  if !fail > 0 then exit 1
