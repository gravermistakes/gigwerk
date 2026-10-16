(* writer: drive the OCaml-writing talent's components from the command line. *)
open Writer

let env () =
  match Sys.getenv_opt "GW_OPAM_SWITCH" with
  | Some sw ->
      [| "env"; "OPAMROOT=" ^ (try Sys.getenv "OPAMROOT" with Not_found -> "/home/user/.opam-gw");
         "opam"; "exec"; "--switch"; sw; "--" |]
  | None -> [||]

let scratch () =
  match Sys.getenv_opt "GW_SCRATCH" with
  | Some d -> d
  | None -> Filename.concat (Filename.get_temp_dir_name ()) "gw-writer"

(* One word for a part's outcome, and the evidence behind it. A part is
   verified only when its own check passes AND the derived program agrees with
   the reference on every fresh input in the reference's domain. *)
let classify ?(constant_only = false) ~suite ~diff ~declined () =
  match suite, diff with
  | `Not_run _, _ -> ("declined", String.concat " | " declined)
  | `Failed _, _ -> ("own-check-failed", "")
  | `Passed, Some (Ok v) when v.Verify.disagreements = [] && v.Verify.compared > 0 ->
      ("verified", Printf.sprintf "%d/%d fresh inputs" v.Verify.agreed v.Verify.compared)
  | `Passed, Some (Error "no input could be generated") when constant_only ->
      (* a part made of constants has no inputs to vary: its own check is
         the whole of what it asks *)
      ("verified", "constants only; its own check is complete")
  | `Passed, Some (Ok v) when v.Verify.compared = 0 -> ("unconfirmed", "no fresh input in the reference's domain")
  | `Passed, Some (Ok v) ->
      ("overfit", Printf.sprintf "%d/%d; %s" v.Verify.agreed v.Verify.compared
         (match v.Verify.disagreements with d :: _ -> d | [] -> ""))
  | `Passed, Some (Error e) -> ("unconfirmed", "differential not run: " ^ String.sub e 0 (min 100 (String.length e)))
  | `Passed, None -> ("unconfirmed", "")

let library_defs : (string * string list * Writer.Expr.t) list ref = ref []

let () =
  match Array.to_list Sys.argv with
  | _ :: "probe" :: dir :: _ ->
      let slug = Filename.basename dir in
      let sc = scratch () in
      (try Unix.mkdir sc 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
      let o = Probe.run ~env:(env ()) ~scratch:sc ~exercise_dir:dir ~slug in
      Printf.printf "%s: %d sites, %d examples\n" slug o.Probe.sites (List.length o.Probe.examples);
      List.iter (fun (t, ex) -> print_endline ("  " ^ Spec.example_to_string t ex)) o.Probe.examples;
      if o.Probe.examples = [] then print_endline o.Probe.log
  | _ :: "solve" :: dir :: _ ->
      let slug = Filename.basename dir in
      let sc = scratch () in
      (try Unix.mkdir sc 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
      let r = Part.solve ~env:(env ()) ~scratch:sc ~exercise_dir:dir ~slug () in
      List.iter (function
          | Part.Derived { name; considered; _ } -> Printf.printf "  derived  %s (%d terms considered)\n" name considered
          | Part.Declined { name; why } -> Printf.printf "  declined %s: %s\n" name why) r.Part.derivations;
      (match r.Part.source with Some s -> print_string s | None -> ());
      (match r.Part.tests with
       | `Passed -> Printf.printf "%s: PASSED its own test suite\n" slug
       | `Failed log -> Printf.printf "%s: FAILED its test suite\n%s\n" slug
                          (String.concat "\n" (List.filteri (fun i _ -> i < 25) (String.split_on_char '\n' log)))
       | `Not_run why -> Printf.printf "%s: not tested (%s)\n" slug why);
      let declined = List.filter_map (function
          | Part.Declined { name; why } -> Some (name ^ ": " ^ why) | _ -> None) r.Part.derivations in
      at_exit (fun () ->
          let constant_only = List.for_all (function
              | Part.Derived { params; _ } -> params = [] | Part.Declined _ -> false) r.Part.derivations in
          let verdict, detail = classify ~constant_only ~suite:r.Part.tests ~diff:r.Part.differential ~declined () in
          Printf.printf "VERDICT\t%s\t%s\t%s\n" slug verdict detail);
      (match r.Part.differential with
       | None -> ()
       | Some (Error e) -> Printf.printf "%s: differential not run: %s\n" slug
                             (String.concat "\n" (List.filteri (fun i _ -> i < 15) (String.split_on_char '\n' e)))
       | Some (Ok v) ->
           Printf.printf "%s: agrees with the reference on %d of %d fresh inputs\n" slug v.Verify.agreed v.Verify.compared;
           List.iter (fun d -> print_endline ("    counterexample: " ^ d)) (List.filteri (fun i _ -> i < 5) v.Verify.disagreements))
  | _ :: "org" :: path :: _ ->
      let r = Ocamlorg.solve ?library:(Sys.getenv_opt "GW_LIBRARY") ~path () in
      let declined = List.filter_map (function
          | Part.Declined { name; why } -> Some (name ^ ": " ^ why) | _ -> None) r.Ocamlorg.derivations in
      at_exit (fun () ->
          let verdict, detail = classify ~suite:r.Ocamlorg.replay ~diff:r.Ocamlorg.differential ~declined () in
          Printf.printf "VERDICT\t%s\t%s\t%s\n" r.Ocamlorg.slug verdict detail);
      List.iter (function
          | Part.Derived { name; considered; _ } -> Printf.printf "  derived  %s (%d steps)\n" name considered
          | Part.Declined { name; why } -> Printf.printf "  declined %s: %s\n" name why) r.Ocamlorg.derivations;
      (match r.Ocamlorg.source with Some s -> print_endline s | None -> ());
      (match r.Ocamlorg.replay with
       | `Passed -> Printf.printf "%s: statement replay PASSED\n" r.Ocamlorg.slug
       | `Failed why -> Printf.printf "%s: statement replay FAILED: %s\n" r.Ocamlorg.slug why
       | `Not_run why -> Printf.printf "%s: replay not run (%s)\n" r.Ocamlorg.slug why);
      (match r.Ocamlorg.differential with
       | None -> ()
       | Some (Error e) -> Printf.printf "%s: differential not run: %s\n" r.Ocamlorg.slug e
       | Some (Ok v) ->
           Printf.printf "%s: agrees with the Solution on %d of %d fresh inputs\n" r.Ocamlorg.slug v.Verify.agreed v.Verify.compared;
           List.iter (fun d -> print_endline ("    counterexample: " ^ d)) (List.filteri (fun i _ -> i < 4) v.Verify.disagreements))
  | _ :: "prolog" :: kind :: path :: _ ->
      (* the next actor: derive with the same components, deliver as Prolog *)
      let slug, derivations, examples, diff =
        if kind = "exercism" then
          let slug = Filename.basename path in
          let sc = scratch () in
          (try Unix.mkdir sc 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
          let r = Part.solve ~env:(env ()) ~scratch:sc ~exercise_dir:path ~slug () in
          (slug, r.Part.derivations, r.Part.examples, r.Part.differential)
        else
          let r = Ocamlorg.solve ?library:(Sys.getenv_opt "GW_LIBRARY") ~path () in
          library_defs := List.map (fun (e : Library.entry) -> (e.name, List.map fst e.params, e.body)) r.Ocamlorg.library_used;
          (r.Ocamlorg.slug, r.Ocamlorg.derivations, r.Ocamlorg.examples, r.Ocamlorg.differential) in
      let defs = !library_defs @ List.filter_map (function
          | Part.Derived { name; params; body; _ } -> Some (name, List.map fst params, body)
          | Part.Declined _ -> None) derivations in
      let declined = List.filter_map (function
          | Part.Declined { name; why } -> Some (name ^ ": " ^ why) | _ -> None) derivations in
      let samples = match diff with Some (Ok v) -> v.Verify.samples | _ -> [] in
      let calls = List.map (fun (n, ex) -> (n, ex.Spec.args, ex.Spec.out)) examples @ samples in
      let verdict, detail =
        if declined <> [] || defs = [] then ("declined", String.concat " | " declined)
        else match Prolog_actor.check ~definitions:defs ~calls with
          | Error e -> ("declined", e)
          | Ok v ->
              print_string v.Prolog_actor.source;
              List.iter (fun f -> print_endline ("    failed: " ^ f)) (List.filteri (fun i _ -> i < 5) v.Prolog_actor.failures);
              if v.Prolog_actor.failures = [] && samples <> [] then
                ("verified", Printf.sprintf "%d/%d (examples and fresh inputs, against the reference's answers)" v.Prolog_actor.passed v.Prolog_actor.total)
              else if v.Prolog_actor.failures = [] then ("unconfirmed", "examples only")
              else ("failed", Printf.sprintf "%d/%d" v.Prolog_actor.passed v.Prolog_actor.total) in
      Printf.printf "PROLOG\t%s\t%s\t%s\n" slug verdict detail
  | _ :: "batch" :: kind :: src :: out :: only ->
      (* Every part, each in its own process under a memory limit, one line of
         verdict each. A part that exhausts memory or time loses only itself. *)
      (try Unix.mkdir out 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
      let entries = Sys.readdir src |> Array.to_list |> List.sort compare in
      let items = match kind with
        | "exercism" -> List.filter (fun d -> Sys.is_directory (Filename.concat src d)) entries
        | _ -> List.filter (fun f -> Filename.check_suffix f ".md") entries in
      let items = List.filter (fun d -> only = [] || List.mem (Filename.remove_extension d) only) items in
      let one item =
          let slug = Filename.remove_extension item in
          let t0 = Unix.gettimeofday () in
          let cmd = if kind = "exercism" then "solve" else "org" in
          let o = Gigwerk.Proc.run ~root:(Sys.getcwd ()) ~timeout_s:1200.
              [| "prlimit"; "--as=" ^ (match Sys.getenv_opt "GW_MEM" with Some m -> m | None -> "6000000000");
                 Sys.executable_name; cmd; Filename.concat src item |] in
          let log = o.Gigwerk.Proc.stdout ^ o.Gigwerk.Proc.stderr in
          let oc = open_out (Filename.concat out (slug ^ ".log")) in output_string oc log; close_out oc;
          let verdict = List.find_map (fun l ->
              match String.split_on_char '\t' l with
              | "VERDICT" :: _ :: v :: rest -> Some (v, String.concat " " rest) | _ -> None)
              (String.split_on_char '\n' o.Gigwerk.Proc.stdout) in
          let v, d = match verdict, o.Gigwerk.Proc.exit_status with
            | Some vd, _ -> vd
            | None, None -> ("error", "timed out")
            | None, Some n -> ("error", Printf.sprintf "exited %d" n) in
          let line = Printf.sprintf "%s\t%s\t%.0fs\t%s\n" slug v (Unix.gettimeofday () -. t0)
              (String.map (fun c -> if c = '\n' || c = '\t' then ' ' else c) d) in
          let oc = open_out (Filename.concat out (slug ^ ".verdict")) in output_string oc line; close_out oc;
          print_string line; flush stdout in
      (* a pool of forked workers, each running one part at a time *)
      let jobs = match Sys.getenv_opt "GW_JOBS" with Some j -> int_of_string j | None -> 1 in
      let running = ref 0 in
      List.iter (fun item ->
          if !running >= jobs then (ignore (Unix.wait ()); decr running);
          match Unix.fork () with
          | 0 -> (try one item with _ -> ()); Unix._exit 0
          | _ -> incr running) items;
      while !running > 0 do ignore (Unix.wait ()); decr running done;
      let tsv = open_out (Filename.concat out "results.tsv") in
      List.iter (fun item ->
          let f = Filename.concat out (Filename.remove_extension item ^ ".verdict") in
          if Sys.file_exists f then output_string tsv (Iface.read_file f)) items;
      close_out tsv
  | _ :: "results" :: title :: logs ->
      (* a batch's verdict lines as a table, counted, nothing carried over *)
      let rows = List.concat_map (fun f ->
          let ic = open_in f in
          let rec go acc = match input_line ic with
            | l -> (match String.split_on_char '\t' l with
                | slug :: verdict :: secs :: rest -> go ((slug, verdict, secs, String.concat " " rest) :: acc)
                | _ -> go acc)
            | exception End_of_file -> close_in ic; List.rev acc in
          go []) logs |> List.sort compare in
      let words = [ "verified"; "overfit"; "unconfirmed"; "own-check-failed"; "declined"; "error" ] in
      Printf.printf "### %s\n\n%d parts: %s.\n\n| part | outcome | time | evidence |\n|---|---|---|---|\n" title (List.length rows)
        (String.concat ", " (List.filter_map (fun w ->
             match List.length (List.filter (fun (_, v, _, _) -> v = w) rows) with
             | 0 -> None | n -> Some (Printf.sprintf "%d %s" n w)) words));
      let cell s = String.concat "\\|" (String.split_on_char '|' (if String.length s > 160 then String.sub s 0 157 ^ "..." else s)) in
      List.iter (fun (slug, v, secs, d) -> Printf.printf "| %s | %s | %s | %s |\n" slug v secs (cell d)) rows
  | _ -> prerr_endline "writer probe|solve <exercise-dir> | org <exercise.md> | batch exercism|org <src-dir> <out-dir> [slug...] | results <title> <batch.log>..."; exit 2
