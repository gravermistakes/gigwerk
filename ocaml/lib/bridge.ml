(* Bridge -- the only door from OCaml into the two external reasoners.
 *
 * Two engines exist and, before this file, nothing in OCaml could reach them:
 * elpi/gate.elpi decides book/queue/refuse over a composition's structure,
 * and prolog/confidence.pl decides which of three review bands a form has
 * earned. Both are read-only from here. This file generates their INPUT
 * (facts, plus a driver goal), shells out, and parses their stdout back into
 * a typed OCaml value. It does not re-implement either engine's logic: that
 * is the whole reason it exists rather than calling Conditions.evaluate and
 * calling it done. Conditions.ml is a local, OCaml-native approximation of
 * the gate, and an approximation is not the same program as the one that
 * actually runs -- see the note by `apply_adversarial_tie` below for one
 * place the two are already known to disagree, and the final report for the
 * rest.
 *
 * Every public function returns `result`, carries the engine's stderr in the
 * error, and never raises. A shelled-out reasoner can be absent, broken, or
 * newly wrong in a way nothing here has seen yet, and an uncaught exception
 * from a booking-path function is a crash in a path a human is relying on to
 * fail SAFE -- not a crash that conveniently skips the safety check. *)

(* ============================================================================
 * Shared plumbing: shelling out and getting a typed result back.
 * ========================================================================= *)

type engine_error =
  | Engine_missing of { binary : string; stderr : string }
  (* the shell could not exec `binary` at all: not installed, or the path we
     were given (default or override) does not resolve to anything runnable *)
  | Engine_failed of { binary : string; exit_code : int; stdout : string; stderr : string }
  (* `binary` ran and objected: bad facts, a real refusal to even try, a crash *)
  | Bad_output of { binary : string; stdout : string; stderr : string; why : string }
  (* `binary` exited 0 and we still could not make sense of what it printed --
     the most dangerous case, because "ran fine" is what a caller expects to
     be able to trust *)

let engine_error_to_string = function
  | Engine_missing { binary; stderr } ->
      Printf.sprintf "%s is not available%s" binary
        (if String.trim stderr = "" then "" else ": " ^ String.trim stderr)
  | Engine_failed { binary; exit_code; stdout; stderr } ->
      Printf.sprintf "%s exited %d\nstdout: %s\nstderr: %s"
        binary exit_code (String.trim stdout) (String.trim stderr)
  | Bad_output { binary; why; stdout; stderr } ->
      Printf.sprintf "%s produced output we could not parse (%s)\nstdout: %s\nstderr: %s"
        binary why (String.trim stdout) (String.trim stderr)

