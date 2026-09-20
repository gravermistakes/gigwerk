(* Active context assembly -- the working memory, fed from the store.
 *
 * This is the wiring MEMORY.md's band 2 was missing: `Working` had the two-band
 * shape and the condensing process, but nothing in the running program handed
 * it real material. Here it is handed the store, so `gigwerk context` assembles
 * the same context the composer would carry into a turn.
 *
 * WHO IS PINNED, AND WHY IT IS NOT A RANKING. Soul and live rulings never
 * contract and never evict. Not because they scored highest -- they are not in
 * the salience race at all. The soul is a bound (soul.sql: changing it
 * invalidates confidence), and a live ruling is what the human decided; a
 * context that lets either fall out of the window because a loud memory
 * out-ranked it is a context that has quietly changed the rules of the machine.
 *
 * WHO ELSE, AND HOW RANKED. Every SARCASM doc becomes one item. Its salience is
 * `Affect.weighted` over the doc's own tone vector -- ledger-derived, the same
 * number the eviction sort uses -- so what stays verbatim in immediate is what
 * mattered, not what arrived last. Its text is the FULL form (expand), so a doc
 * salient enough for immediate is present in full; on spill into working it is
 * contracted, and it is contracted to the digest SARCASM already computed
 * (ready_digest) rather than a fresh one, because that digest is the canonical
 * contracted form and what recollect/strike search.
 *
 * This module calls Persist.load_store, which is the first thing in the running
 * program to do so -- SARCASM stops being write-only the moment a context is
 * assembled from it. *)

(* Soul body, pinned. v_soul_current is the one non-retired version. *)
let soul_pinned () =
  match Store.query "SELECT body FROM v_soul_current LIMIT 1" with
  | [ [ body ] ] when String.trim body <> "" ->
      [ Working.item ~pinned:true ~salience:1.0 (String.trim body) ]
  | _ -> []

(* Live rulings, pinned. Retired rulings are deliberately excluded: "we used to
   think X" is context worth keeping in the ledger (memory.sql keeps the row)
   but it is not what the machine currently believes, so it does not belong in
   the active window as though it were. *)
let ruling_pinned () =
  Store.query
    "SELECT subject || ' ' || predicate || ' ' || object FROM mem_ruling \
     WHERE retired_at IS NULL ORDER BY at"
  |> List.filter_map (function
       | [ s ] when String.trim s <> "" ->
           Some (Working.item ~pinned:true ~salience:1.0 (String.trim s))
       | _ -> None)

(* Every SARCASM doc, ranked by its own affect. The full text is what goes in;
   the stored digest rides along as ready_digest so the working band reuses
   SARCASM's contraction instead of computing a second one. *)
let doc_items () =
  let s = Persist.load_store () in
  Hashtbl.fold
    (fun _ (d : Reconstruct.doc) acc ->
      let salience = Affect.weighted Affect.default_weights d.Reconstruct.affect in
      let ready_digest =
        if Reconstruct.is_contracted d then Some d.Reconstruct.digest else None
      in
      Working.item ~salience ?ready_digest (Reconstruct.expand d) :: acc)
    s []

(* The whole active context: pinned first, then the affect-ranked docs, run
   through the two bands. The caller (the CLI) chooses the band sizes. *)
let assemble ?floor ?immediate_ceiling ?working_ceiling () =
  Working.curate ?floor ?immediate_ceiling ?working_ceiling
    (soul_pinned () @ ruling_pinned () @ doc_items ())
