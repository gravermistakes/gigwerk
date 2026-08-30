(* Reconstruction — a walk through linked documents, not a ranked bag.
 *
 * Think of a markdown file that links another markdown file that links
 * another. You land somewhere, read it, and its prose points onward; you
 * follow. The path is long-form and sequential, and the ORDER IS THE CONTENT.
 * That is what produces the feeling of recollection.
 *
 * RAG fires k queries in parallel, staples k chunks together, and reads like an
 * encyclopedia entry: true facts, no through-line, obviously looked up. The
 * difference is not retrieval quality. It is that one is a PATH and the other
 * is a SET.
 *
 * An earlier version of this file made links the ONLY path and claimed an
 * unlinked document could never be reached. That was wrong twice over. Every
 * document has a surface embedding, so the space itself carries relative
 * relations and nothing is unreachable. And the walk it produced was too
 * coherent to be memory: always on topic, never drifting.
 *
 * THREE CHANNELS, because recollection arrives by more than one road:
 *
 *   Link       an explicit [[reference]] -- narrative continuity
 *   Semantic   proximity in the surface embedding -- associative drift
 *   Resonance  matching AFFECT with near-zero semantic overlap -- the smell
 *
 * The third is the one that makes this feel like remembering. A smell triggers
 * a memory it has nothing to do with; what they share is a shape of feeling,
 * not a subject. A walk with only the first two channels can continue but
 * never jump, and a walk that can only continue on topic is a search wearing
 * a narrative coat.
 *
 * Each step records WHICH channel carried it, because the channel is the
 * interesting part of the trace.
 *
 * TWO MODES, and the second is not a variation on the first:
 *
 *   STRIKE      involuntary. A flavour or a song and you are simply THERE --
 *               no entry point, no path, no hops. Zero traversal. The memory
 *               arrives uninvited and `from = None` records that nothing led
 *               to it.
 *
 *   WALK        deliberate. Enter somewhere, follow links and proximity and
 *               resonance, drift. Long-form and effortful.
 *
 * The composition is how recollection actually behaves: the cue strikes, you
 * land on one specific moment, and the surrounding memory reconstructs outward
 * from where it dropped you. Strike seeds the walk.
 *
 * A cue is not a query. A query asks for something. A cue is just PRESENT --
 * a smell in a corridor, eight bars of a song -- and what it summons was not
 * requested. So a cue carries affect and barely any subject, which is exactly
 * why matching it semantically finds nothing.
 *
 * What comes back is fragments. The contraction is semantic-affectual: at
 * equal similarity affect decides which link is followed, at equal affect
 * similarity decides. Neither alone works — pure similarity walks toward the
 * relevant-and-forgettable, pure affect toward the memorable-and-irrelevant.
 *
 * And it is a READING. The stored form is lossy, the walk is selective, and
 * the result is inferred — overruled by any Record or Ruling that says
 * otherwise. Memory that claims to replay is lying about what it kept. *)

(* CONTRACTION IS NOT COMPACTION.
 *
 * A context-compaction command summarises forward and DISCARDS the original.
 * That has four properties this must not share:
 *
 *   it REPLACES      the detail is gone, so nothing can be reconstructed
 *   it is MODEL-AUTHORED  a summary is a Reading wearing a Record's clothes
 *   it FLATTENS      hierarchy and affect dissolve into one blob of prose
 *   it is ONE-SHOT   compress twice and you are summarising a summary
 *
 * So: `digest` is the contracted form, and `full` is STILL THERE. Contraction
 * ADDS a layer; it never replaces one. That is the difference between
 * reconstruction and lossy-forward summarisation -- detail remains addressable,
 * so `expand` can reach it when budget allows.
 *
 * And the contraction is MECHANICAL. Affect comes from the ledger -- prediction
 * error, hazard, a human's verdict. The semantic vector comes from a frozen
 * encoder. Neither is the model's opinion about what mattered, which is exactly
 * what a compaction summary is. *)
type doc = {
  id     : string;
  digest : string;            (* the contracted form, with [[links]] inline *)
  full   : string option;     (* the original. NOT discarded. *)
  vec    : Embed.vec;         (* embedded from the digest -- what is searched *)
  affect : Affect.t;
}

type store = (string, doc) Hashtbl.t

let store () : store = Hashtbl.create 64

let doc ?(affect = Affect.zero) ?full ~id digest =
  { id; digest; full; vec = Embed.of_text digest; affect }

(* The original, when there is one. A reconstruction that can never reach detail
   is a summary; one that can is a reconstruction. *)
let expand d = match d.full with Some f -> f | None -> d.digest
let is_contracted d = d.full <> None

(* How much was thrown away. A contraction that reports no loss is not
   contracting, and one that reports total loss has nothing to expand into. *)
