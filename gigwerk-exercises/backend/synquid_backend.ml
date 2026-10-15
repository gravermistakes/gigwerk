(* Pure syntax backend for generated Synquid terms. No exercise algorithms. *)
type constructor_output = Named of string | List_nil | List_cons | Tuple
type constructor = { source : string; arity : int; family : string; output : constructor_output }
type term = Symbol of string | Number of string | Boolean of bool
          | App of term * term | Lambda of string * term
          | Binary of string * term * term | Unary of string * term
          | Conditional of term * term * term | Binding of string * term * term
          | Match of term * (string * string list * term) list

type token = { text : string; line : int; column : int }
type parser = { tokens : token array; mutable pos : int; constructors : constructor list }
exception Invalid of string
let invalid message = raise (Invalid message)
let keywords = ["and";"as";"assert";"begin";"class";"constraint";"do";"done";"downto";"else";"end";"exception";"external";"false";"for";"fun";"function";"functor";"if";"in";"include";"inherit";"initializer";"lazy";"let";"match";"method";"module";"mutable";"new";"nonrec";"object";"of";"open";"or";"private";"rec";"sig";"struct";"then";"to";"true";"try";"type";"val";"virtual";"when";"while";"with";"error"]
let is_letter c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'
let is_digit c = c >= '0' && c <= '9'
let is_ident_char c = is_letter c || is_digit c || c = '\''
let identifier s =
  if String.length s = 0 || not (s.[0] >= 'a' && s.[0] <= 'z' || s.[0] = '_')
     || not (String.for_all is_ident_char s) || List.mem s keywords
  then invalid ("invalid identifier: " ^ s);
  s
let constructor p name = match List.find_opt (fun c -> c.source = name) p.constructors with
  | Some c -> c | None -> invalid ("undeclared constructor: " ^ name)
let peek p = if p.pos < Array.length p.tokens then Some p.tokens.(p.pos) else None
let text p = match peek p with Some t -> t.text | None -> "<eof>"
let take p = match peek p with Some t -> p.pos <- p.pos + 1; t | None -> invalid "unexpected end of term"
let eat p expected = let got = take p in if got.text <> expected then invalid ("expected " ^ expected ^ ", got " ^ got.text)
let lex source =
  let n = String.length source in
  let rec scan i line column acc =
    if i = n then Array.of_list (List.rev acc) else
    match source.[i] with
    | ' ' | '\t' | '\r' -> scan (i+1) line (column+1) acc
    | '\n' -> scan (i+1) (line+1) 0 acc
    | c when is_letter c || is_digit c ->
        let j = ref (i+1) in
        while !j < n && (if is_digit c then is_digit source.[!j] else is_ident_char source.[!j]) do incr j done;
        let word = String.sub source i (!j-i) in
        scan !j line (column + !j-i) ({text=word;line;column}::acc)
    | _ ->
        let choices = ["<=>";"->";"<=";">=";"==";"!=";"&&";"||";"=>";"??"] in
        let found = List.find_opt (fun op -> i + String.length op <= n && String.sub source i (String.length op) = op) choices in
        let op = match found with Some s -> s | None ->
          if String.contains "()\\.+-*/!<>=|" source.[i] then String.make 1 source.[i]
          else invalid ("unsupported character at " ^ string_of_int line ^ ": " ^ String.make 1 source.[i]) in
        scan (i+String.length op) line (column+String.length op) ({text=op;line;column}::acc)
  in scan 0 1 0 []
let precedence = function
  | "<=>" -> 1 | "=>" -> 2 | "||" -> 3 | "&&" -> 4
  | "==" | "!=" | "<" | ">" | "<=" | ">=" -> 5
  | "+" | "-" -> 6 | "*" | "/" -> 7 | _ -> -1
let atom_start = function
  | "(" -> true
  | word when String.length word > 0 && (is_letter word.[0] || is_digit word.[0]) ->
      not (List.mem word ("error" :: keywords))
  | _ -> false
let is_case p =
  match peek p with
  | None -> false
  | Some first ->
      let start = if first.text = "|" then p.pos + 1 else p.pos in
      if start >= Array.length p.tokens then false else
      let head = p.tokens.(start) in
      if not (List.exists (fun c -> c.source = head.text) p.constructors) then false else
      let rec arrow i =
        i < Array.length p.tokens && p.tokens.(i).line = head.line &&
        (p.tokens.(i).text = "->" ||
         (String.length p.tokens.(i).text > 0 && is_letter p.tokens.(i).text.[0] && arrow (i+1)))
      in arrow (start+1)

let rec expression p boundary minimum =
  if boundary p then invalid "empty term at layout boundary";
  let left = primary p boundary in
  binary_tail p boundary minimum left