(* Read stdout and stderr concurrently until both hit EOF, instead of draining
   one fully before touching the other. elpi writes real diagnostic text to
   stderr on EVERY invocation, success included (confirmed by hand: a clean
   `elpi ... -exec main -- good` still emits "Parsing time:", "Compilation
   time:", etc. on stderr) -- so a "read all of stdout, then read all of
   stderr" implementation is one large fact file away from deadlocking: the
   child blocks writing to a full stderr pipe while we are still blocked
   waiting for stdout to end. Unix.select drains whichever side has data the
   moment it is ready, so neither pipe can back the other up. *)
let read_both (out_ic : in_channel) (err_ic : in_channel) : string * string =
  let out_fd = Unix.descr_of_in_channel out_ic in
  let err_fd = Unix.descr_of_in_channel err_ic in
  let out_buf = Buffer.create 1024 and err_buf = Buffer.create 1024 in
  let out_done = ref false and err_done = ref false in
  let chunk = Bytes.create 4096 in
  while not (!out_done && !err_done) do
    let watch =
      (if !out_done then [] else [ out_fd ]) @ (if !err_done then [] else [ err_fd ])
    in
    (* Negative timeout = block until at least one fd is ready (verified by
       hand against a child that sleeps before writing: select waited for the
       full delay rather than busy-looping or returning empty immediately). *)
    let ready, _, _ = Unix.select watch [] [] (-1.0) in
    List.iter
      (fun fd ->
        let n = Unix.read fd chunk 0 (Bytes.length chunk) in
        if n = 0 then (if fd = out_fd then out_done := true else err_done := true)
        else Buffer.add_subbytes (if fd = out_fd then out_buf else err_buf) chunk 0 n)
      ready
  done;
  (Buffer.contents out_buf, Buffer.contents err_buf)

let exit_code_of = function
  | Unix.WEXITED n -> n
  | Unix.WSIGNALED n -> 128 + n (* shell convention; only used for reporting *)
  | Unix.WSTOPPED n -> 128 + n

(* Run `binary args...`, capturing stdout/stderr separately and classifying
   the result. 127 is the POSIX shell's own "command not found" exit code
   (confirmed here: both `/nonexistent/elpi ...` and `/nonexistent/swipl ...`
   come back WEXITED 127 with the shell's own "No such file or directory" on
   stderr) -- that is what distinguishes an absent engine from one that ran
   and objected, without needing to pre-check PATH ourselves. *)
let invoke ~binary (args : string list) : (string * string, engine_error) result =
  let cmd = String.concat " " (List.map Filename.quote (binary :: args)) in
  match
    (* open_process_full spawns /bin/sh, which always exists; a missing
       engine binary shows up as the shell's own exit 127 below, not an
       OCaml exception. We still guard the call itself because fork/exec can
       fail for reasons that have nothing to do with which engine we asked
       for (fd exhaustion, ENOMEM under load), and those must not raise
       either. *)
    (try Ok (Unix.open_process_full cmd (Unix.environment ()))
     with Unix.Unix_error (err, fn, _) -> Error (fn, Unix.error_message err))
  with
  | Error (fn, msg) ->
      Error (Engine_missing { binary; stderr = Printf.sprintf "%s: %s" fn msg })
  | Ok (out_ic, in_oc, err_ic) ->
      (* We never write to the child's stdin. Closing our end immediately
         means an engine that unexpectedly waits for input (a driver-goal bug
         that leaves swipl short of its own `halt`, say) hits EOF at once
         instead of hanging this call forever -- verified: SWI's toplevel
         reads EOF-on-stdin as `end_of_file.` and halts rather than blocking. *)
      close_out_noerr in_oc;
      let stdout_s, stderr_s = read_both out_ic err_ic in
      let status = Unix.close_process_full (out_ic, in_oc, err_ic) in
      (match exit_code_of status with
      | 0 -> Ok (stdout_s, stderr_s)
      | 127 -> Error (Engine_missing { binary; stderr = stderr_s })
      | n -> Error (Engine_failed { binary; exit_code = n; stdout = stdout_s; stderr = stderr_s }))

(* Write `contents` to a fresh temp file, hand its path to `f`, and remove it
   afterwards either way. A leaked temp file on every gate call would quietly
   fill /tmp on a long-running booker; deleting in `finally` means a parse
   error or an exception from `f` still cleans up. *)
let with_temp_file ~prefix ~suffix contents (f : string -> 'a) : 'a =
  let path = Filename.temp_file prefix suffix in
  Fun.protect
    ~finally:(fun () -> try Sys.remove path with Sys_error _ -> ())
    (fun () ->
      let oc = open_out path in
      Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () -> output_string oc contents);
      f path)

(* elpi's `accumulate` directive appends ".elpi" itself -- accumulating a path
   that already ends in ".elpi" makes it look for "gate.elpi.elpi" and fail
   (confirmed by hand). Every path we hand to `accumulate` has to go through
   this first. *)
let without_elpi_ext path =
  if Filename.check_suffix path ".elpi" then Filename.chop_suffix path ".elpi" else path

(* Where gate.elpi and confidence.pl live, as siblings of ocaml/ under the
   project root. `Sys.getcwd ()` cannot be trusted for this: `dune test` runs
   from _build/default/test (confirmed by hand), `dune exec` runs from
   wherever it was invoked, and a caller could run the built binary from
   anywhere. `Sys.executable_name` is always right, because dune always
   places build output under <project_root>/ocaml/_build/default/... --
   walking back from the running binary's own resolved path (which is what
   Sys.executable_name gives on Linux, not a possibly-relative argv[0], also
   confirmed by hand) finds the project root regardless of who invoked it. *)
