(* The writer's vocabulary: OCaml's Stdlib, by name, and nothing else.
 *
 * This is the competence the talent holds before any booking. It is generic
 * by rule: an entry is a Stdlib function (or a one-line composition of them,
 * printed as such), never a helper shaped for one exercise. A component named
 * after a problem would be an answer smuggled in as vocabulary, and the
 * program "derived" from it would be written by whoever wrote the component.
 *
 * Each entry carries its type scheme (TGen for its own quantified variables),
 * its meaning as an OCaml function on values, and how it prints. A partial
 * component raises, and the evaluator reads the raise as "no value here". *)

open Types

type t = {
  name : string;
  scheme : ty;
  impl : Value.t list -> Value.t;
  ocaml : string list -> string;
}

exception Undefined

let a = TGen 0 and b = TGen 1 and c = TGen 2

let apply f x = match Value.as_function f with Some g -> g x | None -> raise Undefined
let apply2 f x y = apply (apply f x) y

let int = function Value.Int n -> n | _ -> raise Undefined
let bool = function Value.Bool v -> v | _ -> raise Undefined
let str = function Value.String s -> s | _ -> raise Undefined
let chr = function Value.Char c -> c | _ -> raise Undefined
let lst = function Value.List l -> l | _ -> raise Undefined
let flt = function Value.Float f -> f | _ -> raise Undefined
let i64 = function Value.Int64 n -> n | _ -> raise Undefined

let infix op = function [ x; y ] -> "(" ^ x ^ " " ^ op ^ " " ^ y ^ ")" | _ -> assert false
let prefix f args = "(" ^ String.concat " " (f :: args) ^ ")"

let mk name scheme impl ocaml = { name; scheme; impl; ocaml }
let fn name scheme impl = mk name scheme impl (prefix name)
let op name scheme impl = mk name scheme impl (infix name)

let un f = function [ x ] -> f x | _ -> raise Undefined
let bin f = function [ x; y ] -> f x y | _ -> raise Undefined
let tri f = function [ x; y; z ] -> f x y z | _ -> raise Undefined

let iarith name f = op name (arrows [ t_int; t_int ] t_int)
    (bin (fun x y -> Value.Int (f (int x) (int y))))
let cmp name f = op name (arrows [ a; a ] t_bool)
    (bin (fun x y -> Value.Bool (f (Value.compare x y) 0)))
let farith name f = op name (arrows [ t_float; t_float ] t_float)
    (bin (fun x y -> Value.Float (f (flt x) (flt y))))

(* Results past this size are not values the search can afford: a step that
   doubles a string along a 64-step recursion would otherwise exhaust memory
   before any check could reject it. *)
let cap = 50_000
let small_s s = if String.length s > cap then raise Undefined else Value.String s
let small_l l = if List.length l > cap then raise Undefined else Value.List l

let explode s = List.init (String.length s) (fun i -> Value.Char s.[i])
let implode l = String.init (List.length l) (fun i -> chr (List.nth l i))

