(* The labor tier.
 *
 * A gig runs in a forked child. The parent survives whatever the child does,
 * which is the boundary that every earlier draft of this design lost to its own
 * capability layer -- a Python AST walk defeated by eval, a Lua _ENV defeated
 * by FFI. Here the frozen core is an address-space boundary.
 *
 * The capability dirfd is opened BEFORE the fork, so the child inherits it.
 * That is the whole answer to "can ocap cross a process boundary": for fork it
 * crosses by inheritance, no SCM_RIGHTS needed. (For exec it would not -- the
 * fd is O_CLOEXEC. Passing capabilities across exec needs SCM_RIGHTS or
 * re-derivation under Landlock, and that is a Phase 2 question.) *)

type outcome =
  | Completed of string
  | Failed of string
  | Budget_exceeded of string
  | Crashed of string

let outcome_kind = function
  | Completed _ -> "completed"
  | Failed _ -> "failed"
  | Budget_exceeded _ -> "budget_exceeded"
  | Crashed _ -> "crashed"

let outcome_detail = function
  | Completed s | Failed s | Budget_exceeded s | Crashed s -> s

(* Bounds the child even if every layer above it is wrong. CPU is the one that
 * catches a runaway no static check can see. *)
let apply_limits ~wall_ms =
  let secs = max 1 ((wall_ms + 999) / 1000) in
  ignore (Unix.alarm secs)

let run_gig ~wall_ms ~(work : unit -> string) : outcome =
  let r, w = Unix.pipe () in
  match Unix.fork () with
  | 0 ->
      Unix.close r;
      let out = Unix.out_channel_of_descr w in
      (try
         apply_limits ~wall_ms;
         let result = work () in
         output_string out ("ok\n" ^ result);
         flush out
       with
       | Failure e -> output_string out ("fail\n" ^ e); flush out
       | e -> output_string out ("fail\n" ^ Printexc.to_string e); flush out);
      (* _exit, not exit: exit would run at_exit and flush buffers the child
         shares with the parent, duplicating the parent's pending output. *)
      Unix._exit 0
  | pid ->
      Unix.close w;
      let ic = Unix.in_channel_of_descr r in
      let buf = Buffer.create 512 in
      (try while true do Buffer.add_channel buf ic 1 done
       with End_of_file -> ());
      (try close_in ic with _ -> ());
      let _, status = Unix.waitpid [] pid in
      let payload = Buffer.contents buf in
      let tag, body =
        match String.index_opt payload '\n' with
        | Some i -> String.sub payload 0 i,
                    String.sub payload (i + 1) (String.length payload - i - 1)
        | None -> payload, ""
      in
      (match status, tag with
       | Unix.WEXITED 0, "ok"   -> Completed body
       | Unix.WEXITED 0, "fail" -> Failed body
       | Unix.WSIGNALED n, _ when n = Sys.sigalrm ->
           Budget_exceeded (Printf.sprintf "wall clock %dms exceeded" wall_ms)
       | Unix.WSIGNALED n, _ -> Crashed (Printf.sprintf "killed by signal %d" n)
       | Unix.WEXITED n, _ -> Crashed (Printf.sprintf "exit %d" n)
       | Unix.WSTOPPED n, _ -> Crashed (Printf.sprintf "stopped %d" n))
