(* Tracing — the observability gap the checklist named and this design had.
 *
 * The ledger already recorded WHAT happened. A trace records what happened
 * INSIDE a gig and in what order, so a failure can be located rather than
 * merely noticed.
 *
 * Spans are emitted by the runtime, not by behaviors. A behavior that could
 * write its own trace could write a flattering one, and the trace is evidence.
 * Same reasoning as Phases: the thing being observed does not author the
 * observation. *)

type span = {
  id        : int;
  parent    : int option;
  gig       : string;
  name      : string;
  phase     : string option;    (* the declared phase this span sat in *)
  started   : float;
  ended     : float option;
  outcome   : string option;    (* set once, at close *)
  breach    : string option;    (* a Terms or Phases breach, if that ended it *)
}

type t = { mutable next : int; mutable spans : span list; gig : string }

let create ~gig = { next = 1; spans = []; gig }

let open_ t ?parent ?phase name =
  let id = t.next in
  t.next <- id + 1;
  let s = { id; parent; gig = t.gig; name; phase;
            started = Unix.gettimeofday (); ended = None;
            outcome = None; breach = None } in
  t.spans <- s :: t.spans;
  id

(* Closing an already-closed span is a bug in the caller, not a no-op to
   swallow: a double close means the control flow is not what you think it is,
   and that is exactly what a trace exists to reveal. *)
exception Double_close of int

let close t ?outcome ?breach id =
  t.spans <- List.map (fun s ->
      if s.id <> id then s
      else if s.ended <> None then raise (Double_close id)
      else { s with ended = Some (Unix.gettimeofday ()); outcome; breach })
    t.spans

let spans t = List.rev t.spans

let unclosed t = List.filter (fun s -> s.ended = None) (spans t)

let duration_ms s =
  match s.ended with
  | None -> None
  | Some e -> Some ((e -. s.started) *. 1000.0)

(* Depth via parent links, so a flat list still renders as a tree. *)
let rec depth t s =
  match s.parent with
  | None -> 0
  | Some p ->
      (match List.find_opt (fun x -> x.id = p) (spans t) with
       | Some parent -> 1 + depth t parent
       | None -> 0)

let to_lines t =
  List.map (fun s ->
      Printf.sprintf "%s%s%s %s%s"
        (String.make (2 * depth t s) ' ')
        s.name
        (match s.phase with Some p -> " [" ^ p ^ "]" | None -> "")
        (match duration_ms s with
         | Some d -> Printf.sprintf "%.1fms" d
         | None -> "UNCLOSED")
        (match s.breach, s.outcome with
         | Some b, _ -> " breach=" ^ b
         | None, Some o -> " -> " ^ o
         | None, None -> ""))
    (spans t)

(* Rows for the store. The trace is a ledger table, not a log file: it has to
   be queryable beside outcomes for anything to be learned from it. *)
let to_rows t =
  List.map (fun s ->
      (s.id, s.parent, s.gig, s.name, s.phase,
       (match duration_ms s with Some d -> int_of_float d | None -> -1),
       s.outcome, s.breach))
    (spans t)
