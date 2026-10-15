(* Verification is not the actor's. It is the one component that reads the
 * reference solution, and nothing it reads flows back into the search.
 *
 * A part's own test suite is necessary and not sufficient: leap's nine tests
 * pass for `0 = x mod 4 && 300 < x mod 401`, which calls 2004 a common year.
 * So the written module is also run beside the reference on inputs neither
 * has seen: the examples' inputs, mutated. Where the reference raises, the
 * input is outside the part's domain and is not compared. Every disagreement
 * on the rest is a counterexample, printed.
 *
 * Generation is seeded: the same part draws the same inputs, so a verdict can
 * be reproduced exactly. *)

open Types

type verdict = {
  compared : int;
  agreed : int;
  disagreements : string list;   (* call, writer's value, reference's value *)
  samples : (string * Value.t list * Value.t) list;   (* fresh inputs and the reference's answers *)
}

(* Random.State with a fixed seed: reproducible, and without the short
   low-bit cycles of a bare LCG, which made every coin flip here move in
   lockstep with the one before it. *)
let state = ref (Random.State.make [| 0x5eed |])
let next () = Random.State.bits !state
let pick l = List.nth l (next () mod List.length l)
let chance n = next () mod n = 0

let rec gen decls pool (t : ty) (seen : Value.t list) : Value.t =
  let from_seen () = if seen <> [] && chance 2 then Some (pick seen) else None in
  match repr t with
  | TCon ("int", []) ->
      let ints = List.filter_map (function Value.Int n -> Some n | _ -> None) seen in
      let hi = List.fold_left (fun m n -> max m (abs n)) 10 ints in
      let base = match ints with [] -> 7 | _ -> pick ints in
      Value.Int (match next () mod 10 with
          | 0 | 1 -> next () mod (2 * hi + 10)                    (* uniform over the seen range *)
          | 2 -> next () mod 21                                   (* small *)
          | 3 -> let p = pick [ 10; 100; 1000 ] in p * (next () mod (max 1 (2 * hi / p + 2)))  (* round *)
          | 4 -> base + 1 | 5 -> base - 1 | 6 -> base * 2
          | 7 -> base + (next () mod 50)
          | _ -> abs base + (next () mod 13))
  | TCon ("int64", []) ->
      (match gen decls pool t_int (List.filter_map (function Value.Int64 n -> Some (Value.Int (Int64.to_int n)) | _ -> None) seen) with
       | Value.Int n -> Value.Int64 (Int64.of_int n) | v -> v)
  | TCon ("float", []) ->
      let base = match seen with [] -> 1.5 | _ -> (match pick seen with Value.Float f -> f | _ -> 1.5) in
      Value.Float (base +. float_of_int (next () mod 200 - 100) /. 10.)
  | TCon ("bool", []) -> Value.Bool (chance 2)
  | TCon ("char", []) ->
      let chars = List.filter_map (function Value.Char c -> Some c | _ -> None) pool in
      Value.Char (if chars = [] || chance 5 then Char.chr (32 + next () mod 95) else pick chars)
  | TCon ("string", []) ->
      (match from_seen () with
       | Some (Value.String s) when String.length s > 0 && chance 2 ->
           (* mutate a seen string: drop, duplicate or change one char *)
           let i = next () mod String.length s in
           let b = Buffer.create (String.length s + 1) in
           String.iteri (fun k c ->
               if k = i then (match next () mod 3 with
                   | 0 -> ()
                   | 1 -> Buffer.add_char b c; Buffer.add_char b c
                   | _ -> (match gen decls pool t_char [] with Value.Char d -> Buffer.add_char b d | _ -> ()))
               else Buffer.add_char b c) s;
           Value.String (Buffer.contents b)
       | Some v -> v
       | None ->
           let n = next () mod 12 in
           Value.String (String.init n (fun _ -> match gen decls pool t_char [] with Value.Char c -> c | _ -> 'a')))
  | TCon ("unit", []) -> Value.Unit
  | TCon ("list", [ a ]) ->
      (match from_seen () with
       | Some (Value.List l) when l <> [] && chance 2 ->
           let l = if chance 2 then List.rev l else List.filteri (fun i _ -> i <> next () mod List.length l) l in
           Value.List l
       | Some v -> v
       | None ->
           let elems = List.concat_map (function Value.List l -> l | _ -> []) seen in
           let n = next () mod 8 in
           Value.List (List.init n (fun _ -> gen decls pool a elems)))
  | TCon ("array", [ a ]) ->
      (match gen decls pool (t_list a) (List.map (function Value.Array xs -> Value.List (Array.to_list xs) | v -> v) seen) with
       | Value.List l -> Value.Array (Array.of_list l) | v -> v)
  | TCon ("option", [ a ]) ->
      if chance 3 then Value.Con ("None", [])
      else Value.Con ("Some", [ gen decls pool a (List.filter_map (function Value.Con ("Some", [ x ]) -> Some x | _ -> None) seen) ])
  | TTuple ts ->
      Value.Tuple (List.mapi (fun i t ->
          gen decls pool t (List.filter_map (function Value.Tuple xs -> List.nth_opt xs i | _ -> None) seen)) ts)
  | TCon (name, args) ->
      (match List.find_opt (fun d -> d.name = name) decls with
       | Some { kind = Variant ctors; params; _ } ->
           let sub = List.combine params args in
           let rec inst t = match repr t with
             | TVar v -> (match List.assoc_opt v sub with Some t -> t | None -> t)
             | TCon (n, ts) -> TCon (n, List.map inst ts)
             | TTuple ts -> TTuple (List.map inst ts) | t -> t in
           let shallow = List.filter (fun (_, a) -> a = []) ctors in
           let c, cargs = if shallow <> [] && chance 2 then pick shallow else pick ctors in
           Value.Con (c, List.map (fun t -> gen decls pool (inst t) []) cargs)
       | Some { kind = Poly rows; _ } ->
           let tag, arg = pick rows in
           Value.Poly (tag, Option.map (fun t -> gen decls pool t []) arg)
       | Some { kind = Record fields; _ } ->
           Value.Record (List.map (fun (f, t) -> (f, gen decls pool t [])) fields)
       | Some { kind = Alias t; _ } -> gen decls pool t seen
       | _ -> Value.Int (next () mod 10))
  | TVar _ -> Value.Int (next () mod 10)
  | TArrow _ -> (match seen with [] -> Value.Unit | _ -> pick seen)   (* the test's own functions *)
  | _ -> Value.Unit

let call_source ~name ~labels args =
  let parts = List.map2 (fun l v ->
      let lit = Value.to_ocaml v in
      match l with
      | Nolabel -> lit
      | Labelled s -> "~" ^ s ^ ":" ^ lit
      | Optional s -> "?" ^ s ^ ":" ^ lit) labels args in
  "(" ^ String.concat " " (name :: parts) ^ ")"

(* What every example input has in common, kept in the generated ones: an
   input no test of the part could have looked like says nothing about the
   part. A sorted array for a binary search, a non-negative count, two strands
   of equal length, a radicand that is a perfect square. Read off the examples, Daikon-style, and only ever used
   to shape inputs, never to excuse a disagreement on them. *)
type invariant = Sorted of int | Distinct of int | Nonneg of int | Positive of int | Same_length of int * int
  | Square of int

let elements = function Value.List l -> Some l | Value.Array a -> Some (Array.to_list a) | _ -> None

let invariants (examples : Spec.example list) arity =
  let col i = List.filter_map (fun ex -> List.nth_opt ex.Spec.args i) examples in
  let all p i = let c = col i in c <> [] && List.for_all p c in
  let sorted v = match elements v with
    | Some l -> let rec ok = function a :: (b :: _ as t) -> Value.compare a b <= 0 && ok t | _ -> true in ok l
    | None -> false in
  let distinct v = match elements v with
    | Some l -> List.length (List.sort_uniq Value.compare l) = List.length l | None -> false in
  let long i = List.exists (fun v -> match elements v with Some l -> List.length l >= 2 | None -> false) (col i) in
  let int_ok p v = match v with Value.Int n -> p n | _ -> false in
  let isqrt n = int_of_float (Float.sqrt (float_of_int n)) in
  let square n = n >= 0 && (let r = isqrt n in List.exists (fun k -> k >= 0 && k * k = n) [ r - 1; r; r + 1 ]) in
  let many_squares i = List.length (List.sort_uniq compare
      (List.filter_map (function Value.Int n when n > 1 -> Some n | _ -> None) (col i))) >= 3 in
  List.concat (List.init arity (fun i ->
      (if all sorted i && long i then [ Sorted i ] else [])
      @ (if all distinct i && long i then [ Distinct i ] else [])
      @ (if all (int_ok (fun n -> n > 0)) i then [ Positive i ]
         else if all (int_ok (fun n -> n >= 0)) i then [ Nonneg i ] else [])
      @ (if all (int_ok square) i && many_squares i then [ Square i ] else [])
      @ List.concat (List.init arity (fun j ->
          if j > i && all (fun _ -> true) i
             && List.for_all (fun ex -> match List.nth_opt ex.Spec.args i, List.nth_opt ex.Spec.args j with
                 | Some a, Some b -> (match elements a, elements b with
                     | Some x, Some y -> List.length x = List.length y | _ -> false)
                 | _ -> false) examples
          then [ Same_length (i, j) ] else []))))

let impose invs (inp : Value.t list) =
  let rebuild orig l = match orig with Value.Array _ -> Value.Array (Array.of_list l) | _ -> Value.List l in
  let arr = Array.of_list inp in
  List.iter (function
      | Sorted i -> (match elements arr.(i) with
          | Some l -> arr.(i) <- rebuild arr.(i) (List.stable_sort Value.compare l) | None -> ())
      | Distinct i -> (match elements arr.(i) with
          | Some l -> arr.(i) <- rebuild arr.(i) (List.sort_uniq Value.compare l) | None -> ())
      | Nonneg i -> (match arr.(i) with Value.Int n -> arr.(i) <- Value.Int (abs n) | _ -> ())
      | Positive i -> (match arr.(i) with Value.Int n -> arr.(i) <- Value.Int (max 1 (abs n)) | _ -> ())
      | Same_length (i, j) -> (match elements arr.(i), elements arr.(j) with
          | Some x, Some y ->
              let n = min (List.length x) (List.length y) in
              let cut l = List.filteri (fun k _ -> k < n) l in
              arr.(i) <- rebuild arr.(i) (cut x); arr.(j) <- rebuild arr.(j) (cut y)
          | _ -> ())
      | Square i -> (match arr.(i) with
          | Value.Int n ->
              let r = int_of_float (Float.sqrt (float_of_int (abs n))) in
              let r = if r = 0 && List.mem (Positive i) invs then 1 else r in
              arr.(i) <- Value.Int (r * r)
          | _ -> ())) invs;
  (* sorting after distinct, distinct after sorting: both hold either way *)
  List.iter (function
      | Sorted i -> (match elements arr.(i) with
          | Some l -> arr.(i) <- rebuild arr.(i) (List.stable_sort Value.compare l) | None -> ())
      | _ -> ()) invs;
  Array.to_list arr

let inputs_for decls (v : Iface.value_spec) (examples : Spec.example list) n =
  let ty = Iface.expand decls v.Iface.vty in
  let args, _ = unarrow ty in
  if args = [] then []
  else
    let pool = List.concat_map (fun ex -> List.concat_map Synth.subvalues ex.Spec.args) examples in
    let seen i = List.filter_map (fun ex -> List.nth_opt ex.Spec.args i) examples in
    let tys = List.map (fun (l, t) -> match l with Optional _ -> t_option t | _ -> t) args in
    let invs = invariants examples (List.length tys) in
    let rec draw acc k =
      if k = 0 || List.length acc >= n then List.rev acc
      else
        let inp = impose invs (List.mapi (fun i t -> gen decls pool t (seen i)) tys) in
        let dup = List.exists (fun a -> List.for_all2 Value.equal a inp) acc
                  || List.exists (fun ex -> List.for_all2 Value.equal ex.Spec.args inp) examples in
        draw (if dup then acc else inp :: acc) (k - 1)
    in
    draw [] (n * 6)

let program (iface : Iface.t) calls =
  "open! Stdlib\nlet __gw_run id f = try print_endline (id ^ \"\\t\" ^ f ()) with e -> print_endline (id ^ \"\\t!\" ^ Printexc.to_string e)\n"
  ^ Probe.result_printers iface
  ^ String.concat "\n" (List.mapi (fun i (name, src) ->
      Printf.sprintf "let () = __gw_run \"%d\" (fun () -> __gw_print_%s %s)" i name src) calls) ^ "\n"

let build_and_run ~env ~dir ~exercise_dir ~module_name ~impl ~main =
  Probe.stage_copy ~src:exercise_dir ~dst:dir;
  Probe.write (Filename.concat dir (module_name ^ ".ml")) impl;
  (* open the part's module the way its own test file does *)
  Probe.write (Filename.concat dir "test.ml") ("open " ^ String.capitalize_ascii module_name ^ "\n" ^ main);
  match Probe.run_cmd ~cwd:dir (Array.append env [| "dune"; "build"; "--profile"; "release"; "./test.exe" |]) with
  | Some 0, _ ->
      let _, out = Probe.run_cmd ~cwd:(Filename.concat dir "_build/default") [| "./test.exe" |] in
      Ok (String.split_on_char '\n' out)
  | _, log -> Error log

let close_enough a b =
  match Literal.of_string_opt a, Literal.of_string_opt b with
  | Some (Value.Float x), Some (Value.Float y) ->
      Float.abs (x -. y) <= 1e-6 *. Float.max 1. (Float.abs y)
  | Some x, Some y -> Value.equal x y
  | _ -> a = b

let differential ~env ~scratch ~exercise_dir ~slug ~(iface : Iface.t) ~examples ~source ~reference ?(per_value = 300) () =
  state := Random.State.make [| 0x5eed; Hashtbl.hash slug |];
  let decls = iface.Iface.decls in
  let calls = List.concat_map (fun (v : Iface.value_spec) ->
      let exs = List.filter_map (fun (t, ex) -> if t = v.Iface.vname then Some ex else None) examples in
      let args, _ = unarrow (Iface.expand decls v.Iface.vty) in
      let labels = List.map fst args in
      List.map (fun inp -> (v.Iface.vname, call_source ~name:v.Iface.vname ~labels inp, inp))
        (inputs_for decls v exs per_value)) iface.Iface.values in
  if calls = [] then Error "no input could be generated"
  else
    let main = program iface (List.map (fun (n, src, _) -> (n, src)) calls) in
    let m = Probe.module_name slug in
    let w = build_and_run ~env ~dir:(Filename.concat scratch (slug ^ "-diff-w")) ~exercise_dir ~module_name:m ~impl:source ~main in
    let r = build_and_run ~env ~dir:(Filename.concat scratch (slug ^ "-diff-r")) ~exercise_dir ~module_name:m ~impl:reference ~main in
    match w, r with
    | Error log, _ -> Error ("written module failed to build beside the generated calls:\n" ^ log)
    | _, Error log -> Error ("reference failed to build beside the generated calls:\n" ^ log)
    | Ok wl, Ok rl ->
        let table l = List.filter_map (fun line -> match String.index_opt line '\t' with
            | Some i -> Some (String.sub line 0 i, String.sub line (i + 1) (String.length line - i - 1))
            | None -> None) l in
        let wt = table wl and rt = table rl in
        let compared = ref 0 and agreed = ref 0 and dis = ref [] and samples = ref [] in
        List.iteri (fun i (name, src, inp) ->
            let id = string_of_int i in
            match List.assoc_opt id rt, List.assoc_opt id wt with
            | Some rv, _ when String.length rv > 0 && rv.[0] = '!' -> ()        (* outside the domain *)
            | Some rv, w ->
                incr compared;
                (match Literal.of_string_opt rv with
                 | Some v -> samples := (name, inp, v) :: !samples | None -> ());
                (match w with
                 | Some wv when close_enough wv rv -> incr agreed
                 | Some wv -> dis := Printf.sprintf "%s = %s, reference %s" src wv rv :: !dis
                 | None -> dis := Printf.sprintf "%s: no output, reference %s" src rv :: !dis)
            | None, _ -> ()) calls;
        Ok { compared = !compared; agreed = !agreed; disagreements = List.rev !dis; samples = List.rev !samples }