let project_root () =
  let exe = Sys.executable_name in
  let marker = "/_build/" in
  let mlen = String.length marker and elen = String.length exe in
  let rec find i =
    if i + mlen > elen then None
    else if String.sub exe i mlen = marker then Some (String.sub exe 0 i)
    else find (i + 1)
  in
  find 0

(* Falls back to this container's known checkout path if the executable is
   ever run from outside a dune build tree (a toplevel, say). This bridge is
   internal to one project layout, not a portable library, so a fixed
   fallback here is honest rather than a hack. *)
let default_gate_file () =
  match project_root () with
  | Some ocaml_root -> Filename.concat (Filename.dirname ocaml_root) "elpi/gate.elpi"
  | None -> "/home/claude/gigwerk/elpi/gate.elpi"

let default_confidence_file () =
  match project_root () with
  | Some ocaml_root -> Filename.concat (Filename.dirname ocaml_root) "prolog/confidence.pl"
  | None -> "/home/claude/gigwerk/prolog/confidence.pl"

(* ============================================================================
 * The booking gate (elpi/gate.elpi).
 * ========================================================================= *)

type tier = In_process | Subprocess
type provenance = Human | Agent

(* Mirrors gate.elpi's `ty` exactly: tunit/tstring/tint/tlist/tpair/tarrow.
   Named after the elpi constructors themselves (not e.g. `List`/`Pair`) so a
   reviewer can check this against gate.elpi's `kind ty type` block by eye
   without a translation table. *)
type shape = Tunit | Tstring | Tint | Tlist of shape | Tpair of shape * shape | Tarrow of shape * shape

(* The global capability registry: sql/schema.sql's `capability` table, name
   for name (name, ctor, envelope, side_effecting, requires_booking). This is
   NOT part of a composition -- it is the fixed catalog every composition's
   claims are checked against, shared across every entity, which is exactly
   why gate.elpi's own `system_owns`-style facts and this catalog are supplied
   once per call rather than duplicated onto each claim. Do not confuse this
   with Caps.fs_read and friends: those are constructed OCaml values that
   exist only for a claim that has already passed this gate. *)
type capability = {
  name : string;
  ctor : string;
  envelope : string; (* "/"-delimited; segmented the same way as claim scopes *)
  side_effecting : bool;
  requires_booking : bool;
}

