(* Actor behaviors. Deterministic code. No model call anywhere below this line.
 *
 * Each behavior declares its capability requirements IN ITS TYPE. That is where
 * the ocap guarantee bites at compile time: `critic` cannot be applied without
 * an fs_read, and `echo` has no way to name one. Handing `echo_caps` to
 * `critic` is a type error, not a runtime refusal. *)

(* Observation contract.
 *
 * status + summary + actionable follow-up + resource id, per the
 * agent-harness-construction constraint that an observation which reports a
 * failure without a next step forces the reader to re-derive one.
 *
 * `follow_up` is the field that keeps this honest: a verdict that cannot name
 * what to do next is usually a verdict that did not understand what went
 * wrong. `resource` names WHAT was examined, so a verdict is traceable to an
 * input rather than floating free. *)
type verdict = {
  ok        : bool;
  reason    : string;   (* stable machine-readable slug, not prose *)
  detail    : string;   (* the summary a human reads *)
  follow_up : string;   (* the next action. "" only when ok and nothing follows *)
  resource  : string;   (* what was examined *)
}

let verdict_to_string v =
  Printf.sprintf "%s|%s|%s|%s|%s"
    (if v.ok then "pass" else "fail") v.reason v.detail v.follow_up v.resource

(* A failing verdict with no follow-up is a bug in the behavior, not a
   legitimate state. Checked, not documented. *)
let verdict_wellformed v =
  v.reason <> "" && (v.ok || v.follow_up <> "")

(* ------------------------------------------------------------------ echo
   Zero capabilities. The only actor for which an empty record is correct.
   Proves delivery -> step -> outcome without any tool in the path. *)

type echo_caps = unit

let echo (() : echo_caps) ~msg =
  { ok = true; reason = "echoed"; detail = msg;
    follow_up = ""; resource = "inbox" }

(* ---------------------------------------------------------------- critic
   Reads an artifact, emits a deterministic verdict. Cheap, repeatable, and
   trustworthy in a way a model's judgement is not: a failing critic means
   something is actually wrong, every time. *)

type critic_caps = { root : Caps.fs_read; ledger : Caps.sqlite_ro }

let critic (c : critic_caps) ~artifact =
  match Caps.read c.root artifact with
  | exception Failure e ->
      { ok = false; reason = "unreadable"; detail = e;
        follow_up = "confirm the path is beneath the capability root, then reissue";
        resource = artifact }
  | contents ->
      let lines = String.split_on_char '\n' contents in
      let n = List.length lines in
      let empty = String.trim contents = "" in
      let balanced =
        let d = ref 0 and bad = ref false in
        String.iter (fun ch ->
            if ch = '(' then incr d
            else if ch = ')' then (decr d; if !d < 0 then bad := true)) contents;
        (not !bad) && !d = 0
      in
      if empty then
        { ok = false; reason = "empty_artifact"; detail = "0 bytes of content";
          follow_up = "the producing gig emitted nothing -- inspect it, not this artifact";
          resource = artifact }
      else if not balanced then
        { ok = false; reason = "unbalanced_parens";
          detail = "artifact does not close its groups";
          follow_up = "balance the groups and resubmit; this check is positional";
          resource = artifact }
      else
        { ok = true; reason = "checks_passed";
          detail = Printf.sprintf "%d lines, balanced, db=%s" n (Caps.sqlite_db c.ledger);
          follow_up = ""; resource = artifact }

(* ------------------------------------------------------------- phase steps
 *
 * Phase emission lives HERE, beside the behavior, because phases.ml's ladders
 * are declared beside the code that reaches them and for the same reason: a
 * caller that got to choose the phase name could choose the terminal one. The
 * booker reads what comes back off the pipe and decides what it counts as; the
 * behavior only reports where it actually got to.
 *
 * `None` is not a failure signal -- it is the absence of a completed step. A
 * critic that could not read the artifact never completed `read`, so it names
 * no phase at all. That is different from naming a phase outside the ladder,
 * which is a breach, and the two must not collapse: one is a behavior that hit
 * a wall, the other is a behavior whose report cannot be trusted. *)

let echo_step (() : echo_caps) ~msg =
  (Some "echoed", verdict_to_string (echo () ~msg))

let critic_step (c : critic_caps) ~artifact =
  let v = critic c ~artifact in
  (* Every other reason means the artifact WAS read and a verdict was reached,
     including the reasons that say the artifact is bad. A verdict of "this is
     broken" is the critic doing its job. *)
  let phase = if v.reason = "unreadable" then None else Some "verdict_emitted" in
  (phase, verdict_to_string v)