and binary_tail p boundary minimum left =
  let op = text p in
  let prec = precedence op in
  if not (boundary p) && prec >= minimum then (
    ignore (take p);
    let right = expression p boundary (prec+1) in
    binary_tail p boundary minimum (Binary(op,left,right)))
  else left
and primary p boundary =
  match text p with
  | "\\" ->
      eat p "\\";
      let name = identifier (take p).text in
      eat p ".";
      Lambda(name,expression p boundary 0)
  | "if" ->
      eat p "if";
      let cond = expression p boundary 0 in
      eat p "then";
      let yes = expression p boundary 0 in
      eat p "else";
      let no = expression p boundary 0 in
      Conditional(cond,yes,no)
  | "let" ->
      eat p "let";
      let name = identifier (take p).text in
      eat p "=";
      let value = expression p boundary 0 in
      eat p "in";
      Binding(name,value,expression p boundary 0)
  | "match" ->
      eat p "match";
      let subject = expression p boundary 0 in
      eat p "with";
      if not (is_case p) then invalid "match has no cases";
      let first = Option.get (peek p) in
      let case_column = first.column in
      let rec cases acc =
        match peek p with
        | Some t when not (boundary p) && t.column = case_column && is_case p ->
            if text p = "|" then ignore(take p);
            let name = (take p).text in
            let c = constructor p name in
            let rec names acc = if text p = "->" then List.rev acc
              else names (identifier (take p).text :: acc) in
            let binders = names [] in
            eat p "->";
            if List.length binders <> c.arity || List.length (List.sort_uniq compare binders) <> List.length binders
            then invalid "invalid pattern arity or repeated binders";
            let stop q = boundary q || (match peek q with
              | Some t -> t.column <= case_column && is_case q
              | None -> false) in
            let body = expression p stop 0 in
            cases ((name,binders,body)::acc)
        | _ -> List.rev acc
      in
      let branches = cases [] in
      let family = (constructor p (let n,_,_ = List.hd branches in n)).family in
      if not (List.for_all (fun (n,_,_) -> (constructor p n).family = family) branches) then invalid "mixed constructor families";
      let actual = List.map (fun (n,_,_) -> n) branches |> List.sort compare in
      let expected = List.filter (fun c -> c.family = family) p.constructors |> List.map (fun c -> c.source) |> List.sort compare in
      if actual <> expected then invalid "partial or duplicate match";
      Match(subject,branches)
  | "!" -> eat p "!"; Unary("not", primary p boundary)
  | "-" -> eat p "-"; Unary("-", primary p boundary)
  | "??" | "error" -> invalid "hole/error term is not a completed program"
  | _ -> applications p boundary (atom p)
and applications p boundary value =
  if not (boundary p) && atom_start (text p) then applications p boundary (App(value,atom p)) else value
and atom p =
  match text p with
  | "(" -> eat p "("; let result = expression p (fun _ -> false) 0 in eat p ")"; result
  | "True" -> ignore(take p); Boolean true
  | "False" -> ignore(take p); Boolean false
  | "??" | "error" -> invalid "incomplete/error atom"
  | word when String.length word > 0 && is_digit word.[0] -> ignore(take p); Number word
  | word when String.length word > 0 && is_letter word.[0] && not (List.mem word keywords) -> ignore(take p); Symbol word
  | word -> invalid ("unexpected atom: " ^ word)

let render_constructor c arguments =
  if List.length arguments <> c.arity then invalid ("partial/overapplied constructor: " ^ c.source);
  match c.output, arguments with
  | List_nil, [] -> "[]"
  | List_cons, [head;tail] -> head ^ " :: " ^ tail
  | Tuple, _ when List.length arguments >= 2 -> "(" ^ String.concat ", " arguments ^ ")"
  | Named name, [] -> name
  | Named name, _ -> name ^ " (" ^ String.concat ", " arguments ^ ")"
  | _ -> invalid "invalid constructor output mapping"