type composition = {
  entity : string;
  (* (capability name, scope) pairs -- the exact shape Store.claims already
     returns, so a caller holding `Store.claims ~entity` can pass it straight
     through without reshaping it. *)
  claims : (string * string) list;
  (* Prolog/elpi predicate names (sql/schema.sql's c_policy.predicate), carried
     because policy_set is part of a composition's identity everywhere else in
     this system (the `form` table's signature folds it in). gate.elpi has no
     `policy` fact or check today (grep the file: there is none), so nothing
     here is emitted as a fact -- this field is inert until a policy-aware
     check exists to read it. *)
  policies : string list;
  state_shape : shape;
  provenance : provenance;
  tier : tier;
  human_verdict : bool; (* an approval row exists for this entity *)
  previously_refused : bool; (* this composition shape is in the dead set *)
  (* The adversarial judge's weight, per Conditions.evidence. gate.elpi has no
     fact or check for these either -- the tie-break they feed is applied by
     this module after elpi decides, see `apply_adversarial_tie`. *)
  support_strength : int;
  refutation_strength : int;
}

(* A convenience base, one field short of gate.elpi's own trivial-accept case
   (see the report: an entity with no claim/provenance facts at all books by
   default). Mirrors Conditions.clean's role: override the fields a test
   cares about rather than restating all ten every time. *)
let clean_composition =
  {
    entity = "";
    claims = [];
    policies = [];
    state_shape = Tunit;
    provenance = Human;
    tier = In_process;
    human_verdict = false;
    previously_refused = false;
    support_strength = 1;
    refutation_strength = 0;
  }

type decision = Book | Queue | Refuse

let decision_to_string = function Book -> "book" | Queue -> "queue" | Refuse -> "refuse"

type gate_result = { decision : decision; reasons : string list }

(* The decision a caller should treat an Error from `gate` as, when a booking
   still has to be decided one way or the other and the gate could not run.
   Refuse, not queue -- and this is deliberately not the reflexively
   "safe-sounding" pick, because queue has a real argument for it: queueing
   keeps a human in the loop rather than dead-ending every booking during an
   elpi outage, and "we could not check" sounds more like "ask a person"
   (queue) than "this is definitely bad" (refuse, which Conditions.ml reserves
   for compositions "no human decision changes"). But queue is not merely
   "ask a person" in this system -- every OTHER queued item has already
   passed checks 1-4: its scope is confirmed to narrow its envelope, its
   capabilities are confirmed to exist, its shape is confirmed well-formed.
   Routing an engine outage into the same queue hands a human reviewer
   something that looks exactly like a normal procedural item, with nothing
   marking the one difference that matters: none of the structural safety
   checks ran at all. A reviewer who approves it as "just another queue item"
   is approving a possibly-widened, possibly-nonexistent capability without
   knowing that is what they are doing -- which launders "unverified" into
   "reviewed" and is worse than refusing outright. Refuse costs availability
   during an outage; it never misrepresents what happened. It also matches
   the one precedent this codebase already has for uncertainty in this exact
   spot: Conditions.evaluate's adversarial tie also refuses rather than
   passing the question along. *)
let gate_fail_safe = Refuse

(* Split a "/"-delimited scope or envelope into the segment list gate.elpi's
   `narrows` expects. THIS MUST HAPPEN HERE, NOT IN THE GATE: elpi only ever
   sees the segments we hand it, so if this function is wrong the gate cannot
   catch it downstream. It is also the exact fix for the bug elpi/README.md
   documents: a CHARACTER-level or unsplit comparison lets "/srv/gigwerk-evil"
   match as a "prefix" of "/srv/gigwerk", because the characters "srv/gigwerk"
   really are a run at the front of both strings; only a SEGMENT-level split
   makes "gigwerk-evil" and "gigwerk" two distinct, non-unifying atoms so
   `prefix_of` in gate.elpi can tell them apart. (Verified by mutation: see
   the final report -- exploding the path into single characters instead of
   segments flips the "sneaky" end-to-end test from refuse to book.) Empty
   segments are dropped so a leading "/", a trailing "/", or "//" all collapse
   the same way on both sides of every comparison. *)
let segments_of_path s = String.split_on_char '/' s |> List.filter (fun seg -> seg <> "")

(* Escape a string for an elpi "..." literal. Facts are generated text that
   elpi re-parses as code: an unescaped double-quote character in an entity
   name, capability name, or scope segment would close the literal early,
   and whatever follows
   -- bug- or attacker-supplied -- would be parsed as elpi syntax instead of
   inert data. Same class of bug as string-built SQL; same shape of fix.
   The three escapes below were each verified against the real elpi binary:
   a quote, a backslash, and a newline all round-trip through `print`
   unchanged. *)
let elpi_string s =
  let buf = Buffer.create (String.length s + 2) in
  Buffer.add_char buf '"';
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string buf "\\\""
      | '\\' -> Buffer.add_string buf "\\\\"
      | '\n' -> Buffer.add_string buf "\\n"
      | '\r' -> Buffer.add_string buf "\\r"
      | c -> Buffer.add_char buf c)
    s;
  Buffer.add_char buf '"';
  Buffer.contents buf

let elpi_string_list segs = "[" ^ String.concat "," (List.map elpi_string segs) ^ "]"
let elpi_bool b = if b then "tt" else "ff"

(* A compound shape used as an argument must be parenthesised (juxtaposition
   is application, so a bare `tlist X` sitting in an argument slot would
   misparse as two separate arguments to whatever it sits inside); an atomic
   shape (tunit/tstring/tint) never needs parens. Verified against
   facts_test2.elpi's own fixture: `tarrow tunit (tlist (tarrow tstring
   tint))` is exactly what this produces for the equivalent OCaml shape. *)
let rec elpi_shape = function
  | Tunit -> "tunit"
  | Tstring -> "tstring"
  | Tint -> "tint"
  | Tlist s -> "tlist " ^ elpi_shape_arg s
  | Tpair (a, b) -> "tpair " ^ elpi_shape_arg a ^ " " ^ elpi_shape_arg b
  | Tarrow (a, b) -> "tarrow " ^ elpi_shape_arg a ^ " " ^ elpi_shape_arg b

and elpi_shape_arg = function
  | (Tunit | Tstring | Tint) as s -> elpi_shape s
  | s -> "(" ^ elpi_shape s ^ ")"

let provenance_word = function Human -> "human" | Agent -> "agent"
let tier_word = function In_process -> "in_process" | Subprocess -> "subprocess"

(* Generate the elpi facts for one composition, against the given catalog.
   Order does not affect gate.elpi's checks (each looks up an exact claim,
   entity, or capability name; a composition should never carry two claims on
   the same capability, mirroring c_capability's own primary key), so this
   just emits them in the order it was given them. *)
let gate_facts ~capabilities (c : composition) : string =
  let buf = Buffer.create 512 in
  let line s = Buffer.add_string buf s; Buffer.add_char buf '\n' in
  List.iter
    (fun (cap : capability) ->
      line
        (Printf.sprintf "capability %s %s %s %s %s." (elpi_string cap.name) (elpi_string cap.ctor)
           (elpi_string_list (segments_of_path cap.envelope))
           (elpi_bool cap.side_effecting) (elpi_bool cap.requires_booking)))
    capabilities;
  List.iter
    (fun (cap_name, scope) ->
      line
        (Printf.sprintf "claim %s %s %s." (elpi_string c.entity) (elpi_string cap_name)
           (elpi_string_list (segments_of_path scope))))
    c.claims;
  line (Printf.sprintf "provenance %s %s." (elpi_string c.entity) (elpi_string (provenance_word c.provenance)));
  line (Printf.sprintf "tier %s %s." (elpi_string c.entity) (elpi_string (tier_word c.tier)));
  line (Printf.sprintf "state_shape %s %s." (elpi_string c.entity) (elpi_shape_arg c.state_shape));
  if c.human_verdict then line (Printf.sprintf "human_verdict %s." (elpi_string c.entity));
  if c.previously_refused then line (Printf.sprintf "refused %s." (elpi_string c.entity));
  Buffer.contents buf

(* The driver elpi/README.md's own run_test.elpi already demonstrates:
   `accumulate gate. accumulate facts_test.` This is the same shape, generated
   instead of hand-written, with absolute (quoted) paths so it works
   regardless of the caller's cwd -- the same reason `default_gate_file`
   cannot rely on cwd either. *)
let gate_driver ~gate_file ~facts_file =
  Printf.sprintf "accumulate %s.\naccumulate %s.\n"
    (elpi_string (without_elpi_ext gate_file))
    (elpi_string (without_elpi_ext facts_file))

let gate_decision_prefix = "decision: "
let gate_reason_prefix = "  reason: "

(* Parses gate.elpi's `main` output EXACTLY as observed by hand:
     decision: book
   or
     decision: refuse
       reason: scope widens envelope for fs_read
   (one line, then zero or more two-space-indented reason lines -- confirmed
   against a real run for every case in elpi/README.md's table, byte-checked
   with `cat -A` for exact spacing). Anything else is Bad_output rather than
   a best-effort guess: a parser that shrugs at unrecognised output is how a
   permissive answer sneaks past the "never silently permissive" rule. *)
let parse_gate_output (stdout : string) : (decision * string list, string) result =
  let lines = String.split_on_char '\n' stdout |> List.filter (fun l -> l <> "") in
  match lines with
  | [] -> Error "empty stdout (expected a \"decision: \" line)"
  | first :: rest ->
      if not (String.starts_with ~prefix:gate_decision_prefix first) then
        Error (Printf.sprintf "first line %S does not start with %S" first gate_decision_prefix)
      else
        let word =
          String.sub first
            (String.length gate_decision_prefix)
            (String.length first - String.length gate_decision_prefix)
        in
        let decision =
          match word with
          | "book" -> Some Book
          | "queue" -> Some Queue
          | "refuse" -> Some Refuse
          | _ -> None
        in
        (match decision with
        | None -> Error (Printf.sprintf "unrecognised decision word %S" word)
        | Some decision ->
            let rec reasons_of acc = function
              | [] -> Ok (List.rev acc)
              | l :: tl ->
                  if String.starts_with ~prefix:gate_reason_prefix l then
                    let r =
                      String.sub l
                        (String.length gate_reason_prefix)
                        (String.length l - String.length gate_reason_prefix)
                    in
                    reasons_of (r :: acc) tl
                  else Error (Printf.sprintf "unexpected line %S where a reason was expected" l)
            in
            (match reasons_of [] rest with
            | Error e -> Error e
            | Ok reasons -> Ok (decision, reasons)))

(* gate.elpi resolves checks 1-7 into book/queue/refuse; it has no fact or
   check for the adversarial judge's numeric weight (grep confirms no
   support/refutation predicate exists there). Conditions.evaluate runs that
   tie-break AFTER its structural checks and BEFORE its procedural ones
   (structural refuse beats the tie; the tie beats queue/book), so this
   reproduces the same ordering on top of elpi's answer: an elpi REFUSE is
   left untouched (it is already the strongest verdict, and a support count
   overturning a hard structural refusal would be exactly the "silently
   permissive" outcome the error discipline above forbids), while an elpi
   BOOK or QUEUE can still be escalated to refuse by a tie. It can only ever
   escalate, never downgrade.
     NOTE for whoever reconciles the two engines later: this is not a no-op
   port. gate.elpi's own `hard` predicate treats "composition previously
   refused" (check 7) as QUEUE-worthy -- soft, a human can resolve it -- while
   Conditions.ml's `structural_failures` treats the equivalent flag
   (not_refused_before) as a hard REFUSE. And Conditions.ml refuses on
   `no_composer_grants`, a check gate.elpi does not have at all. The two rule
   sets agree on the shape of the problem and disagree on these specifics;
   this bridge defers to gate.elpi's own classification because that is the
   engine actually running, and does not try to paper over the difference. *)
let apply_adversarial_tie (c : composition) (decision, reasons) =
  match decision with
  | Refuse -> { decision = Refuse; reasons }
  | (Book | Queue) as d ->
      if c.refutation_strength >= c.support_strength && c.refutation_strength > 0 then
        { decision = Refuse; reasons = reasons @ [ "refutation_at_least_as_strong_as_support" ] }
      else { decision = d; reasons }

let gate ?(elpi_bin = "elpi") ?gate_file ~capabilities (c : composition) :
    (gate_result, engine_error) result =
  let gate_file = match gate_file with Some f -> f | None -> default_gate_file () in
  let facts_text = gate_facts ~capabilities c in
  with_temp_file ~prefix:"gigwerk_bridge_facts_" ~suffix:".elpi" facts_text (fun facts_path ->
      let driver_text = gate_driver ~gate_file ~facts_file:facts_path in
      with_temp_file ~prefix:"gigwerk_bridge_driver_" ~suffix:".elpi" driver_text (fun driver_path ->
          match invoke ~binary:elpi_bin [ driver_path; "-exec"; "main"; "--"; c.entity ] with
          | Error e -> Error e
          | Ok (stdout_s, stderr_s) -> (
              match parse_gate_output stdout_s with
              | Error why -> Error (Bad_output { binary = elpi_bin; stdout = stdout_s; stderr = stderr_s; why })
              | Ok parsed -> Ok (apply_adversarial_tie c parsed))))

(* ============================================================================
 * Confidence bands (prolog/confidence.pl).
 * ========================================================================= *)

type prediction = Held | Partial | Not_held

type review = {
  form_sig : string;
  prediction : prediction;
  critic_passed : bool;
  judge_refuted : bool;
  at : int; (* unix seconds; sort key only, native int is ample precision *)
}

type band = A_autopass | B_last_review | C_needs_review

let band_to_string = function
  | A_autopass -> "a_autopass"
  | B_last_review -> "b_last_review"
  | C_needs_review -> "c_needs_review"

type confidence_result = { band : band; certainty : float }

(* The fail-safe for an unreachable confidence engine. Unlike the gate's, this
   one has an obvious answer: A_autopass is not merely "the more permissive
   choice", it is a claim confidence.pl documents as qualitative -- "nothing
   has gone wrong recently" over a real, measured, clean 15-review window
   (see confidence.pl's own comment on `band/3`). Manufacturing that claim
   because swipl is unreachable is not an approximation of the truth, it is
   asserting a track record that was never measured -- there is no reading of
   "we could not ask" that honestly means "and the answer is a clean record".
   C_needs_review is the only value that does not fabricate evidence, which is
   exactly what the error discipline above forbids doing. *)
let confidence_fail_safe = C_needs_review

(* Escape a string for a single-quoted Prolog atom: '' or \' for an embedded
   quote (confirmed both work; \' is used here since it composes with the
   other backslash escapes below without a separate doubling pass), \\ for a
   literal backslash, \n for a newline so a raw newline in form_sig can never
   terminate the atom early and start a new clause. Verified against the real
   swipl binary: consulting the escaped atom and reading it back with writeq/1
   reproduces the original bytes exactly. *)
let pl_atom s =
  let buf = Buffer.create (String.length s + 2) in
  Buffer.add_char buf '\'';
  String.iter
    (fun c ->
      match c with
      | '\'' -> Buffer.add_string buf "\\'"
      | '\\' -> Buffer.add_string buf "\\\\"
      | '\n' -> Buffer.add_string buf "\\n"
      | '\r' -> Buffer.add_string buf "\\r"
      | c -> Buffer.add_char buf c)
    s;
  Buffer.add_char buf '\'';
  Buffer.contents buf

let pl_bit b = if b then "1" else "0"
let pl_prediction = function Held -> "yes" | Partial -> "partial" | Not_held -> "no"

(* review(FormSig, PredictionHeld, CriticPassed, JudgeRefuted, At) -- the exact
   arity and argument domains from confidence.pl's own header comment. Loaded
   into a plain file with no `:- module` of its own, which lands its clauses
   in `user` (confirmed by hand) -- exactly where confidence.pl already
   expects fact dumps to land ("fact dumps consult into user, so read from
   there"). *)
let confidence_facts (reviews : review list) : string =
  let buf = Buffer.create 256 in
  List.iter
    (fun r ->
      Buffer.add_string buf
        (Printf.sprintf "review(%s, %s, %s, %s, %d).\n" (pl_atom r.form_sig)
           (pl_prediction r.prediction) (pl_bit r.critic_passed) (pl_bit r.judge_refuted) r.at))
    reviews;
  Buffer.contents buf

(* band/3 has no CLI reporter of its own (unlike gate.elpi's `main`), so this
   goal is entirely ours to define -- verified by hand against the real
   swipl binary rather than assumed, same as everything else here.
     One real gap in confidence.pl this goal has to paper over: band/3 calls
   certainty/2 unconditionally before checking whether the window has even
   filled, and certainty/2's lifetime_rate/window_rate both hard-require
   N > 0 reviews. A form with ZERO reviews therefore makes band/3 FAIL
   outright rather than report c_needs_review (confirmed by hand: consulting
   an empty facts file and calling confidence:band('nosig', B, C) fails with
   no solution, it does not bind C_needs_review). A brand-new, review-less
   form is unambiguously cold start, so the `->` here supplies exactly the
   band/certainty confidence.pl's own documentation says an unfilled window
   should produce, rather than surfacing a plain goal failure to OCaml as if
   it were something unexpected. This is a workaround in code we generate,
   not a patch to confidence.pl itself, which stays untouched. *)
let confidence_goal ~confidence_file ~facts_file ~form_sig =
  Printf.sprintf
    "consult(%s), consult(%s), ( confidence:band(%s, Band, C) -> true ; Band = c_needs_review, C \
     = 0.0 ), format(\"band:~w~ncertainty:~4f~n\", [Band, C]), halt"
    (pl_atom facts_file) (pl_atom confidence_file) (pl_atom form_sig)

let band_of_string = function
  | "a_autopass" -> Some A_autopass
  | "b_last_review" -> Some B_last_review
  | "c_needs_review" -> Some C_needs_review
  | _ -> None

(* Parses exactly the two lines `confidence_goal` above asks swipl to print:
     band:a_autopass
     certainty:1.0000
   (byte-checked with `cat -A` against a real run). Anything else -- a
   different line count, an unrecognised band atom, a certainty that will
   not parse as a float -- is Bad_output, not a best guess. *)
let parse_confidence_output (stdout : string) : (confidence_result, string) result =
  let lines = String.split_on_char '\n' stdout |> List.filter (fun l -> l <> "") in
  match lines with
  | [ band_line; cert_line ] ->
      let bp = "band:" and cp = "certainty:" in
      if not (String.starts_with ~prefix:bp band_line) then
        Error (Printf.sprintf "first line %S does not start with %S" band_line bp)
      else if not (String.starts_with ~prefix:cp cert_line) then
        Error (Printf.sprintf "second line %S does not start with %S" cert_line cp)
      else
        let bw = String.sub band_line (String.length bp) (String.length band_line - String.length bp) in
        let cw = String.sub cert_line (String.length cp) (String.length cert_line - String.length cp) in
        (match (band_of_string bw, float_of_string_opt cw) with
        | Some band, Some certainty -> Ok { band; certainty }
        | None, _ -> Error (Printf.sprintf "unrecognised band %S" bw)
        | _, None -> Error (Printf.sprintf "unparseable certainty %S" cw))
  | other -> Error (Printf.sprintf "expected exactly 2 lines, got %d" (List.length other))

let confidence ?(swipl_bin = "swipl") ?confidence_file ~form_sig (reviews : review list) :
    (confidence_result, engine_error) result =
  let confidence_file = match confidence_file with Some f -> f | None -> default_confidence_file () in
  let facts_text = confidence_facts reviews in
  with_temp_file ~prefix:"gigwerk_bridge_reviews_" ~suffix:".pl" facts_text (fun facts_path ->
      let goal = confidence_goal ~confidence_file ~facts_file:facts_path ~form_sig in
      match invoke ~binary:swipl_bin [ "-q"; "-g"; goal; "-t"; "halt" ] with
      | Error e -> Error e
      | Ok (stdout_s, stderr_s) ->
          if String.trim stderr_s <> "" then
            (* Unlike elpi, a clean run of THIS EXACT file pairing never
               writes to stderr (verified by hand). But swipl's `consult` is
               lenient about a syntax error in the facts we generate: it logs
               to stderr, silently drops the broken clause and everything
               after it up to the point it resynchronises, and still exits 0
               with a plausible-looking band and certainty computed from
               whatever partial data survived (reproduced by hand: an
               unterminated quote two facts in left exactly one review fact
               loaded, and the run still exited 0 with a coherent-looking
               c_needs_review/0.0667). Exit code alone cannot catch that, so
               any stderr output at all -- even on exit 0 -- is treated as
               untrustworthy stdout rather than a fact we get to ignore. *)
            Error
              (Bad_output
                 {
                   binary = swipl_bin;
                   stdout = stdout_s;
                   stderr = stderr_s;
                   why =
                     "swipl wrote to stderr on an otherwise-zero exit; a clean run of this exact \
                      file pairing never does, so this means consult silently dropped or \
                      mis-parsed a fact rather than raising -- the stdout next to it cannot be \
                      trusted even where it happens to parse";
                 })
          else (
            match parse_confidence_output stdout_s with
            | Error why -> Error (Bad_output { binary = swipl_bin; stdout = stdout_s; stderr = stderr_s; why })
            | Ok r -> Ok r))