let compression_ratio d =
  match d.full with
  | None -> 1.0
  | Some f ->
      if String.length f = 0 then 1.0
      else float_of_int (String.length d.digest) /. float_of_int (String.length f)

let add (s : store) d = Hashtbl.replace s d.id d
let get (s : store) id = Hashtbl.find_opt s id

(* [[target]] inline. The link lives in the sentence, which is why the rendered
   path reads continuously instead of as a list of excerpts. *)
let links d =
  let out = ref [] and n = String.length d.digest in
  let i = ref 0 in
  while !i < n - 1 do
    if d.digest.[!i] = '[' && d.digest.[!i + 1] = '[' then begin
      let j = ref (!i + 2) in
      while !j < n - 1 && not (d.digest.[!j] = ']' && d.digest.[!j + 1] = ']') do incr j done;
      if !j < n - 1 then begin
        out := String.sub d.digest (!i + 2) (!j - !i - 2) :: !out;
        i := !j + 2
      end else incr i
    end else incr i
  done;
  List.rev !out

type channel = Link | Semantic | Resonance

let channel_to_string = function
  | Link -> "link" | Semantic -> "semantic" | Resonance -> "resonance"

type step = {
  doc  : doc;
  from : string option;    (* which document reminded us of this one *)
  via  : channel;          (* and by which road *)
  pull : float;
}

type recollection = {
  path       : step list;   (* ordered; the order is the content *)
  jumps      : int;         (* how many steps arrived by resonance *)
  rendered   : string;
  turns      : int;
  dead_end   : bool;        (* the thread went cold rather than running out *)
  is_reading : bool;        (* always *)
}

(* Channel weights are POLICY. Raise resonance and the walk drifts more; drop
   it to zero and you have a coherent, on-topic, unmemorable search. *)
type channels = { w_link : float; w_semantic : float; w_resonance : float }
let default_channels = { w_link = 1.0; w_semantic = 0.75; w_resonance = 0.9 }

(* At each document, choose ONE next step. Choosing all of them turns the walk
   back into a set, and the set is what reads encyclopedically. *)
let recollect (s : store) ?(budget = 1200) ?(weights = Affect.default_weights)
              ?(channels = default_channels) ?(threshold = 0.02)
              ~entry ~query () =
  let q = Embed.of_text query in
  let seen = Hashtbl.create 16 in
  let all () = Hashtbl.fold (fun _ d acc -> d :: acc) s [] in
  let candidates current =
    let linked = links current |> List.filter_map (get s) in
    let linked_ids = List.map (fun d -> d.id) linked in
    let others =
      all () |> List.filter (fun d ->
          d.id <> current.id && not (List.mem d.id linked_ids)) in
    let by_link =
      List.map (fun d ->
          (d, Link,
           channels.w_link
           *. (Embed.cosine q d.vec
               +. (0.35 *. Affect.weighted weights d.affect))))
        linked in
    let by_semantic =
      List.map (fun d ->
          (d, Semantic, channels.w_semantic *. Embed.cosine q d.vec)) others in
    (* Resonance scores on AFFECT ALIGNMENT WITH THE CURRENT DOCUMENT, not on
       the query. That is what lets a step arrive with almost no semantic
       relation to anything being asked about -- which is the whole point.
       Flat affect resonates with nothing; furniture is not a cue. *)
    let by_resonance =
      if Affect.is_flat current.affect then []
      else
        List.filter_map (fun d ->
            if Affect.is_flat d.affect then None
            else
              let r = Affect.resonance current.affect d.affect in
              let sem = Embed.cosine q d.vec in
              (* only counts as a jump when the semantic link is genuinely
                 weak -- otherwise it is just a semantic step wearing a hat *)
              if r > 0.75 && sem < 0.25
              then Some (d, Resonance, channels.w_resonance *. r)
              else None)
          others
    in
    by_link @ by_semantic @ by_resonance
    |> List.filter (fun (d, _, _) -> not (Hashtbl.mem seen d.id))
    |> List.sort (fun (_, _, a) (_, _, b) -> compare b a)
  in
  let rec walk current from via spent acc =
    if Hashtbl.mem seen current.id then (List.rev acc, spent, false)
    else begin
      Hashtbl.replace seen current.id true;
      let cost = (String.length current.digest + 3) / 4 in
      if spent + cost > budget && acc <> [] then (List.rev acc, spent, false)
      else
        let acc = { doc = current; from; via;
                    pull = Embed.cosine q current.vec } :: acc in
        let spent = spent + cost in
        match candidates current with
        | (next, ch, p) :: _ when p >= threshold ->
            walk next (Some current.id) ch spent acc
        | _ -> (List.rev acc, spent, true)
    end
  in
  match get s entry with
  | None -> { path = []; jumps = 0; rendered = ""; turns = 0;
              dead_end = true; is_reading = true }
  | Some e ->
      let path, _spent, cold = walk e None Link 0 [] in
      { path;
        jumps = List.length (List.filter (fun st -> st.via = Resonance) path);
        rendered = String.concat "\n\n" (List.map (fun st -> st.doc.digest) path);
        turns = List.length path; dead_end = cold; is_reading = true }

