(* cvc5, booked for a part: the part stated as SyGuS (Cvc5_contract), cvc5's
 * solver does the labor, its answer is translated to OCaml, and acceptance
 * is the part's own tests and the differential, as for every writer. *)

let solver () = match Sys.getenv_opt "GW_CVC5" with Some p -> p | None -> "cvc5"

let book ~scratch ~timeout_s ~name problem =
  let file = Filename.concat scratch (name ^ ".sy") in
  Probe.write file problem;
  let o = Gigwerk.Proc.run ~root:scratch ~timeout_s:(timeout_s +. 10.)
      [| solver (); "--lang=sygus2"; Printf.sprintf "--tlimit=%.0f" (timeout_s *. 1000.); file |] in
  let out = String.trim o.Gigwerk.Proc.stdout in
  if String.length out > 0 && out.[0] = '(' && (try ignore (Str.search_forward (Str.regexp_string "define-fun") out 0); true with Not_found -> false)
  then (try Ok (Cvc5_contract.answer out) with Failure e -> Error ("cvc5's answer: " ^ e))
  else
    let said = String.trim (out ^ " " ^ o.Gigwerk.Proc.stderr) in
    Error (if said = "" || o.Gigwerk.Proc.exit_status = None then "cvc5: no answer within the time limit"
           else "cvc5: " ^ (if String.length said > 200 then String.sub said 0 200 else said))

let derive ~scratch ~timeout_s (iface : Iface.t) examples (v : Iface.value_spec) =
  let name = v.Iface.vname in
  let exs = List.filter_map (fun (t, ex) -> if t = name then Some ex else None) examples in
  let exs = List.fold_left (fun acc (ex : Spec.example) ->
      if List.exists (fun (e : Spec.example) ->
          List.length e.Spec.args = List.length ex.Spec.args && List.for_all2 Value.equal e.Spec.args ex.Spec.args) acc
      then acc else acc @ [ ex ]) [] exs in
  if exs = [] then Smyth_talent.Declined { name; why = "no example of it could be read from the tests" }
  else
    let args, out = Types.unarrow (Iface.expand iface.Iface.decls v.Iface.vty) in
    let params = Part.param_names args in
    match Cvc5_contract.problem ~params:(List.map (fun (n, _, t) -> (n, t)) params) ~out_ty:out exs with
    | exception Cvc5_contract.Unrepresentable what -> Smyth_talent.Declined { name; why = "SyGuS here cannot state " ^ what }
    | problem ->
        (match book ~scratch ~timeout_s ~name problem with
         | Ok body -> Smyth_talent.Derived { name; definition =
                        Cvc5_contract.definition ~name ~params:(List.map (fun (n, l, _) -> (n, l)) params) body }
         | Error why -> Smyth_talent.Declined { name; why })

let solve ~env ~scratch ~exercise_dir ~slug ?(timeout_s = 60.) () =
  Smyth_talent.solve_with ~derive:(derive ~scratch ~timeout_s) ~prelude:[ Cvc5_contract.helpers ]
    ~env ~scratch ~exercise_dir ~slug ()
