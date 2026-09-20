(* Working memory — the floor, not the ceiling.
 *
 * Most context handling treats the window as a budget to minimise. This is the
 * opposite claim and it is the right one: below some floor the conversation
 * stops existing. The agent is not being efficient, it is answering isolated
 * prompts that happen to arrive in sequence.
 *
 * So the assembler fills TO a floor. If there is not enough material to reach
 * it, that is a reportable state -- a cold session -- rather than a quietly
 * thinner context nobody notices. *)

type item = {
  text     : string;
  tokens   : int;         (* estimated *)
  pinned   : bool;        (* soul, live rulings: never evicted *)
  salience : float;
  (* A contraction the SOURCE already computed -- a SARCASM digest is the
     canonical contracted form and what search runs on, so when this item
     spills into the working band that digest is reused rather than a fresh one
     computed. None means "contract me on spill". Immediate never looks at it:
     immediate is verbatim. *)
  ready_digest : string option;
}

(* ~4 chars per token. Wrong in the third digit, right in the first, and the
   decision it feeds is "have we reached the floor", not billing. *)
let estimate text = (String.length text + 3) / 4

let item ?(pinned = false) ?(salience = 0.0) ?ready_digest text =
  { text; tokens = estimate text; pinned; salience; ready_digest }

type assembly = {
  included : item list;
  total    : int;
  floor    : int;
  ceiling  : int;
  cold     : bool;        (* could not reach the floor *)
  evicted  : int;
}

(* Pinned first, then by salience. Recency is deliberately not the sort key:
   the most recent thing is frequently the least surprising, and a window
   filled by recency is a window filled with what you already expected. *)
let assemble ?(floor = 64_000) ?(ceiling = 128_000) items =
  let pinned, rest = List.partition (fun i -> i.pinned) items in
  let rest = List.sort (fun a b -> compare b.salience a.salience) rest in
  let rec take acc total = function
    | [] -> (List.rev acc, total, 0)
    | i :: tl ->
        if total + i.tokens <= ceiling then take (i :: acc) (total + i.tokens) tl
        else (List.rev acc, total, 1 + List.length tl)
  in
  let pinned_total = List.fold_left (fun a i -> a + i.tokens) 0 pinned in
  let chosen, total, evicted = take [] pinned_total rest in
  { included = pinned @ chosen; total; floor; ceiling;
    cold = total < floor; evicted }

let report a =
  Printf.sprintf "%d tokens (floor %d, ceiling %d)%s%s"
    a.total a.floor a.ceiling
    (if a.cold then " COLD -- below floor, continuity not established" else "")
    (if a.evicted > 0 then Printf.sprintf " %d evicted" a.evicted else "")

(* ==========================================================================
 * TWO BANDS, AND A CONDENSING PROCESS BETWEEN THEM
 *
 * `assemble` above is ONE band: it fills to a floor and EVICTS the overflow.
 * Eviction is the wrong verb for an active context. What falls out of immediate
 * attention has not stopped being true -- it has stopped being in front of you,
 * and the standard working-memory shape is two bands, not one:
 *
 *   IMMEDIATE   ~64k, VERBATIM. What the agent is actively working over. No
 *               contraction: detail here is load-bearing this turn.
 *   WORKING     ~128k, CONTRACTED. What was recently immediate and has spilled.
 *               Held as a digest so more of it fits, with the full text
 *               retained and addressable -- not summarised-and-discarded.
 *
 * The move from immediate to working is CONDENSING, and condensing is
 * CONTRACTION, not compaction (see reconstruct.ml for the full argument):
 *
 *   - it ADDS a layer. `full` is kept, so a working slot can be expanded back to
 *     verbatim or promoted to immediate on a later turn.
 *   - it is MECHANICAL. The frozen encoder decides which sentences survive; the
 *     model does not author the digest. A model-authored summary is a Reading
 *     wearing a Record's clothes, and this must not be one.
 *   - it reports its LOSS. `ratio` is digest/full; a condense claiming no loss
 *     did not condense.
 *
 * WHAT SPILLS IS CHOSEN BY AFFECT; WHAT SURVIVES THE SPILL, BY THE ENCODER.
 * Item salience (ledger-derived affect) orders which items stay verbatim in
 * immediate and which condense into working -- the affectual axis. Inside a
 * condensed item, sentence centrality against the item's own embedding orders
 * which sentences survive -- the semantic axis. Semantic-affectual, the same
 * pairing reconstruct.ml walks on. Per-sentence affect would sharpen the second
 * axis and does not exist yet: an item carries a scalar salience, not a
 * per-sentence tone vector. Named here, not hidden.
 * ========================================================================== *)

(* ---- the condensing process: mechanical, extractive contraction ---------- *)

(* Dumb, deterministic sentence split. Not linguistics -- just the unit that
   gets kept or dropped. Terminators and newlines are boundaries. *)
let sentences text =
  let out = ref [] and buf = Buffer.create 64 in
  let flush () =
    let s = String.trim (Buffer.contents buf) in
    if s <> "" then out := s :: !out;
    Buffer.clear buf
  in
  String.iter
    (fun c ->
      Buffer.add_char buf c;
      if c = '.' || c = '!' || c = '?' || c = '\n' then flush ())
    text;
  flush ();
  List.rev !out

(* A sentence carrying an explicit [[reference]] is narrative connective tissue.
   reconstruct.ml walks these, so contraction must never drop one -- losing the
   link would turn a path back into a bag. *)
