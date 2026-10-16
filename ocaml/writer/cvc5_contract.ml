(* A part, written as a SyGuS problem: the contract cvc5 is booked against.
 *
 * cvc5's SyGuS solver synthesizes a term from a grammar and constraints.
 * This module states the part: one grammar, the same for every part, over
 * integers, booleans and strings; the part's examples as constraints; and the
 * constants the grammar may use, read off the examples by one fixed rule:
 *
 *   - strings: the text of each answer that is not a copy of an input string,
 *     cut where an input occurs; the empty string; each punctuation or space
 *     character the examples contain;
 *   - integers: 0 to 10, 100 and 1000.
 *
 * SyGuS solvers search slowly over free constants; stating them is how the
 * SyGuS string benchmarks are posed. The rule never looks at what a part
 * means, only at its examples' text.
 *
 * What SyGuS's theories cannot state here (lists, floats, chars, records,
 * functions as arguments) is refused in words. *)

open Types

exception Unrepresentable of string

type sort = Int | Bool | Str | Opt of sort

let rec sort t =
  match repr t with
  | TCon ("int", []) -> Int
  | TCon ("bool", []) -> Bool
  | TCon ("string", []) -> Str
  | TCon ("option", [ a ]) ->
      (match sort a with Opt _ -> raise (Unrepresentable "an option of an option") | s -> Opt s)
  | t -> raise (Unrepresentable ("type " ^ Types.to_string t))

let rec sort_name = function
  | Int -> "Int" | Bool -> "Bool" | Str -> "String"
  | Opt s -> "Opt" ^ sort_name s

let smt_string s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter (fun c ->
      if c = '"' then Buffer.add_string b "\"\""
      else if Char.code c < 32 || Char.code c > 126 || c = '\\' then
        Buffer.add_string b (Printf.sprintf "\\u{%x}" (Char.code c))
      else Buffer.add_char b c) s;
  Buffer.add_char b '"';
  Buffer.contents b

let rec value s v =
  match s, v with
  | Int, Value.Int n -> if n < 0 then Printf.sprintf "(- %d)" (- n) else string_of_int n
  | Bool, Value.Bool b -> string_of_bool b
  | Str, Value.String x -> smt_string x
  | Opt s, Value.Con ("None", []) -> Printf.sprintf "(as none%s Opt%s)" (sort_name s) (sort_name s)
  | Opt s, Value.Con ("Some", [ x ]) -> Printf.sprintf "(some%s %s)" (sort_name s) (value s x)
  | _ -> raise (Unrepresentable "a value its type does not describe")

(* The constants the grammar may use, by the rule above. *)
let constants (examples : Spec.example list) =
  let strings_of v = match v with
    | Value.String s -> [ s ]
    | Value.Con ("Some", [ Value.String s ]) -> [ s ]
    | _ -> [] in
  let cut s pieces =
    let pieces = List.filter (fun p -> String.length p > 0) pieces in
    let rec go acc start i =
      if i >= String.length s then List.rev (if i > start then String.sub s start (i - start) :: acc else acc)
      else match List.find_opt (fun p ->
          i + String.length p <= String.length s && String.sub s i (String.length p) = p) pieces with
        | Some p ->
            let acc = if i > start then String.sub s start (i - start) :: acc else acc in
            go acc (i + String.length p) (i + String.length p)
        | None -> go acc start (i + 1) in
    go [] 0 0 in
  let fragments = List.concat_map (fun (ex : Spec.example) ->
      let inputs = List.concat_map strings_of ex.Spec.args in
      List.concat_map (fun o -> cut o inputs) (strings_of ex.Spec.out)) examples in
  let punct = List.concat_map (fun (ex : Spec.example) ->
      List.concat_map (fun v -> List.concat_map (fun s ->
          List.filter_map (fun c ->
              if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') then None
              else Some (String.make 1 c)) (List.init (String.length s) (String.get s))) (strings_of v))
        (ex.Spec.out :: ex.Spec.args)) examples in
  let strs = List.sort_uniq compare ("" :: fragments @ punct) in
  let strs = List.filter (fun s -> String.length s <= 80) strs in
  let strs = List.filteri (fun i _ -> i < 24) strs in
  let ints = List.init 11 Fun.id @ [ 100; 1000 ] in
  (strs, ints)

