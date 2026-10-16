open Synquid_backend

let passed = ref 0
let require name ok = if ok then incr passed else failwith name
let contains s part = try ignore (Str.search_forward (Str.regexp_string part) s 0); true with Not_found -> false
let ctor source arity family output = { source; arity; family; output }
let constructors = [
  ctor "Nil" 0 "List" List_nil;
  ctor "Cons" 2 "List" List_cons;
  ctor "None" 0 "Option" (Named "None");
  ctor "Some" 1 "Option" (Named "Some");
  ctor "Pair" 2 "Pair" Tuple;
  ctor "Empty" 0 "Tree" (Named "Empty");
  ctor "Node" 3 "Tree" (Named "Node")
]
let lower s = translate ~constructors ~primitives:[] s
let expect name s parts = match lower s with
  | Error e -> failwith (name ^ ": " ^ e)
  | Ok code -> List.iter (fun part -> require (name ^ ": " ^ part) (contains code part)) parts
let reject name s = match lower s with Error _ -> incr passed | Ok _ -> failwith name

let () =
  expect "one argument" "f = \\xs . xs\n" ["let rec f"; "fun xs ->"];
  expect "numeric literals" "f = \\x . x + 1\n" ["x + 1"];
  expect "bool literal" "f = \\x . True\n" ["true"];
  expect "negative literal" "f = \\x . -1\n" ["-1"];
  expect "list constructors" "f = \\x . Cons x Nil\n" ["x :: []"];
  expect "option constructor" "f = \\x . Some x\n" ["Some (x)"];
  expect "pair" "f = \\x . \\y . Pair x y\n" ["(x, y)"];
  expect "complete list match" "f = \\xs .\n  match xs with\n    Nil -> 0\n    Cons h t -> 1 + (f t)\n" ["| [] ->"; "| h :: t ->"];
  expect "nested match layout" "f = \\xs .\n  match xs with\n    Nil -> None\n    Cons h t ->\n      match t with\n        Nil -> Some h\n        Cons h2 t2 -> f t\n" ["match t with"; "| h2 :: t2 ->"];
  expect "nested match followed by outer branch" "f = \\xs .\n  match xs with\n    Cons h t ->\n      match t with\n        Nil -> Some h\n        Cons h2 t2 -> f t\n    Nil -> None\n" ["| [] ->"; "None"];
  expect "if" "f = \\x . if x == 0 then 1 else x\n" ["x = 0"; "then"; "else"];
  expect "let" "f = \\x . let y = x + 1 in y\n" ["let y ="; " in "];
  expect "multiple definitions" "f :: x:Int -> Int\nf = \\x . g x\ng :: x:Int -> Int\ng = \\x . x\n(Goals: 2)\n" ["let rec f"; "and g"];
  expect "higher-order argument" "f = \\g . \\x . g x\n" ["g (x)"];
  expect "local lambda" "f = \\x . let g = (\\y . y) in g x\n" ["fun y ->"; "g (x)"];
  reject "hole rejected" "f = \\x . ??\n";
  reject "error rejected" "f = \\x . error\n";
  reject "unknown symbol rejected" "f = \\x . system x\n";
  reject "partial constructor rejected" "f = \\x . Node x\n";
  reject "partial match rejected" "f = \\xs . match xs with\n  Nil -> Nil\n";
  reject "duplicate pattern rejected" "f = \\xs . match xs with\n  Nil -> Nil\n  Nil -> Nil\n";
  reject "wrong pattern arity rejected" "f = \\xs . match xs with\n  Nil -> Nil\n  Cons h -> Nil\n";
  reject "duplicate binders rejected" "f = \\x . \\x . x\n";
  reject "unbound variable rejected" "f = \\x . y\n";
  reject "reserved identifier rejected" "f = \\type . type\n";
  reject "duplicate goal rejected" "f = \\x . x\nf = \\y . y\n";
  let invalid_context name context =
    match translate ~constructors:context ~primitives:[] "f = \\x . Nil\n" with
    | Error _ -> incr passed
    | Ok _ -> failwith name
  in
  invalid_context "invalid emitted constructor name" [ctor "Nil" 0 "X" (Named "Bad; failwith")];
  invalid_context "negative constructor arity" [ctor "Nil" (-1) "X" List_nil];
  invalid_context "duplicate constructor manifest" [ctor "Nil" 0 "X" List_nil; ctor "Nil" 0 "X" List_nil];
  Printf.printf "PASS: %d generic backend assertions\n" !passed
