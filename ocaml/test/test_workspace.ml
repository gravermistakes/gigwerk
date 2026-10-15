(* Workspace confinement: everything an Actor writes or reads lands beneath
 * the root, new subdirectories included, and no path, symlink or absolute name
 * reaches outside it. *)
open Gigwerk

let pass = ref 0 and fail = ref 0
let check name b =
  if b then (incr pass; Printf.printf "  ok   %s\n" name)
  else (incr fail; Printf.printf "  FAIL %s\n" name)

let temp_dir () =
  let d = Filename.temp_file "gigwerk_ws" "" in
  Sys.remove d; Unix.mkdir d 0o755;
  at_exit (fun () -> ignore (Proc.run ~root:"/" ~timeout_s:10. [| "rm"; "-rf"; d |]));
  d

let () =
  print_endline "workspace -- beneath the root, and nowhere else";
  let root = temp_dir () and outside = temp_dir () in
  let ws = match Workspace.create root with Ok ws -> ws | Error _ -> failwith "create" in
  let real = ws.Workspace.root in
  let refused = function Error (Workspace.Invalid_path _) -> true | _ -> false in

  check "a file in a subdirectory that does not exist yet is written, under the root"
    (Workspace.write ws ~path:"new/deeper/a.ml" ~contents:"x" = Ok ()
     && Sys.file_exists (Filename.concat real "new/deeper/a.ml"));
  check "...and read back"
    (Workspace.read ws ~path:"new/deeper/a.ml" = Ok "x");
  check "a path that climbs out with .. is refused"
    (refused (Workspace.write ws ~path:"new/../../escape" ~contents:"x"));
  check "an absolute path is refused"
    (refused (Workspace.write ws ~path:(Filename.concat outside "abs") ~contents:"x"));

  Unix.symlink outside (Filename.concat real "door");
  check "a symlink inside the root that leads out is refused"
    (refused (Workspace.write ws ~path:"door/x" ~contents:"x")
     && not (Sys.file_exists (Filename.concat outside "x")));
  check "...including through directories beneath it that do not exist yet"
    (refused (Workspace.write ws ~path:"door/new/x" ~contents:"x")
     && not (Sys.file_exists (Filename.concat outside "new")));
  check "...and for reads"
    (refused (Workspace.read ws ~path:"door/x"));
  check "reading something not there is an error, not a crash"
    (match Workspace.read ws ~path:"nowhere/at/all" with Error _ -> true | Ok _ -> false);

  check "a root that cannot be made is an error, not an exception"
    (match Workspace.create "/dev/null/no-such-root" with
     | Error (Workspace.Invalid_root _) -> true
     | _ -> false
     | exception _ -> false);

  Printf.printf "workspace: %d passed, %d failed\n" !pass !fail;
  if !fail <> 0 then exit 1