let all : t list = [
  (* integers *)
  iarith "+" ( + ); iarith "-" ( - ); iarith "*" ( * );
  iarith "/" (fun x y -> if y = 0 then raise Undefined else x / y);
  iarith "mod" (fun x y -> if y = 0 then raise Undefined else x mod y);
  iarith "land" ( land ); iarith "lor" ( lor ); iarith "lxor" ( lxor );
  iarith "lsl" (fun x y -> if y < 0 || y > 62 then raise Undefined else x lsl y);
  iarith "lsr" (fun x y -> if y < 0 || y > 62 then raise Undefined else x lsr y);
  fn "abs" (arrow t_int t_int) (un (fun x -> Value.Int (abs (int x))));
  mk "~-" (arrow t_int t_int) (un (fun x -> Value.Int (- (int x))))
    (function [ x ] -> "(- " ^ x ^ ")" | _ -> assert false);
  fn "succ" (arrow t_int t_int) (un (fun x -> Value.Int (int x + 1)));
  fn "pred" (arrow t_int t_int) (un (fun x -> Value.Int (int x - 1)));
  fn "max" (arrows [ a; a ] a) (bin (fun x y -> if Value.compare x y >= 0 then x else y));
  fn "min" (arrows [ a; a ] a) (bin (fun x y -> if Value.compare x y <= 0 then x else y));
  fn "compare" (arrows [ a; a ] t_int) (bin (fun x y -> Value.Int (Value.compare x y)));
  (* comparison and logic *)
  cmp "=" ( = ); cmp "<>" ( <> ); cmp "<" ( < ); cmp ">" ( > ); cmp "<=" ( <= ); cmp ">=" ( >= );
  op "&&" (arrows [ t_bool; t_bool ] t_bool) (bin (fun x y -> Value.Bool (bool x && bool y)));
  op "||" (arrows [ t_bool; t_bool ] t_bool) (bin (fun x y -> Value.Bool (bool x || bool y)));
  fn "not" (arrow t_bool t_bool) (un (fun x -> Value.Bool (not (bool x))));
  (* floats *)
  farith "+." ( +. ); farith "-." ( -. ); farith "*." ( *. ); farith "/." ( /. );
  farith "**" ( ** );
  fn "sqrt" (arrow t_float t_float) (un (fun x -> Value.Float (sqrt (flt x))));
  fn "float_of_int" (arrow t_int t_float) (un (fun x -> Value.Float (float_of_int (int x))));
  fn "int_of_float" (arrow t_float t_int) (un (fun x -> Value.Int (int_of_float (flt x))));
  (* int64 *)
  fn "Int64.of_int" (arrow t_int t_int64) (un (fun x -> Value.Int64 (Int64.of_int (int x))));
  fn "Int64.to_int" (arrow t_int64 t_int) (un (fun x -> Value.Int (Int64.to_int (i64 x))));
  (* strings and chars *)
  op "^" (arrows [ t_string; t_string ] t_string)
    (bin (fun x y -> if String.length (str x) + String.length (str y) > cap then raise Undefined
           else Value.String (str x ^ str y)));
  fn "String.length" (arrow t_string t_int) (un (fun s -> Value.Int (String.length (str s))));
  mk "String.get" (arrows [ t_string; t_int ] t_char)
    (bin (fun s i -> let s = str s and i = int i in
           if i < 0 || i >= String.length s then raise Undefined else Value.Char s.[i]))
    (function [ s; i ] -> s ^ ".[" ^ i ^ "]" | _ -> assert false);
  fn "String.sub" (arrows [ t_string; t_int; t_int ] t_string)
    (tri (fun s i n -> let s = str s and i = int i and n = int n in
           if i < 0 || n < 0 || i + n > String.length s then raise Undefined
           else Value.String (String.sub s i n)));
  fn "String.make" (arrows [ t_int; t_char ] t_string)
    (bin (fun n ch -> let n = int n in
           if n < 0 || n > 10_000 then raise Undefined else Value.String (String.make n (chr ch))));
  fn "String.concat" (arrows [ t_string; t_list t_string ] t_string)
    (bin (fun sep l ->
         let parts = List.map str (lst l) in
         if List.fold_left (fun n p -> n + String.length p + String.length (str sep)) 0 parts > cap then raise Undefined
         else Value.String (String.concat (str sep) parts)));
  fn "String.uppercase_ascii" (arrow t_string t_string)
    (un (fun s -> Value.String (String.uppercase_ascii (str s))));
  fn "String.lowercase_ascii" (arrow t_string t_string)
    (un (fun s -> Value.String (String.lowercase_ascii (str s))));
  fn "String.capitalize_ascii" (arrow t_string t_string)
    (un (fun s -> Value.String (String.capitalize_ascii (str s))));
  fn "String.trim" (arrow t_string t_string) (un (fun s -> Value.String (String.trim (str s))));
  fn "String.split_on_char" (arrows [ t_char; t_string ] (t_list t_string))
    (bin (fun ch s -> Value.List (List.map (fun x -> Value.String x)
                                    (String.split_on_char (chr ch) (str s)))));
  fn "String.contains" (arrows [ t_string; t_char ] t_bool)
    (bin (fun s ch -> Value.Bool (String.contains (str s) (chr ch))));
  fn "String.map" (arrows [ arrow t_char t_char; t_string ] t_string)
    (bin (fun f s -> Value.String (String.map (fun ch -> chr (apply f (Value.Char ch))) (str s))));
  fn "String.init" (arrows [ t_int; arrow t_int t_char ] t_string)
    (bin (fun n f -> let n = int n in
           if n < 0 || n > 10_000 then raise Undefined
           else Value.String (String.init n (fun i -> chr (apply f (Value.Int i))))));
  fn "String.exists" (arrows [ arrow t_char t_bool; t_string ] t_bool)
    (bin (fun f s -> Value.Bool (String.exists (fun c -> bool (apply f (Value.Char c))) (str s))));
  fn "String.for_all" (arrows [ arrow t_char t_bool; t_string ] t_bool)
    (bin (fun f s -> Value.Bool (String.for_all (fun c -> bool (apply f (Value.Char c))) (str s))));
  mk "String.starts_with" (arrows [ t_string; t_string ] t_bool)
    (bin (fun p s -> Value.Bool (String.starts_with ~prefix:(str p) (str s))))
    (function [ p; s ] -> "(String.starts_with ~prefix:" ^ p ^ " " ^ s ^ ")" | _ -> assert false);
  mk "String.ends_with" (arrows [ t_string; t_string ] t_bool)
    (bin (fun p s -> Value.Bool (String.ends_with ~suffix:(str p) (str s))))
    (function [ p; s ] -> "(String.ends_with ~suffix:" ^ p ^ " " ^ s ^ ")" | _ -> assert false);
  fn "String.index_opt" (arrows [ t_string; t_char ] (t_option t_int))
    (bin (fun s c -> match String.index_opt (str s) (chr c) with
         | Some i -> Value.Con ("Some", [ Value.Int i ]) | None -> Value.Con ("None", [])));
  fn "string_of_int" (arrow t_int t_string) (un (fun x -> Value.String (string_of_int (int x))));
  fn "int_of_string_opt" (arrow t_string (t_option t_int))
    (un (fun s -> match int_of_string_opt (str s) with
         | Some n -> Value.Con ("Some", [ Value.Int n ]) | None -> Value.Con ("None", [])));
  mk "explode" (arrow t_string (t_list t_char)) (un (fun s -> Value.List (explode (str s))))
    (function [ s ] -> "(List.of_seq (String.to_seq " ^ s ^ "))" | _ -> assert false);
  mk "implode" (arrow (t_list t_char) t_string) (un (fun l -> Value.String (implode (lst l))))
    (function [ l ] -> "(String.of_seq (List.to_seq " ^ l ^ "))" | _ -> assert false);
  mk "String.of_char" (arrow t_char t_string) (un (fun ch -> Value.String (String.make 1 (chr ch))))
    (function [ ch ] -> "(String.make 1 " ^ ch ^ ")" | _ -> assert false);
  fn "Char.code" (arrow t_char t_int) (un (fun ch -> Value.Int (Char.code (chr ch))));
  fn "Char.chr" (arrow t_int t_char)
    (un (fun n -> let n = int n in if n < 0 || n > 255 then raise Undefined else Value.Char (Char.chr n)));
  fn "Char.uppercase_ascii" (arrow t_char t_char) (un (fun ch -> Value.Char (Char.uppercase_ascii (chr ch))));
  fn "Char.lowercase_ascii" (arrow t_char t_char) (un (fun ch -> Value.Char (Char.lowercase_ascii (chr ch))));
  (* lists *)
  op "::" (arrows [ a; t_list a ] (t_list a)) (bin (fun x l -> small_l (x :: lst l)));
  op "@" (arrows [ t_list a; t_list a ] (t_list a))
    (bin (fun x y -> if List.length (lst x) + List.length (lst y) > cap then raise Undefined
           else Value.List (lst x @ lst y)));
  fn "List.length" (arrow (t_list a) t_int) (un (fun l -> Value.Int (List.length (lst l))));
  fn "List.rev" (arrow (t_list a) (t_list a)) (un (fun l -> Value.List (List.rev (lst l))));
  fn "List.hd" (arrow (t_list a) a) (un (fun l -> match lst l with x :: _ -> x | [] -> raise Undefined));
  fn "List.tl" (arrow (t_list a) (t_list a))
    (un (fun l -> match lst l with _ :: t -> Value.List t | [] -> raise Undefined));
  fn "List.nth" (arrows [ t_list a; t_int ] a)
    (bin (fun l n -> let l = lst l and n = int n in
           if n < 0 || n >= List.length l then raise Undefined else List.nth l n));
  fn "List.nth_opt" (arrows [ t_list a; t_int ] (t_option a))
    (bin (fun l n -> let n = int n in
           if n < 0 then raise Undefined
           else match List.nth_opt (lst l) n with
             | Some x -> Value.Con ("Some", [ x ]) | None -> Value.Con ("None", [])));
  fn "List.map" (arrows [ arrow a b; t_list a ] (t_list b))
    (bin (fun f l -> Value.List (List.map (apply f) (lst l))));
  fn "List.mapi" (arrows [ arrows [ t_int; a ] b; t_list a ] (t_list b))
    (bin (fun f l -> Value.List (List.mapi (fun i x -> apply2 f (Value.Int i) x) (lst l))));
  fn "List.filter" (arrows [ arrow a t_bool; t_list a ] (t_list a))
    (bin (fun f l -> Value.List (List.filter (fun x -> bool (apply f x)) (lst l))));
  fn "List.filter_map" (arrows [ arrow a (t_option b); t_list a ] (t_list b))
    (bin (fun f l -> Value.List (List.filter_map (fun x -> match apply f x with
         | Value.Con ("Some", [ y ]) -> Some y | _ -> None) (lst l))));
  fn "List.concat_map" (arrows [ arrow a (t_list b); t_list a ] (t_list b))
    (bin (fun f l -> small_l (List.concat_map (fun x -> lst (apply f x)) (lst l))));
  fn "List.fold_left" (arrows [ arrows [ b; a ] b; b; t_list a ] b)
    (tri (fun f z l -> List.fold_left (apply2 f) z (lst l)));
  fn "List.fold_right" (arrows [ arrows [ a; b ] b; t_list a; b ] b)
    (tri (fun f l z -> List.fold_right (apply2 f) (lst l) z));
  fn "List.filteri" (arrows [ arrows [ t_int; a ] t_bool; t_list a ] (t_list a))
    (bin (fun f l -> Value.List (List.filteri (fun i x -> bool (apply2 f (Value.Int i) x)) (lst l))));
  fn "List.find_map" (arrows [ arrow a (t_option b); t_list a ] (t_option b))
    (bin (fun f l -> match List.find_map (fun x -> match apply f x with
         | Value.Con ("Some", [ y ]) -> Some y | _ -> None) (lst l) with
         | Some y -> Value.Con ("Some", [ y ]) | None -> Value.Con ("None", [])));
  fn "List.partition" (arrows [ arrow a t_bool; t_list a ] (TTuple [ t_list a; t_list a ]))
    (bin (fun f l -> let y, n = List.partition (fun x -> bool (apply f x)) (lst l) in
           Value.Tuple [ Value.List y; Value.List n ]));
  fn "List.exists" (arrows [ arrow a t_bool; t_list a ] t_bool)
    (bin (fun f l -> Value.Bool (List.exists (fun x -> bool (apply f x)) (lst l))));
  fn "List.for_all" (arrows [ arrow a t_bool; t_list a ] t_bool)
    (bin (fun f l -> Value.Bool (List.for_all (fun x -> bool (apply f x)) (lst l))));
  fn "List.mem" (arrows [ a; t_list a ] t_bool)
    (bin (fun x l -> Value.Bool (List.exists (Value.equal x) (lst l))));
  fn "List.concat" (arrow (t_list (t_list a)) (t_list a)) (un (fun l -> small_l (List.concat_map lst (lst l))));
  fn "List.init" (arrows [ t_int; arrow t_int a ] (t_list a))
    (bin (fun n f -> let n = int n in
           if n < 0 || n > 10_000 then raise Undefined
           else Value.List (List.init n (fun i -> apply f (Value.Int i)))));
  mk "List.sort" (arrow (t_list a) (t_list a))
    (un (fun l -> Value.List (List.stable_sort Value.compare (lst l))))
    (function [ l ] -> "(List.sort compare " ^ l ^ ")" | _ -> assert false);
  mk "List.sort_uniq" (arrow (t_list a) (t_list a))
    (un (fun l -> Value.List (List.sort_uniq Value.compare (lst l))))
    (function [ l ] -> "(List.sort_uniq compare " ^ l ^ ")" | _ -> assert false);
  fn "List.assoc_opt" (arrows [ a; t_list (TTuple [ a; b ]) ] (t_option b))
    (bin (fun k l -> match List.find_opt (function
         | Value.Tuple [ k'; _ ] -> Value.equal k k' | _ -> false) (lst l) with
         | Some (Value.Tuple [ _; v ]) -> Value.Con ("Some", [ v ]) | _ -> Value.Con ("None", [])));
  fn "List.find_opt" (arrows [ arrow a t_bool; t_list a ] (t_option a))
    (bin (fun f l -> match List.find_opt (fun x -> bool (apply f x)) (lst l) with
         | Some x -> Value.Con ("Some", [ x ]) | None -> Value.Con ("None", [])));
  fn "List.combine" (arrows [ t_list a; t_list b ] (t_list (TTuple [ a; b ])))
    (bin (fun x y -> let x = lst x and y = lst y in
           if List.length x <> List.length y then raise Undefined
           else Value.List (List.map2 (fun p q -> Value.Tuple [ p; q ]) x y)));
  fn "List.split" (arrow (t_list (TTuple [ a; b ])) (TTuple [ t_list a; t_list b ]))
    (un (fun l -> let p = List.map (function Value.Tuple [ x; y ] -> (x, y) | _ -> raise Undefined) (lst l) in
           Value.Tuple [ Value.List (List.map fst p); Value.List (List.map snd p) ]));
  (* options and pairs *)
  mk "Option.value" (arrows [ t_option a; a ] a)
    (bin (fun o d -> match o with Value.Con ("Some", [ x ]) -> x | _ -> d))
    (function [ o; d ] -> "(Option.value " ^ o ^ " ~default:" ^ d ^ ")" | _ -> assert false);
  fn "Option.map" (arrows [ arrow a b; t_option a ] (t_option b))
    (bin (fun f o -> match o with Value.Con ("Some", [ x ]) -> Value.Con ("Some", [ apply f x ]) | v -> v));
  fn "Option.is_some" (arrow (t_option a) t_bool)
    (un (function Value.Con ("Some", _) -> Value.Bool true | _ -> Value.Bool false));
  fn "fst" (arrow (TTuple [ a; b ]) a) (un (function Value.Tuple [ x; _ ] -> x | _ -> raise Undefined));
  fn "snd" (arrow (TTuple [ a; b ]) b) (un (function Value.Tuple [ _; y ] -> y | _ -> raise Undefined));
  (* arrays, read only *)
  fn "Array.to_list" (arrow (t_array a) (t_list a))
    (un (function Value.Array xs -> Value.List (Array.to_list xs) | _ -> raise Undefined));
  fn "Array.of_list" (arrow (t_list a) (t_array a)) (un (fun l -> Value.Array (Array.of_list (lst l))));
  fn "Array.length" (arrow (t_array a) t_int)
    (un (function Value.Array xs -> Value.Int (Array.length xs) | _ -> raise Undefined));
  mk "Array.get" (arrows [ t_array a; t_int ] a)
    (bin (fun arr i -> match arr with
         | Value.Array xs -> let i = int i in
           if i < 0 || i >= Array.length xs then raise Undefined else xs.(i)
         | _ -> raise Undefined))
    (function [ arr; i ] -> arr ^ ".(" ^ i ^ ")" | _ -> assert false);
]

let find name = List.find (fun c -> c.name = name) all
let _ = c
let _ = small_s

(* Values the part itself has already been given, offered back as vocabulary
   for its later values: `difference_of_squares` may call `square_of_sum`. They
   are the part's own interface, not outside help, and they are cleared with
   each part. *)
let siblings : (string, int) Hashtbl.t = Hashtbl.create 4
