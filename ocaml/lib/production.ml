(* An acceptance check is a CLOSED VARIANT, not a command string.
 *
 * It was a string, and Verifier handed it to /bin/sh -c. The specification is
 * written by the agent, which is the one thing in this system that calls a
 * model, so the path ran: model output -> free text -> shell. A working
 * directory is not a confinement.
 *
 * Same move as Grants.action: a verb nobody defined is not "unknown", it is
 * unrepresentable, so a typo fails to parse rather than reaching a shell. This
 * is affordable for OCaml precisely because the toolchain IS a closed set of
 * verbs; you do not need sh to build OCaml. *)
type acceptance =
  | Dune_build
  | Dune_runtest of string option   (* optional subdirectory *)
  | Dune_exec of string             (* target *)
  | Fmt_check

(* argv, never a command line. Nothing here is concatenated, so nothing here
   can be split apart again by a shell that never runs. *)
let acceptance_argv = function
  | Dune_build -> [ "dune"; "build" ]
  | Dune_runtest None -> [ "dune"; "runtest" ]
  | Dune_runtest (Some dir) -> [ "dune"; "runtest"; dir ]
  | Dune_exec target -> [ "dune"; "exec"; target ]
  | Fmt_check -> [ "dune"; "build"; "@fmt" ]

let acceptance_to_string a = String.concat " " (acceptance_argv a)

type requirement = {
  id : string;
  statement : string;
  depends_on : string list;
  acceptance : acceptance option;
}

type artifact = {
  requirement_id : string;
  paths : string list;
}