(* ------------------------------------------------------------- strike ----
 *
 * No entry point. No traversal. The cue's affect signature is matched against
 * every memory's, and the strongest resonance IS the result -- one step, or
 * none.
 *
 * Two conditions, and the second is what makes it recall rather than search:
 *
 *   1. a flat cue cannot strike. A stimulus that provoked nothing summons
 *      nothing; that is not memory, it is furniture.
 *   2. the SEMANTIC overlap must be weak. A cue that is already about the
 *      memory is a query, and finding it is retrieval. The whole phenomenon
 *      is that the flavour has nothing to do with the afternoon it returns.
 *)
(* `max_semantic` is a PERCENTILE of this store, not a constant.
 *
 * Measured on the shipped encoder: unrelated pairs mean 0.065 but reach 0.279;
 * related pairs mean 0.321 but fall to 0.139. The distributions overlap badly,
 * so any fixed cutoff either admits related documents (making strike degenerate
 * into semantic search) or excludes genuine strikes. A constant cannot be right
 * for both a store of terse log lines and a store of prose.
 *
 * Taking the 25th percentile of the cue's actual similarity distribution asks
 * the question that matters -- "is this among the LEAST related things here?" --
 * instead of guessing an absolute.
 *
 * BUT a percentile over a small store is unstable. With six documents the 25th
 * percentile is essentially the second-smallest value, so adding one unrelated
 * document moves the strike threshold and a cue that fired stops firing. That
 * is not hypothetical -- it broke seven tests the first time this landed.
 *
 * So the percentile only applies once there are enough documents for a
 * distribution to mean anything. Below that, fall back to a deliberately
 * conservative absolute: unrelated pairs measured mean 0.065 sd 0.111, so
 * mean + 1sd ~ 0.18 admits most genuine strikes while excluding most of the
 * related range. Neither rule is right everywhere; the switch is the point. *)
let percentile p xs =
  match List.sort compare xs with
  | [] -> 1.0
  | sorted ->
      let n = List.length sorted in
      let i = min (n - 1) (max 0 (int_of_float (p *. float_of_int (n - 1)))) in
      List.nth sorted i

(* Below this the distribution is noise, not a distribution. *)
let min_store_for_percentile = 20
let small_store_max_semantic = 0.18   (* unrelated mean + 1sd, measured *)

let strike (s : store) ?(affect = Affect.zero) ?(min_resonance = 0.7)
           ?(semantic_percentile = 0.25) ~cue () =
  if Affect.is_flat affect then None
  else
    let q = Embed.of_text cue in
    let sims = Hashtbl.fold (fun _ d acc -> Embed.cosine q d.vec :: acc) s [] in
    let max_semantic =
      if List.length sims < min_store_for_percentile then small_store_max_semantic
      else percentile semantic_percentile sims in
    Hashtbl.fold (fun _ d acc -> d :: acc) s []
    |> List.filter_map (fun d ->
        if Affect.is_flat d.affect then None
        else
          let r = Affect.resonance affect d.affect in
          let sem = Embed.cosine q d.vec in
          if r >= min_resonance && sem <= max_semantic then Some (d, r) else None)
    |> List.sort (fun (_, a) (_, b) -> compare b a)
    |> function [] -> None | (d, _) :: _ -> Some d

(* Strike, then reconstruct outward from wherever it landed. The struck memory
   is step one with `from = None` and `via = Resonance`: nothing reminded us. *)
let remember (s : store) ?budget ?weights ?channels ~cue ~cue_affect ~query () =
  match strike s ~affect:cue_affect ~cue () with
  | None -> { path = []; jumps = 0; rendered = ""; turns = 0;
              dead_end = true; is_reading = true }
  | Some entry ->
      let r = recollect s ?budget ?weights ?channels ~entry:entry.id ~query () in
      { r with
        jumps = r.jumps + 1;
        path = (match r.path with
                | first :: rest -> { first with via = Resonance } :: rest
                | [] -> []) }

(* What a RAG would do with the same store: rank everything by similarity and
   staple the top k together. Kept here for comparison, and because the test
   that matters is the DIFFERENCE. *)
let encyclopedic (s : store) ?(k = 3) ~query () =
  let q = Embed.of_text query in
  Hashtbl.fold (fun _ d acc -> (d, Embed.cosine q d.vec) :: acc) s []
  |> List.sort (fun (_, a) (_, b) -> compare b a)
  |> List.filteri (fun i _ -> i < k)
  |> List.map fst
