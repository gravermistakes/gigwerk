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
}

(* ~4 chars per token. Wrong in the third digit, right in the first, and the
   decision it feeds is "have we reached the floor", not billing. *)
let estimate text = (String.length text + 3) / 4

let item ?(pinned = false) ?(salience = 0.0) text =
  { text; tokens = estimate text; pinned; salience }

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