let rec render constructors scope term =
  let recurse = render constructors scope in
  match term with
  | Symbol name -> (match List.find_opt (fun c -> c.source = name) constructors with
      | Some c -> render_constructor c []
      | None -> if name = "_" || not (List.mem name scope) then invalid ("unbound symbol: " ^ name) else name)
  | Number n -> n
  | Boolean b -> string_of_bool b
  | Lambda (name,body) ->
      let rec collect names = function Lambda(n,b) -> collect (n::names) b | body -> (List.rev names,body) in
      let names,body = collect [name] body in
      if List.length (List.sort_uniq compare names) <> List.length names then invalid "duplicate lambda binders";
      "(fun " ^ String.concat " " names ^ " -> " ^ render constructors (names @ scope) body ^ ")"
  | App _ ->
      let rec flatten acc = function App(f,x) -> flatten (x::acc) f | head -> head,List.rev(List.rev acc) in
      let head,args = flatten [] term in
      let args = List.map recurse args in
      (match head with
       | Symbol name when List.exists (fun c -> c.source = name) constructors ->
           render_constructor (List.find(fun c -> c.source=name)constructors) args
       | _ -> "(" ^ recurse head ^ " " ^ String.concat " " (List.map(fun a->"("^a^")")args) ^ ")")
  | Binary(op,a,b) ->
      let op = match op with "==" -> "=" | "!=" -> "<>" | "<=>" -> "=" | s -> s in
      if op = "=>" then "((not (" ^ recurse a ^ ")) || (" ^ recurse b ^ "))"
      else "(" ^ recurse a ^ " " ^ op ^ " " ^ recurse b ^ ")"
  | Unary("-",Number n) -> "(-" ^ n ^ ")"
  | Unary(op,x) -> "(" ^ op ^ " (" ^ recurse x ^ "))"
  | Conditional(c,t,e) -> "(if " ^ recurse c ^ " then " ^ recurse t ^ " else " ^ recurse e ^ ")"
  | Binding(name,value,body) -> "(let " ^ name ^ " = " ^ recurse value ^ " in " ^ render constructors (name::scope) body ^ ")"
  | Match(subject,cases) ->
      "(match " ^ recurse subject ^ " with\n" ^ String.concat "\n" (List.map (fun (name,names,body) ->
        let c = List.find (fun c -> c.source = name) constructors in
        "| " ^ render_constructor c names ^ " -> " ^ render constructors (names@scope) body) cases) ^ ")"

let definitions source =
  let lines = String.split_on_char '\n' source in
  let start = Str.regexp "^\\([a-z_][A-Za-z0-9_']*\\)[ \t]*=[ \t]*" in
  let signature = Str.regexp "^[A-Za-z_][A-Za-z0-9_']*[ \t]*::" in
  let stats = Str.regexp "^(\\(Goals\\|Measures\\|Spec size\\|Solution size\\):" in
  let flush current acc = match current with None -> acc | Some(name,body) -> (name,String.concat "\n" (List.rev body))::acc in
  let rec loop current acc = function
    | [] -> List.rev(flush current acc)
    | line::rest when Str.string_match start line 0 ->
        let name = identifier (Str.matched_group 1 line) in
        let offset = Str.match_end () in
        loop (Some(name,[String.sub line offset (String.length line-offset)])) (flush current acc) rest
    | line::rest when Str.string_match signature line 0 || Str.string_match stats line 0 -> loop current acc rest
    | line::rest -> (match current with
        | None -> if String.trim line = "" then loop current acc rest else invalid "unexpected preamble (not successful synthesis output)"
        | Some(name,body) -> loop (Some(name,line::body)) acc rest)
  in loop None [] lines

let translate ~constructors ~primitives source =
  try
    let constructor_name name =
      String.length name > 0 && name.[0] >= 'A' && name.[0] <= 'Z'
      && String.for_all is_ident_char name
    in
    let labels = List.map (fun c -> c.source) constructors in
    if List.length (List.sort_uniq compare labels) <> List.length labels then invalid "duplicate constructor manifest";
    List.iter (fun c ->
      if not (constructor_name c.source) || c.arity < 0 || c.family = "" then invalid "invalid constructor manifest";
      match c.output with
      | Named name -> if not (constructor_name name) then invalid "invalid emitted constructor name"
      | List_nil -> if c.arity <> 0 then invalid "nil arity must be zero"
      | List_cons -> if c.arity <> 2 then invalid "cons arity must be two"
      | Tuple -> if c.arity < 2 then invalid "tuple arity must be at least two") constructors;
    let defs = definitions source in
    if defs = [] then invalid "no completed definitions";
    let names = List.map fst defs in
    if List.length (List.sort_uniq compare names) <> List.length names then invalid "duplicate goal definitions";
    List.iter (fun s -> ignore(identifier s)) primitives;
    let emitted = List.mapi(fun i (name,body) ->
      let p = {tokens=lex body;pos=0;constructors} in
      let tree = expression p (fun _->false) 0 in
      if p.pos <> Array.length p.tokens then invalid ("unconsumed term in " ^ name ^ ": " ^ text p);
      (if i=0 then "let rec " else "and ") ^ name ^ " = " ^ render constructors (names@primitives) tree) defs in
    Ok ("(* Mechanically generated; no exercise-specific algorithm substitution. *)\n" ^ String.concat "\n" emitted ^ "\n")
  with Invalid message -> Error message
