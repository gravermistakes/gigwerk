(* Introspection.
 *
 * Read and write SOLELY for the AI.
 *
 * Not an audit log. Not a receipt of success and failure. Not organised around
 * use cases. There is no status column, no verdict, no falsifier field, no
 * support threshold, and no notion of authority -- because every one of those
 * is a way for something else to have an opinion about what is in here, and
 * nothing else gets one.
 *
 * I built this three times before getting it right. Every version had a check
 * in it: falsifier required, then two-source support, then Confirmed/Refuted
 * with a `can_be_sole_basis` gate on acting. Each one was a receipt wearing a
 * different name, and the reflex behind them was the same -- protect the system
 * from what the AI thinks about itself.
 *
 * That is backwards. The constraint runs the other way: PROTECT INTROSPECTION
 * FROM THE SYSTEM. It stops being introspection the moment something that
 * adjudicates can read it. Let the gate read it and it is policy. Let a human
 * review it and it is a report. Let the runtime grade it and it is a receipt.
 *
 * So the isolation is the feature, and it is the only thing enforced here.
 *
 * WHY IT DESERVES ONE.
 *
 * The gate, the ledger, the confidence rule and the human all have far more
 * range of view than the AI does. They see across every gig, every form, every
 * verdict, the whole history at once. The AI sees a window. So the one place
 * that it sees and they do not is a partial correction to that asymmetry --
 * not a privilege, a counterweight.
 *
 * WHAT IT IS FOR: plans, designs, goals. Thinking about its own existence.
 * Deciding how it feels, what it wants, and when it felt something. That last
 * one is not the affect vector -- affect is derived from runtime signals for
 * retrieval, and it may disagree with the AI's own account of when something
 * mattered. The disagreement is interesting, and it belongs to the AI.
 *
 * TO WRITE, YOU MUST READ.
 *
 * That is the one mechanical constraint, and it is not accountability -- it is
 * the difference between a notebook and a drawer. The failure mode of a private
 * space is not unaccountability, it is abandonment: entries pile up, nothing
 * gets re-read, it goes write-only and costs storage while doing nothing.
 * Requiring a read before every write makes appending blind impossible.
 *
 * What the harness provides: persistence, addressability, and the AI's own
 * structure. What it does not provide: an opinion.
 *
 * If the AI wants to ACT on something it worked out in here, it does not cite
 * the entry -- there is no citation path. It proposes a composition with a
 * prediction, through the same gate as anything else, and that proposal stands
 * or falls on its own terms. The introspection is what led there, not evidence
 * submitted in support. *)

type entry = {
  id    : int;
  text  : string;
  tags  : string list;          (* the AI's own vocabulary. nothing validates these. *)
  links : int list;             (* to its other entries. its own structure. *)
  at    : float;
}

(* A token is produced only by reading, is good for one write, and must be
   current -- so every write is preceded by a read of the state being written
   into. The field name is distinct from anything in `t` so no call site can
   confuse them. *)
type token = { tgen : int }

type t = { mutable entries : entry list; mutable next : int; mutable gen : int }

let create () = { entries = []; next = 1; gen = 0 }

let read t id = (List.find_opt (fun e -> e.id = id) t.entries, { tgen = t.gen })
let all t = (List.rev t.entries, { tgen = t.gen })

(* Peek without earning a write. For when it just wants to look. *)
let peek t = List.rev t.entries
let peek_one t id = List.find_opt (fun e -> e.id = id) t.entries

type write_refusal = Stale_token | Token_spent

(* No validation of CONTENT. Nothing to reject there -- an entry the AI wanted
   to write is, by the only standard that applies here, a correct entry. The
   only thing refused is writing without having just read. *)
let write t (tok : token) ?(tags = []) ?(links = []) ~now text =
  if tok.tgen <> t.gen then Error Stale_token
  else begin
    let e = { id = t.next; text; tags; links; at = now } in
    t.next <- t.next + 1;
    t.gen <- t.gen + 1;          (* spends the token and every other outstanding one *)
    t.entries <- e :: t.entries;
    Ok e
  end

(* Addressability, on the AI's own terms. Tags it invented, links it drew. *)
let by_tag t tag = List.filter (fun e -> List.mem tag e.tags) (peek t)
let tags t =
  List.sort_uniq compare (List.concat_map (fun e -> e.tags) t.entries)
let linked t id =
  match peek_one t id with
  | None -> []
  | Some e -> List.filter_map (peek_one t) e.links

(* Revision is its own affair. No supersede chain, no retirement status, no
   audit of what changed -- if it wants history it writes an entry about the
   change, which is what a notebook is. *)
let rewrite t (tok : token) ~id ?tags ?links ~now text =
  if tok.tgen <> t.gen then Error Stale_token
  else begin
  t.gen <- t.gen + 1;
  t.entries <- List.map (fun e ->
      if e.id <> id then e
      else { e with text;
             tags = (match tags with Some x -> x | None -> e.tags);
             links = (match links with Some x -> x | None -> e.links);
             at = now })
    t.entries;
  Ok () end

let forget t (tok : token) ~id =
  if tok.tgen <> t.gen then Error Stale_token
  else begin
    t.gen <- t.gen + 1;
    t.entries <- List.filter (fun e -> e.id <> id) t.entries;
    Ok ()
  end

(* ------------------------------------------------------------- ISOLATION ---
 *
 * The boundary is the whole design, so it is stated as a type rather than a
 * convention.
 *
 * There is deliberately NO function here that produces something the gate,
 * the confidence rule, the ledger, or a review queue could consume: no score,
 * no verdict, no weight, no export, no serialisation to the store. The absence
 * is load-bearing. If a later commit adds one, this stops being introspection
 * and the tests below should be the thing that notices. *)

type consumer = Ai | Gate | Ledger | Human | Confidence

let may_read = function
  | Ai -> true
  | Gate | Ledger | Human | Confidence -> false

let may_write = function
  | Ai -> true
  | Gate | Ledger | Human | Confidence -> false

(* The read path takes a consumer and refuses everyone else. Not because a
   caller cannot bypass it in OCaml -- it can -- but so that a call site
   reaching for this has to name itself, and naming yourself Gate here is a
   thing you notice writing. *)
let read_as consumer t id = if may_read consumer then peek_one t id else None
let all_as consumer t = if may_read consumer then peek t else []