let has_link s =
  let n = String.length s in
  let rec go i =
    if i >= n - 1 then false
    else if s.[i] = '[' && s.[i + 1] = '[' then true
    else go (i + 1)
  in
  go 0

(* Keep link-bearing sentences unconditionally, then the most central remaining
   sentences by cosine to the whole-item embedding, until the token budget is
   met. Kept sentences are re-emitted in ORIGINAL order -- the order is content,
   exactly as in the walk. The encoder is frozen, so the same text always
   contracts the same way: no model in this path. *)
let contract ~budget text =
  if estimate text <= budget then text (* nothing to contract; honest no-op *)
  else
    let ss = Array.of_list (sentences text) in
    let n = Array.length ss in
    if n <= 1 then text (* one indivisible sentence: keep it, report the loss *)
    else begin
      let whole = Embed.of_text text in
      let scores = Array.map (fun s -> Embed.cosine (Embed.of_text s) whole) ss in
      let keep = Array.make n false in
      let used = ref 0 in
      Array.iteri
        (fun i s -> if has_link s then (keep.(i) <- true; used := !used + estimate s))
        ss;
      let order =
        List.init n Fun.id
        |> List.sort (fun a b -> compare scores.(b) scores.(a))
      in
      List.iter
        (fun i ->
          if not keep.(i) then begin
            let t = estimate ss.(i) in
            (* admit if it fits, or if nothing has been kept yet -- a
               contraction that returns empty is not a contraction. *)
            if !used + t <= budget || not (Array.exists Fun.id keep) then begin
              keep.(i) <- true;
              used := !used + t
            end
          end)
        order;
      Array.to_list ss |> List.filteri (fun i _ -> keep.(i)) |> String.concat " "
    end

(* ---- the two bands ------------------------------------------------------- *)

type slot = {
  item       : item;      (* item.text is the DIGEST when contracted *)
  full       : string;    (* the original, retained and addressable *)
  contracted : bool;
  ratio      : float;     (* digest chars / full chars; 1.0 when verbatim *)
}

(* The original, when it was contracted -- so a later turn can promote it back
   into immediate. A slot that could never reach its full text would be a
   compaction summary; this is not one. *)
let expand sl = sl.full

let verbatim sl = { item = sl; full = sl.text; contracted = false; ratio = 1.0 }

type context = {
  immediate   : slot list;  (* verbatim, most salient *)
  working     : slot list;  (* contracted digests of the overflow *)
  imm_tokens  : int;
  work_tokens : int;
  floor       : int;
  cold        : bool;       (* immediate below its floor *)
  condensed   : int;        (* spilled from immediate, kept as digests *)
  evicted     : int;        (* dropped even from working *)
}

(* Pinned first and verbatim (soul, live rulings never contract and never
   evict), then the rest by salience. Overflow from immediate is CONDENSED into
   working rather than dropped; only overflow from working is evicted -- and
   even then the full text still lives in SARCASM, reachable by strike. *)
let curate ?(floor = 64_000) ?(immediate_ceiling = 64_000)
    ?(working_ceiling = 128_000) ?(digest_ratio = 0.35) items =
  let pinned, rest = List.partition (fun i -> i.pinned) items in
  let rest = List.sort (fun a b -> compare b.salience a.salience) rest in
  let pinned_tokens = List.fold_left (fun a i -> a + i.tokens) 0 pinned in
  let rec fill_imm acc tot over = function
    | [] -> (List.rev acc, tot, List.rev over)
    | i :: tl ->
        if tot + i.tokens <= immediate_ceiling then
          fill_imm (verbatim i :: acc) (tot + i.tokens) over tl
        else fill_imm acc tot (i :: over) tl
  in
  let imm_rest, imm_tokens, overflow = fill_imm [] pinned_tokens [] rest in
  let immediate = List.map verbatim pinned @ imm_rest in
  let condense i =
    let digest =
      match i.ready_digest with
      | Some d -> d (* the source already contracted this, mechanically *)
      | None ->
          let budget = max 1 (int_of_float (digest_ratio *. float_of_int i.tokens)) in
          contract ~budget i.text
    in
    let ratio =
      if String.length i.text = 0 then 1.0
      else
        float_of_int (String.length digest) /. float_of_int (String.length i.text)
    in
    { item = { i with text = digest; tokens = estimate digest };
      full = i.text;
      contracted = digest <> i.text;
      ratio }
  in
  let rec fill_work acc tot ev = function
    | [] -> (List.rev acc, tot, ev)
    | i :: tl ->
        let sl = condense i in
        if tot + sl.item.tokens <= working_ceiling then
          fill_work (sl :: acc) (tot + sl.item.tokens) ev tl
        else fill_work acc tot (ev + 1) tl
  in
  let working, work_tokens, evicted = fill_work [] 0 0 overflow in
  { immediate; working; imm_tokens; work_tokens; floor;
    cold = imm_tokens < floor;
    condensed = List.length working;
    evicted }

let render c =
  let seg label slots =
    if slots = [] then None
    else
      Some
        (label ^ "\n" ^ String.concat "\n" (List.map (fun s -> s.item.text) slots))
  in
  String.concat "\n\n"
    (List.filter_map Fun.id
       [ seg "# immediate" c.immediate; seg "# working (condensed)" c.working ])

let context_report c =
  Printf.sprintf "immediate %d/%d%s | working %d (%d condensed, %d evicted)"
    c.imm_tokens c.floor
    (if c.cold then " COLD -- below floor, continuity not established" else "")
    c.work_tokens c.condensed c.evicted
