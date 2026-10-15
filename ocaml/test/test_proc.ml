(* Proc: the one place in the labor tier where a process starts. Each check
   here was written against a fault it has been seen to catch. *)
open Gigwerk

let pass = ref 0 and fail = ref 0
let check name b =
  if b then (incr pass; Printf.printf "  ok   %s\n" name)
  else (incr fail; Printf.printf "  FAIL %s\n" name)

let timed f =
  let t0 = Unix.gettimeofday () in
  let r = f () in
  (r, Unix.gettimeofday () -. t0)

let () =
  print_endline "\nproc -- argv to execvp, no shell";
  let o, dt = timed (fun () ->
      Proc.run ~root:"/" ~timeout_s:20. [| "ls"; "/gigwerk-no-such-path" |]) in
  check "a child that writes only to stderr is read, and returns long before its deadline"
    (o.Proc.exit_status = Some 2 && o.Proc.stderr <> "" && o.Proc.stdout = "" && dt < 5.);
  let o, dt = timed (fun () ->
      Proc.run ~root:"/" ~timeout_s:20. [| "gigwerk-no-such-program" |]) in
  check "a program that does not exist is 127, promptly, as a shell would report"
    (o.Proc.exit_status = Some 127 && dt < 5.);
  let (), dt = timed (fun () ->
      for _ = 1 to 20 do
        ignore (Proc.run ~root:"/" ~timeout_s:2. [| "true" |])
      done) in
  check "twenty instant children together cost less than three of their deadlines"
    (dt < 6.);
  let o = Proc.run ~root:"/" ~timeout_s:5. [| "echo"; "a;b"; "$(x)"; "*" |] in
  check "argv is passed as written: no splitting, substitution or globbing"
    (o.Proc.stdout = "a;b $(x) *\n");
  let o, dt = timed (fun () -> Proc.run ~root:"/" ~timeout_s:0.5 [| "sleep"; "5" |]) in
  check "a child past its deadline is killed and reported as no exit status"
    (o.Proc.exit_status = None && dt < 3.);
  Printf.printf "proc: %d passed, %d failed\n" !pass !fail;
  if !fail <> 0 then exit 1
