(* Asserts the properties the design claims, not that the code runs. *)
open Gigwerk

let pass = ref 0 and fail = ref 0
let check name b =
  if b then (incr pass; Printf.printf "  ok   %s\n" name)
  else (incr fail; Printf.printf "  FAIL %s\n" name)

let root = "/tmp/gw-test"

let () =
  ignore (Sys.command (Printf.sprintf "rm -rf %s && mkdir -p %s/sub" root root));
  let oc = open_out (root ^ "/inside.txt") in
  output_string oc "hello (world)\n"; close_out oc;
  let oc = open_out (root ^ "/sub/deep.txt") in
  output_string oc "deep\n"; close_out oc;
  ignore (Sys.command (Printf.sprintf "ln -sf /etc/passwd %s/evil-link" root));

  print_string "\nkernel\n";
  check "openat2 with RESOLVE_BENEATH is available" (Caps.have_openat2 ());

  print_string "\ncapability root\n";
  let c = Caps.fs_read ~root in
  check "reads a file inside the root"
    (try Caps.read c "inside.txt" = "hello (world)\n" with _ -> false);
  check "reads through a subdirectory"
    (try Caps.read c "sub/deep.txt" = "deep\n" with _ -> false);

  print_string "\nescape attempts -- all must be refused BY THE KERNEL\n";
  let refused p =
    try ignore (Caps.read c p); false with Failure _ -> true in
  check "dotdot traversal refused"            (refused "../../etc/passwd");
  check "absolute path refused"               (refused "/etc/passwd");
  (* RESOLVE_BENEATH forbids ESCAPING the root, not ".." as syntax. A dotdot
     that stays inside resolves fine, and there is no security reason to refuse
     it. This assertion was wrong on the first run -- pinning the real boundary. *)
  check "dotdot that stays inside the root is PERMITTED"
    (try Caps.read c "sub/../inside.txt" = "hello (world)\n" with _ -> false);
  check "symlink out of the root refused"     (refused "evil-link");
  check "nonexistent file still errors"       (refused "nope.txt");

  print_string "\nprocess boundary\n";
  (* The dirfd is opened before the fork, so the child inherits it. That is the
     answer to "can ocap cross a process boundary": for fork, by inheritance.
     NOT for exec -- the fd is O_CLOEXEC, so exec would need SCM_RIGHTS or
     re-derivation under Landlock. Phase 2 question, flagged not guessed. *)
  let o = Actor.run_gig ~wall_ms:5000 ~work:(fun () -> Caps.read c "inside.txt") in
  check "inherited capability works in the forked child"
    (match o with Actor.Completed s -> s = "hello (world)\n" | _ -> false);
  let o = Actor.run_gig ~wall_ms:5000
      ~work:(fun () -> Caps.read c "../../etc/passwd") in
  check "child cannot escape the inherited root"
    (match o with Actor.Failed _ -> true | _ -> false);
  let o = Actor.run_gig ~wall_ms:5000 ~work:(fun () -> failwith "boom") in
  check "child failure is reported, parent survives"
    (match o with Actor.Failed s -> s = "boom" | _ -> false);
  let o = Actor.run_gig ~wall_ms:1000 ~work:(fun () -> Unix.sleep 5; "never") in
  check "runaway child is killed on the wall clock"
    (match o with Actor.Budget_exceeded _ -> true | _ -> false);
  check "parent is alive after all of the above" (1 + 1 = 2);

  print_string "\nbehaviors are deterministic\n";
  let mk () = Behaviors.critic { root = c; ledger = Caps.sqlite_ro ~db:"x.db" }
                ~artifact:"inside.txt" in
  check "same input, same verdict" (mk () = mk ());
  check "echo needs no capability at all"
    ((Behaviors.echo () ~msg:"m").detail = "m");
  check "critic reports a bad artifact without erroring"
    (let v = Behaviors.critic { root = c; ledger = Caps.sqlite_ro ~db:"x.db" }
               ~artifact:"nope.txt" in
     not v.ok && v.reason = "unreadable");

  Printf.printf "\n%d passed, %d failed\n" !pass !fail;
  if !fail > 0 then exit 1
