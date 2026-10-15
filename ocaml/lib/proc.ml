(* Running a program, with no shell.
 *
 * argv goes to execvp directly, so nothing can be re-split, expanded, chained
 * or substituted: there is no interpreter left to do it. Verifier runs
 * acceptance checks through this, and an Actor runs its own tools through it,
 * so there is exactly one place in the labor tier where a process starts. *)

type outcome = {
  exit_status : int option;   (* None: killed at the deadline *)
  stdout : string;
  stderr : string;
}

let read_available fd buffer =
  let chunk = Bytes.create 4096 in
  let rec loop () =
    match Unix.read fd chunk 0 (Bytes.length chunk) with
    | 0 -> false
    | n -> Buffer.add_subbytes buffer chunk 0 n; true
    | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> true
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> loop ()
  in
  loop ()

let run ~root ~timeout_s (argv : string array) =
  if Array.length argv = 0 then invalid_arg "Proc.run: empty argv";
  let out_r, out_w = Unix.pipe () in
  let err_r, err_w = Unix.pipe () in
  match Unix.fork () with
  | 0 ->
      (* Everything in this arm must end in _exit. A failure that unwound out of
         the child would leave it running the PARENT's program past the fork,
         duplicating output and any store write the parent still has pending. *)
      (try
         Unix.close out_r; Unix.close err_r;
         Unix.dup2 out_w Unix.stdout; Unix.dup2 err_w Unix.stderr;
         Unix.close out_w; Unix.close err_w;
         Unix.chdir root;
         Unix.execvp argv.(0) argv
       with _ -> ());
      (* Reached only if execvp failed: 127, as a shell would report for a
         command that does not exist. *)
      Unix._exit 127
  | pid ->
      Unix.close out_w; Unix.close err_w;
      Unix.set_nonblock out_r; Unix.set_nonblock err_r;
      let out = Buffer.create 256 and err = Buffer.create 256 in
      let deadline = Unix.gettimeofday () +. timeout_s in
      let open_out = ref true and open_err = ref true and status = ref None in
      (* ECHILD means the child is already reaped, which is a fact about the
         child being gone -- exactly what these calls are waiting to learn. It
         is not an error to propagate, and propagating it aborted the whole of
         Producer.run on a command that merely finished early. *)
      let reap flags =
        try Some (Unix.waitpid flags pid) with
        | Unix.Unix_error (Unix.ECHILD, _, _) -> None
        | Unix.Unix_error (Unix.EINTR, _, _) -> None
      in
      let kill_and_wait () =
        (try Unix.kill pid Sys.sigkill with _ -> ());
        ignore (reap [])
      in
      (* The parentheses are load-bearing. Without them the `else` binds to
         the inner `if`, stderr is only ever read after a successful stdout
         read, and a child that closes stderr first leaves err_r permanently
         readable: select returns at once, forever, until the deadline. *)
      let drain ready =
        List.iter (fun fd ->
          if fd = out_r && !open_out then
            (if not (read_available out_r out) then open_out := false)
          else if fd = err_r && !open_err then
            (if not (read_available err_r err) then open_err := false)) ready
      in
      let fds () =
        (if !open_out then [out_r] else []) @ (if !open_err then [err_r] else [])
      in
      let timed_out = ref false in
      while (!open_out || !open_err || not (Option.is_some !status)) && not !timed_out do
        let remaining = deadline -. Unix.gettimeofday () in
        if remaining <= 0. then timed_out := true
        else begin
          (* Both pipes can reach EOF a moment before the child is reapable.
             select on no descriptors then just sleeps, and sleeping out the
             whole remaining deadline made every such run cost its timeout. *)
          let wait = if fds () = [] then Float.min remaining 0.01 else remaining in
          let ready, _, _ = Unix.select (fds ()) [] [] wait in
          drain ready;
          if not (Option.is_some !status) then
            match reap [ Unix.WNOHANG ] with
            | None -> status := Some (Unix.WEXITED 127)  (* already gone *)
            | Some (0, _) -> ()
            | Some (_, s) -> status := Some s
        end
      done;
      if !timed_out then begin
        kill_and_wait ();
        Unix.close out_r; Unix.close err_r;
        { exit_status = None; stdout = Buffer.contents out;
          stderr = Buffer.contents err }
      end else begin
        while !open_out || !open_err do
          let ready, _, _ = Unix.select (fds ()) [] [] 0.1 in
          drain ready
        done;
        Unix.close out_r; Unix.close err_r;
        let code = match !status with
          | Some (Unix.WEXITED n) -> n
          | Some (Unix.WSIGNALED n) -> 128 + n
          | Some (Unix.WSTOPPED n) -> 128 + n
          | None -> 1
        in
        { exit_status = Some code; stdout = Buffer.contents out;
          stderr = Buffer.contents err }
      end