let grammar ~(params : (string * sort) list) ~out (strs, ints) =
  let of_sort s = List.filter_map (fun (p, s') -> if s' = s then Some p else None) params in
  let opts = List.filter_map (fun (p, s) -> match s with Opt b -> Some (p, b) | _ -> None) params in
  let unwrap b = List.filter_map (fun (p, b') -> if b' = b then Some (Printf.sprintf "(val%s %s)" (sort_name b) p) else None) opts in
  let tests = List.map (fun (p, b) -> Printf.sprintf "((_ is none%s) %s)" (sort_name b) p) opts in
  let uses_str = out = Str || List.exists (fun (_, s) -> s = Str || s = Opt Str) params in
  (* strings are indexed by integers, so a part about text reaches them too *)
  let uses_int = uses_str || out = Int || List.exists (fun (_, s) -> s = Int || s = Opt Int) params in
  let i_rules = String.concat " " (of_sort Int @ unwrap Int @ List.map string_of_int ints
                                   @ [ "(+ I I)"; "(- I I)"; "(* I I)"; "(div I I)"; "(mod I I)"; "(ite B I I)" ]
                                   @ (if uses_str then [ "(str.len S)"; "(str.indexof S S I)"; "(str.to_int S)" ] else [])) in
  let s_rules = String.concat " " (of_sort Str @ unwrap Str @ List.map smt_string strs
                                   @ [ "(str.++ S S)"; "(str.at S I)"; "(str.substr S I I)"; "(str.replace S S S)";
                                       "(str.from_int I)"; "(ite B S S)" ]) in
  let b_rules = String.concat " " (of_sort Bool @ tests @ [ "true"; "false"; "(and B B)"; "(or B B)"; "(not B)"; "(ite B B B)" ]
                                   @ (if uses_int then [ "(= I I)"; "(< I I)"; "(<= I I)" ] else [])
                                   @ (if uses_str then [ "(= S S)"; "(str.prefixof S S)"; "(str.suffixof S S)"; "(str.contains S S)" ] else [])) in
  let start = match out with Int -> "I" | Bool -> "B" | Str -> "S" | Opt _ -> raise (Unrepresentable "an option result") in
  let nts = [ (start, out) ] @ List.filter (fun (n, _) -> n <> start)
                                 ([ ("B", Bool) ] @ (if uses_int then [ ("I", Int) ] else []) @ (if uses_str then [ ("S", Str) ] else [])) in
  let rules n = match n with "I" -> i_rules | "B" -> b_rules | _ -> s_rules in
  Printf.sprintf "(%s)\n  (%s)"
    (String.concat " " (List.map (fun (n, s) -> "(" ^ n ^ " " ^ sort_name s ^ ")") nts))
    (String.concat "\n   " (List.map (fun (n, s) -> "(" ^ n ^ " " ^ sort_name s ^ " (" ^ rules n ^ "))") nts))

let problem ~(params : (string * ty) list) ~out_ty (examples : Spec.example list) =
  let ps = List.mapi (fun i (_, t) -> ("p" ^ string_of_int i, sort t)) params in
  let out = sort out_ty in
  let datatypes = List.sort_uniq compare (List.filter_map (fun (_, s) -> match s with
      | Opt b -> Some (Printf.sprintf "(declare-datatype Opt%s ((none%s) (some%s (val%s %s))))"
                         (sort_name b) (sort_name b) (sort_name b) (sort_name b) (sort_name b))
      | _ -> None) ps) in
  let consts = constants examples in
  String.concat "\n" (
    [ "(set-logic ALL)" ] @ datatypes
    @ [ Printf.sprintf "(synth-fun f (%s) %s\n  %s)"
          (String.concat " " (List.map (fun (p, s) -> "(" ^ p ^ " " ^ sort_name s ^ ")") ps))
          (sort_name out) (grammar ~params:ps ~out consts) ]
    @ List.map (fun (ex : Spec.example) ->
        let call = if ps = [] then "f"
          else "(f " ^ String.concat " " (List.map2 (fun (_, s) v -> value s v) ps ex.Spec.args) ^ ")" in
        Printf.sprintf "(constraint (= %s %s))" call (value out ex.Spec.out)) examples
    @ [ "(check-synth)" ]) ^ "\n"

(* ---------------------------------------------- cvc5's answer, as OCaml *)

type sexp = Atom of string | Str_lit of string | List of sexp list

let parse s =
  let n = String.length s in
  let rec skip i = if i < n && (s.[i] = ' ' || s.[i] = '\n' || s.[i] = '\t' || s.[i] = '\r') then skip (i + 1) else i in
  let rec one i =
    let i = skip i in
    if i >= n then failwith "unexpected end"
    else if s.[i] = '(' then
      let rec items acc i =
        let i = skip i in
        if i < n && s.[i] = ')' then (List (List.rev acc), i + 1)
        else let x, i = one i in items (x :: acc) i in
      items [] (i + 1)
    else if s.[i] = '"' then
      let b = Buffer.create 16 in
      let rec str i =
        if i >= n then failwith "unterminated string"
        else if s.[i] = '"' then
          if i + 1 < n && s.[i + 1] = '"' then (Buffer.add_char b '"'; str (i + 2))
          else (Str_lit (Buffer.contents b), i + 1)
        else if s.[i] = '\\' && i + 2 < n && s.[i + 1] = 'u' && s.[i + 2] = '{' then
          let j = String.index_from s i '}' in
          Buffer.add_char b (Char.chr (int_of_string ("0x" ^ String.sub s (i + 3) (j - i - 3))));
          str (j + 1)
        else (Buffer.add_char b s.[i]; str (i + 1)) in
      str (i + 1)
    else
      let j = ref i in
      while !j < n && not (List.mem s.[!j] [ ' '; '\n'; '\t'; '\r'; '('; ')' ]) do incr j done;
      (Atom (String.sub s i (!j - i)), !j) in
  fst (one 0)

(* SMT-LIB's operators, each by an OCaml expression of the same meaning on
   every input (division and modulus are Euclidean there, and total). *)
let helpers = {|let gw_div a b = if b = 0 then 0 else let q = a / b in if a mod b < 0 then (if b > 0 then q - 1 else q + 1) else q
let gw_mod a b = if b = 0 then a else let m = a mod b in if m < 0 then m + abs b else m
let gw_at s i = if i >= 0 && i < String.length s then String.make 1 s.[i] else ""
let gw_substr s i n = if i >= 0 && n > 0 && i < String.length s then String.sub s i (min n (String.length s - i)) else ""
let gw_indexof s t i =
  let n = String.length s and m = String.length t in
  if i < 0 || i > n then -1
  else let rec go k = if k + m > n then -1 else if String.sub s k m = t then k else go (k + 1) in go i
let gw_contains s t = gw_indexof s t 0 >= 0
let gw_replace s t u = if t = "" then u ^ s else
  let k = gw_indexof s t 0 in if k < 0 then s else String.sub s 0 k ^ u ^ String.sub s (k + String.length t) (String.length s - k - String.length t)
let gw_to_int s = if s <> "" && String.for_all (fun c -> c >= '0' && c <= '9') s then int_of_string s else -1
let gw_from_int n = if n < 0 then "" else string_of_int n|}

let rec ocaml = function
  | Atom ("true" | "false" as b) -> b
  | Atom a when a <> "" && (a.[0] = '-' || (a.[0] >= '0' && a.[0] <= '9')) -> "(" ^ a ^ ")"
  | Atom a -> a
  | Str_lit s -> Printf.sprintf "%S" s
  | List [ List [ Atom "_"; Atom "is"; Atom c ]; x ] when String.length c >= 4 && String.sub c 0 4 = "none" ->
      Printf.sprintf "(%s = None)" (ocaml x)
  | List [ Atom "as"; Atom c; _ ] when String.length c >= 4 && String.sub c 0 4 = "none" -> "None"
  | List [ Atom c; x ] when String.length c >= 3 && String.sub c 0 3 = "val" ->
      Printf.sprintf "(match %s with Some v -> v | None -> raise Not_found)" (ocaml x)
  | List [ Atom c; x ] when String.length c >= 4 && String.sub c 0 4 = "some" -> Printf.sprintf "(Some %s)" (ocaml x)
  | List [ Atom "ite"; c; a; b ] -> Printf.sprintf "(if %s then %s else %s)" (ocaml c) (ocaml a) (ocaml b)
  | List [ Atom "-"; a ] -> Printf.sprintf "(- %s)" (ocaml a)
  | List [ Atom "not"; a ] -> Printf.sprintf "(not %s)" (ocaml a)
  | List (Atom op :: args) ->
      let a = List.map ocaml args in
      let bin o = match a with
        | [ x; y ] -> Printf.sprintf "(%s %s %s)" x o y
        | x :: rest -> List.fold_left (fun acc y -> Printf.sprintf "(%s %s %s)" acc o y) x rest
        | [] -> failwith ("empty " ^ op) in
      (match op, a with
       | ("+" | "-" | "*"), _ -> bin op
       | "=", _ -> bin "="
       | "<", _ -> bin "<" | "<=", _ -> bin "<=" | ">", _ -> bin ">" | ">=", _ -> bin ">="
       | "and", _ -> bin "&&" | "or", _ -> bin "||"
       | "=>", [ x; y ] -> Printf.sprintf "((not %s) || %s)" x y
       | "div", [ x; y ] -> Printf.sprintf "(gw_div %s %s)" x y
       | "mod", [ x; y ] -> Printf.sprintf "(gw_mod %s %s)" x y
       | "str.++", _ -> bin "^"
       | "str.len", [ x ] -> Printf.sprintf "(String.length %s)" x
       | "str.at", [ x; i ] -> Printf.sprintf "(gw_at %s %s)" x i
       | "str.substr", [ x; i; n ] -> Printf.sprintf "(gw_substr %s %s %s)" x i n
       | "str.indexof", [ x; t; i ] -> Printf.sprintf "(gw_indexof %s %s %s)" x t i
       | "str.replace", [ x; t; u ] -> Printf.sprintf "(gw_replace %s %s %s)" x t u
       | "str.contains", [ x; t ] -> Printf.sprintf "(gw_contains %s %s)" x t
       | "str.prefixof", [ p; x ] -> Printf.sprintf "(String.starts_with ~prefix:%s %s)" p x
       | "str.suffixof", [ p; x ] -> Printf.sprintf "(String.ends_with ~suffix:%s %s)" p x
       | "str.to_int", [ x ] -> Printf.sprintf "(gw_to_int %s)" x
       | ("str.from_int" | "int.to.str"), [ x ] -> Printf.sprintf "(gw_from_int %s)" x
       | _ -> failwith ("an operator the lowering does not know: " ^ op))
  | List _ -> failwith "an unexpected term"

(* "(\n(define-fun f ((p0 Int)) T body)\n)" -> the body as OCaml *)
let answer text =
  match parse text with
  | List [ List [ Atom "define-fun"; Atom _; _; _; body ] ] -> ocaml body
  | List [ Atom "define-fun"; Atom _; _; _; body ] -> ocaml body
  | _ -> failwith "not a definition"

let definition ~name ~(params : (string * label) list) body =
  let pnames = List.mapi (fun i _ -> "p" ^ string_of_int i) params in
  let outer = List.map2 (fun p (_, l) -> match l with
      | Labelled s -> "~" ^ s ^ ":" ^ p | Optional s -> "?" ^ s ^ ":" ^ p | Nolabel -> p) pnames params in
  Printf.sprintf "let %s %s = %s" name (String.concat " " outer) body
