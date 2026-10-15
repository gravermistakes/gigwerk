(* Running a term. Every run is bounded by fuel, so a candidate that loops is
 * a candidate without a value, not a hung search. A partial component, a
 * failed match, an unbound name: all of them are "no value here" (Stuck),
 * which a candidate can be judged on like any other outcome. *)

open Expr

exception Stuck
exception Out_of_fuel

let fuel = ref 0

let tick () = decr fuel; if !fuel < 0 then raise Out_of_fuel

let components : (string, Components.t) Hashtbl.t =
  let t = Hashtbl.create 128 in
  List.iter (fun c -> Hashtbl.replace t c.Components.name c) Components.all; t

let rec matches p (v : Value.t) acc =
  match p, v with
  | PVar x, _ -> Some ((x, v) :: acc)
  | PWild, _ -> Some acc
  | PNil, Value.List [] -> Some acc
  | PCons (ph, pt), Value.List (h :: t) ->
      Option.bind (matches ph h acc) (matches pt (Value.List t))
  | PCon (c, ps), Value.Con (d, vs) when c = d && List.length ps = List.length vs ->
      many ps vs acc
  | PCon (c, [ p ]), Value.Con (d, vs) when c = d && List.length vs > 1 ->
      matches p (Value.Tuple vs) acc
  | PPoly (c, None), Value.Poly (d, None) when c = d -> Some acc
  | PPoly (c, Some p), Value.Poly (d, Some v) when c = d -> matches p v acc
  | PTuple ps, Value.Tuple vs when List.length ps = List.length vs -> many ps vs acc
  | PLit l, _ -> if Value.equal l v then Some acc else None
  | _ -> None
and many ps vs acc =
  match ps, vs with
  | [], [] -> Some acc
  | p :: ps, v :: vs -> Option.bind (matches p v acc) (many ps vs)
  | _ -> None

let rec eval env e : Value.t =
  tick ();
  match e with
  | Var x -> (match List.assoc_opt x env with Some v -> v | None -> raise Stuck)
  | Lit v -> v
  | Call (name, args) ->
      let c = match Hashtbl.find_opt components name with Some c -> c | None -> raise Stuck in
      let vs = List.map (eval env) args in
      (try c.Components.impl vs with
       | Components.Undefined | Division_by_zero | Invalid_argument _ | Failure _
       | Not_found | Value.Not_comparable -> raise Stuck)
  | App (f, args) ->
      let fv = eval env f in
      List.fold_left (fun f a ->
          match f with Value.Fun g -> tick (); g (eval env a) | _ -> raise Stuck) fv args
  | Lam (xs, body) -> closure env xs body
  | Con (c, args) -> Value.Con (c, List.map (eval env) args)
  | Poly (c, None) -> Value.Poly (c, None)
  | Poly (c, Some a) -> Value.Poly (c, Some (eval env a))
  | Tuple args -> Value.Tuple (List.map (eval env) args)
  | Record fs -> Value.Record (List.map (fun (f, e) -> (f, eval env e)) fs)
  | Field (e, f) ->
      (match eval env e with
       | Value.Record fs -> (match List.assoc_opt f fs with Some v -> v | None -> raise Stuck)
       | _ -> raise Stuck)
  | If (c, a, b) ->
      (match eval env c with
       | Value.Bool true -> eval env a
       | Value.Bool false -> eval env b
       | _ -> raise Stuck)
  | Match (scrut, branches) ->
      let v = eval env scrut in
      let rec go = function
        | [] -> raise Stuck
        | (p, body) :: rest ->
            (match matches p v [] with
             | Some binds -> eval (binds @ env) body
             | None -> go rest)
      in
      go branches
  | Let (false, x, a, b) -> eval ((x, eval env a) :: env) b
  | Let (true, x, a, b) ->
      let self = ref (Value.Fun (fun _ -> raise Stuck)) in
      let env' = (x, Value.Fun (fun v -> match !self with Value.Fun g -> g v | _ -> raise Stuck)) :: env in
      self := eval env' a;
      eval env' b

and closure env xs body =
  match xs with
  | [] -> eval env body
  | x :: rest -> Value.Fun (fun v -> closure ((x, v) :: env) rest body)

(* One run, bounded. None when the term gets stuck or runs out of fuel. *)
let run ?(budget = 20_000) env e =
  fuel := budget;
  try Some (eval env e) with
  | Stuck | Out_of_fuel | Stack_overflow -> None
