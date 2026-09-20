type result = {
  command : string;
  exit_status : int option;
  stdout : string;
  stderr : string;
  passed : bool;
}

type t = { results : result list; passed : bool }

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

let run_command ~root ~timeout_s command =
  let out_r, out_w = Unix.pipe () in
  let err_r, err_w = Unix.pipe () in
  match Unix.fork () with
  | 0 ->
      Unix.close out_r; Unix.close err_r;
      Unix.dup2 out_w Unix.stdout; Unix.dup2 err_w Unix.stderr;
      Unix.close out_w; Unix.close err_w;
      Unix.chdir root;
      Unix.execv "/bin/sh" [| "/bin/sh"; "-c"; command |]
  | pid ->
      Unix.close out_w; Unix.close err_w;
      Unix.set_nonblock out_r; Unix.set_nonblock err_r;
      let out = Buffer.create 256 and err = Buffer.create 256 in
      let deadline = Unix.gettimeofday () +. timeout_s in
      let open_out = ref true and open_err = ref true and status = ref None in
      let kill_and_wait () =
        (try Unix.kill pid Sys.sigkill with _ -> ());
        ignore (Unix.waitpid [] pid)
      in
      let timed_out = ref false in
      while (!open_out || !open_err || not (Option.is_some !status)) && not !timed_out do
        let remaining = deadline -. Unix.gettimeofday () in
        if remaining <= 0. then timed_out := true
        else begin
          let fds = (if !open_out then [out_r] else []) @ (if !open_err then [err_r] else []) in
          let ready, _, _ = Unix.select fds [] [] remaining in
          List.iter (fun fd ->
            if fd = out_r && !open_out then
              if not (read_available out_r out) then open_out := false
            else if fd = err_r && !open_err then
              if not (read_available err_r err) then open_err := false) ready;
          if not (Option.is_some !status) then
            match Unix.waitpid [Unix.WNOHANG] pid with
            | 0, _ -> ()
            | _, s -> status := Some s
        end
      done;
      if !timed_out then begin
        kill_and_wait ();
        Unix.close out_r; Unix.close err_r;
        { command; exit_status = None; stdout = Buffer.contents out;
          stderr = Buffer.contents err ^ "\nverification timeout"; passed = false }
      end else begin
        while !open_out || !open_err do
          let fds = (if !open_out then [out_r] else []) @ (if !open_err then [err_r] else []) in
          if fds = [] then ()
          else
            let ready, _, _ = Unix.select fds [] [] 0.1 in
            List.iter (fun fd ->
              if fd = out_r && !open_out then
                if not (read_available out_r out) then open_out := false
              else if fd = err_r && !open_err then
                if not (read_available err_r err) then open_err := false) ready
        done;
        Unix.close out_r; Unix.close err_r;
        let code = match !status with
          | Some (Unix.WEXITED n) -> n
          | Some (Unix.WSIGNALED n) -> 128 + n
          | Some (Unix.WSTOPPED n) -> 128 + n
          | None -> 1
        in
        { command; exit_status = Some code; stdout = Buffer.contents out;
          stderr = Buffer.contents err; passed = code = 0 }
      end

let verify workspace specification =
  let commands =
    Specification.requirements specification
    |> List.filter_map (fun r -> Option.map (fun c -> (r.Production.id, c)) r.Production.acceptance)
  in
  let results =
    List.map (fun (_id, command) -> run_command ~root:workspace.Workspace.root ~timeout_s:30. command) commands
  in
  { results; passed = List.for_all (fun (r : result) -> r.passed) results }

module Verification = struct
  type nonrec t = t
end
