(* Examples from an Exercism part's own test file, computed by the compiler.
 *
 * The test file is a program: it defines helpers, calls Base, builds values in
 * local bindings. Reading its assertions as text would miss most of that, so
 * instead it is RUN, against a probe in place of the part:
 *
 *   - the probe implements the part's interface, and each function records
 *     the arguments it was called with (printed as OCaml literals through
 *     printers derived from the interface types) and then raises;
 *   - each assertion site `ae EXPECTED GOT` in the test is rewritten to run
 *     GOT under a handler and print EXPECTED with the printer for the called
 *     function's result type.
 *
 * Each site then yields one example: the arguments the probe saw and the value
 * the test expected back. A site is used only when GOT is a direct call (of
 * the part's function, or of a helper whose body is one), and only when that
 * run made exactly one call: anything else might relate EXPECTED to a
 * transformed result, and an example that misstates the part is worse than
 * none. The reference solution is never read. *)

open Parsetree
open Types

type site = { id : int; target : string; constant : bool; exp : expression; got : expression }

let read = Iface.read_file

let write path contents =
  let oc = open_out_bin path in output_string oc contents; close_out oc

(* `Leap.leap_year` and `leap_year` both name the part's function. *)
let ident_name (e : expression) =
  match e.pexp_desc with
  | Pexp_ident { txt; _ } -> Some (Longident.last txt)
  | _ -> None

let mentions names (e : expression) =
  let found = ref false in
  let it = { Ast_iterator.default_iterator with
             expr = (fun self e ->
                 (match ident_name e with
                  | Some n when List.mem n names -> found := true | _ -> ());
                 Ast_iterator.default_iterator.expr self e) } in
  it.expr it e; !found

let rec strip_funs (e : expression) =
  match e.pexp_desc with
  | Pexp_fun (_, _, _, body) -> strip_funs body
  | Pexp_constraint (e, _) -> strip_funs e
  | _ -> e

(* The function a direct call calls, if GOT is one. *)
let called ~callable (e : expression) =
  match e.pexp_desc with
  | Pexp_apply (f, _) ->
      (match ident_name f with
       | Some "|>" ->
           (match e.pexp_desc with
            | Pexp_apply (_, [ _; (_, g) ]) ->
                (match g.pexp_desc with
                 | Pexp_ident _ -> Option.bind (ident_name g) (fun n ->
                     if List.mem n callable then Some n else None)
                 | Pexp_apply (h, _) -> Option.bind (ident_name h) (fun n ->
                     if List.mem n callable then Some n else None)
                 | _ -> None)
            | _ -> None)
       | Some n when List.mem n callable -> Some n
       | _ -> None)
  | _ -> None

(* Test-local helpers whose body is a direct call of one of the part's
   functions: `let hamdist a b = hamming_distance (dna a) (dna b)`. *)
let helpers ~targets (str : structure) =
  List.concat_map (fun item ->
      match item.pstr_desc with
      | Pstr_value (_, vbs) ->
          List.filter_map (fun vb ->
              match vb.pvb_pat.ppat_desc, vb.pvb_expr.pexp_desc with
              | Ppat_var { txt = h; _ }, Pexp_fun _ ->
                  Option.map (fun t -> (h, t)) (called ~callable:targets (strip_funs vb.pvb_expr))
              | _ -> None) vbs
      | _ -> []) str

let unlabeled args = List.filter_map (fun (l, a) -> if l = Asttypes.Nolabel then Some a else None) args

let find_sites ~targets ~constants ~helpers (str : structure) =
  let names = targets @ List.map fst helpers in
  let sites = ref [] and n = ref 0 in
  let resolve name = match List.assoc_opt name helpers with Some t -> t | None -> name in
  let site_of (e : expression) =
    match e.pexp_desc with
    | Pexp_apply (_, args) ->
        let rec pairs = function
          | exp :: got :: rest ->
              if mentions names exp then pairs (got :: rest)
              else (match ident_name got with
                  | Some c when List.mem c constants -> Some (exp, got, c, true)
                  | _ ->
                      match called ~callable:names got with
                      | Some f -> Some (exp, got, resolve f, false)
                      | None -> pairs (got :: rest))
          | _ -> None
        in
        pairs (unlabeled args)
    | _ -> None
  in
  let mapper = { Ast_mapper.default_mapper with
                 expr = (fun self e ->
                     match site_of e with
                     | Some (exp, got, target, constant) ->
                         incr n;
                         let s = { id = !n; target; constant; exp; got } in
                         sites := s :: !sites;
                         let call = Printf.sprintf "(Gw_probe.site %d %S %b (fun () -> ignore (%s)) (fun () -> __gw_print_%s (%s)); Stdlib.Obj.magic (fun _ -> ()))"
                             s.id target constant
                             (if constant then "()" else Format.asprintf "%a" Pprintast.expression got)
                             target (Format.asprintf "%a" Pprintast.expression exp) in
                         Parse.expression (Lexing.from_string call)
                     | None -> Ast_mapper.default_mapper.expr self e) } in
  let str' = mapper.structure mapper str in
  (List.rev !sites, str')

let is_function t = match repr t with TArrow _ -> true | _ -> false

(* The probe module: the part's declarations, printers for them, and each
   value of the interface as a recorder. *)
let probe_module (iface : Iface.t) (mli_src : string) =
  let sg = Parse.interface (Lexing.from_string mli_src) in
  let decl_items = List.filter_map (fun item ->
      match item.psig_desc with
      | Psig_type (rf, tds) ->
          let tds = List.map (fun td ->
              if td.ptype_kind = Ptype_abstract && td.ptype_manifest = None then
                { td with ptype_manifest = Some (Ast_helper.Typ.constr
                                                   { txt = Longident.Lident "int"; loc = td.ptype_loc } []) }
              else td) tds in
          Some (Format.asprintf "%a" Pprintast.structure
                  [ Ast_helper.Str.type_ rf tds ])
      | Psig_open od ->
          Some ("open " ^ String.concat "." (Longident.flatten od.popen_expr.txt))
      | _ -> None) sg in
  let decls = iface.Iface.decls in
  let values = List.map (fun v ->
      let args, _ = unarrow v.Iface.vty in
      if args = [] then Printf.sprintf "let %s = Stdlib.Obj.magic 0" v.Iface.vname
      else
        let params = List.mapi (fun i (l, t) ->
            let x = "a" ^ string_of_int i in
            let binder = match l with
              | Nolabel -> x | Labelled s -> "~" ^ s ^ ":" ^ x | Optional s -> "?" ^ s ^ ":" ^ x in
            let t = match l with Optional _ -> t_option t | _ -> t in
            (binder, x, t)) args in
        let printed = List.map (fun (_, x, t) ->
            try Printers.printer decls t ^ " " ^ x
            with Printers.Unprintable _ -> "\"<unprintable>\"") params in
        Printf.sprintf "let %s %s = Gw_probe.record %S [%s]; Stdlib.raise Gw_probe.Probe"
          v.Iface.vname (String.concat " " (List.map (fun (b, _, _) -> b) params))
          v.Iface.vname (String.concat "; " printed)) iface.Iface.values in
  String.concat "\n" decl_items ^ "\n" ^ Printers.generic ^ Printers.decl_printers decls ^ "\n"
  ^ String.concat "\n" values ^ "\n"

let probe_support =
  {|exception Probe
let calls : (string * string list) list ref = ref []
let record name args = calls := (name, args) :: !calls
let out = Stdlib.open_out_bin "gw_probe.out"
let site id target constant got exp =
  calls := [];
  let ok = (try got (); true with Probe -> true | _ -> false) in
  let recorded = Stdlib.List.rev !calls in
  match (try Some (exp ()) with _ -> None) with
  | None -> ()
  | Some e ->
      if constant then Stdlib.Printf.fprintf out "%d\t%s\t\t%S\n%!" id target e
      else (match recorded with
          | [ (name, args) ] when ok && name = target ->
              Stdlib.Printf.fprintf out "%d\t%s\t%S\t%S\n%!" id target
                (Stdlib.String.concat "\031" args) e
          | _ -> ())
|}

(* Printers for each function's result type, placed in the test file after its
   opens so the part's constructors are in scope. *)
let result_printers (iface : Iface.t) =
  let decls = iface.Iface.decls in
  Printers.generic ^ Printers.decl_printers decls
  ^ String.concat "\n" (List.map (fun v ->
      let _, r = unarrow v.Iface.vty in
      let p = try Printers.printer decls r with Printers.Unprintable _ -> "(fun _ -> \"<unprintable>\")" in
      Printf.sprintf "let __gw_print_%s = %s" v.Iface.vname p) iface.Iface.values) ^ "\n"

(* Insert generated code after the test file's last leading `open`. *)
let instrument_test (iface : Iface.t) (str : structure) =
  let rec split acc = function
    | ({ pstr_desc = Pstr_open _; _ } as i) :: rest -> split (i :: acc) rest
    | rest -> (List.rev acc, rest)
  in
  let opens, rest = split [] str in
  Format.asprintf "%a" Pprintast.structure opens ^ "\n" ^ result_printers iface
  ^ Format.asprintf "%a" Pprintast.structure rest ^ "\n"

type outcome = {
  examples : (string * Spec.example) list;     (* target, example *)
  sites : int;
  log : string;
}

let module_name slug = String.map (fun c -> if c = '-' then '_' else c) slug

let run_cmd ~cwd argv =
  let o = Gigwerk.Proc.run ~root:cwd ~timeout_s:300. argv in
  (o.Gigwerk.Proc.exit_status, o.Gigwerk.Proc.stdout ^ o.Gigwerk.Proc.stderr)

let parse_args s =
  if s = "" then Some []
  else
    let parts = String.split_on_char '\031' s in
    let vs = List.map Literal.of_string_opt parts in
    if List.for_all Option.is_some vs then Some (List.map Option.get vs) else None

(* Run the probe for one exercise directory, in a scratch copy. *)
let run ~env ~scratch ~exercise_dir ~slug =
  let m = module_name slug in
  let mli_path = Filename.concat exercise_dir (m ^ ".mli") in
  let mli_src = read mli_path in
  let iface = Iface.parse_string mli_src in
  let targets = List.map (fun v -> v.Iface.vname) iface.Iface.values in
  let constants = List.filter_map (fun v ->
      if is_function v.Iface.vty then None else Some v.Iface.vname) iface.Iface.values in
  let test_src = read (Filename.concat exercise_dir "test.ml") in
  let str = Parse.implementation (Lexing.from_string test_src) in
  let helpers = helpers ~targets str in
  let sites, str' = find_sites ~targets ~constants ~helpers str in
  let dir = Filename.concat scratch slug in
  ignore (run_cmd ~cwd:"/" [| "rm"; "-rf"; dir |]);
  ignore (run_cmd ~cwd:"/" [| "cp"; "-r"; exercise_dir; dir |]);
  ignore (run_cmd ~cwd:dir [| "rm"; "-rf"; ".meta"; "_build" |]);
  write (Filename.concat dir "gw_probe.ml") probe_support;
  write (Filename.concat dir (m ^ ".ml")) (probe_module iface mli_src);
  write (Filename.concat dir "test.ml") (instrument_test iface str');
  let status, log = run_cmd ~cwd:dir (Array.append env [| "dune"; "build"; "./test.exe" |]) in
  if status <> Some 0 then { examples = []; sites = List.length sites; log = "build failed:\n" ^ log }
  else begin
    let _, runlog = run_cmd ~cwd:(Filename.concat dir "_build/default")
        [| "./test.exe" |] in
    let out = try read (Filename.concat dir "_build/default/gw_probe.out") with _ -> "" in
    let examples = List.filter_map (fun line ->
        match String.split_on_char '\t' line with
        | [ _id; target; args; exp ] ->
            let unq s = try Scanf.sscanf s "%S" (fun x -> x) with _ -> s in
            let args = if args = "" then Some [] else parse_args (unq args) in
            (match args, Literal.of_string_opt (unq exp) with
             | Some args, Some out -> Some (target, { Spec.args; out })
             | _ -> None)
        | _ -> None) (String.split_on_char '\n' out) in
    { examples; sites = List.length sites; log = runlog }
  end
