(* The next actor: the same derivation, written as Prolog and checked by
 * SWI-Prolog. Nothing here searches. It takes the terms the OCaml writer's
 * components derived, lowers them (Lower_prolog), and runs them against the
 * part's examples and against the fresh inputs the verifier drew, whose
 * reference answers came from the reference solution. *)

type verdict = {
  passed : int;
  total : int;
  failures : string list;
  source : string;
}

let driver (calls : (string * Value.t list * Value.t) list) =
  let tests = List.mapi (fun i (name, args, out) ->
      Printf.sprintf "gw_test(%d) :- ( catch(call_with_time_limit(5, %s(%s)), _, fail) -> ( R == %s -> format(\"~w ok~n\", [%d]) ; format(\"~w no ~q~n\", [%d, R]) ) ; format(\"~w fail~n\", [%d]) )."
        i (Lower_prolog.predicate_name name)
        (String.concat ", " (List.map Lower_prolog.term args @ [ "R" ]))
        (Lower_prolog.term out) i i i) calls in
  ":- use_module(library(time)).\n" ^ String.concat "\n" tests
  ^ Printf.sprintf "\nmain :- forall(between(0, %d, I), gw_test(I)).\n:- initialization(main, main).\n"
    (List.length calls - 1)

(* A Prolog program from anywhere (Popper's, for one), run on the same
   calls. *)
let run_source ~source ~calls =
  if calls = [] then Error "nothing to check it against"
  else
    let program = Lower_prolog.prelude ^ "\n" ^ source ^ "\n" ^ driver calls in
    let f = Filename.temp_file "gw_prolog" ".pl" in
    Probe.write f program;
    let o = Gigwerk.Proc.run ~root:(Filename.dirname f) ~timeout_s:300. [| "swipl"; "-q"; f |] in
    (try Sys.remove f with _ -> ());
    let lines = String.split_on_char '\n' o.Gigwerk.Proc.stdout in
    let ok i = List.mem (Printf.sprintf "%d ok" i) lines in
    let failures = List.concat (List.mapi (fun i (name, args, out) ->
        if ok i then []
        else [ Printf.sprintf "%s(%s) should give %s" (Lower_prolog.predicate_name name)
                 (String.concat ", " (List.map Lower_prolog.term args)) (Lower_prolog.term out) ]) calls) in
    let errors = String.trim o.Gigwerk.Proc.stderr in
    Ok { passed = List.length calls - List.length failures; total = List.length calls;
         failures = (if errors <> "" && failures <> [] then [ errors ] else []) @ failures; source }

let check ~(definitions : (string * string list * Expr.t) list) ~calls =
  match List.map (fun (name, params, body) -> Lower_prolog.definition ~name ~params body) definitions with
  | exception Lower_prolog.Unsupported why -> Error ("cannot be written as Prolog: " ^ why)
  | clauses ->
      let source = String.concat "\n" clauses in
      if calls = [] then Error "nothing to check it against"
      else
        let program = Lower_prolog.prelude ^ "\n" ^ source ^ "\n" ^ driver calls in
        let f = Filename.temp_file "gw_prolog" ".pl" in
        Probe.write f program;
        let o = Gigwerk.Proc.run ~root:(Filename.dirname f) ~timeout_s:300. [| "swipl"; "-q"; f |] in
        (try Sys.remove f with _ -> ());
        let lines = String.split_on_char '\n' o.Gigwerk.Proc.stdout in
        let ok i = List.mem (Printf.sprintf "%d ok" i) lines in
        let failures = List.concat (List.mapi (fun i (name, args, out) ->
            if ok i then []
            else [ Printf.sprintf "%s(%s) should give %s" (Lower_prolog.predicate_name name)
                     (String.concat ", " (List.map Lower_prolog.term args)) (Lower_prolog.term out) ]) calls) in
        let errors = String.trim o.Gigwerk.Proc.stderr in
        Ok { passed = List.length calls - List.length failures; total = List.length calls;
             failures = (if errors <> "" && failures <> [] then [ errors ] else []) @ failures; source }
