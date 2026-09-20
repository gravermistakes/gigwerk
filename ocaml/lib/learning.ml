type requirement_outcome = {
  id : string;
  status : string;
}

type artifact_digest = {
  requirement_id : string;
  path : string;
  digest : string;
}

type verification_outcome = {
  command : string;
  exit_status : int option;
  passed : bool;
}

type trace = {
  specification_digest : string;
  requirements : requirement_outcome list;
  artifacts : artifact_digest list;
  verification : verification_outcome list;
  terminal_status : string;
}

let digest_string s = Digest.to_hex (Digest.string s)

let escape s =
  let b = Buffer.create (String.length s + 8) in
  String.iter (function
    | '"' -> Buffer.add_string b "\\\""
    | '\\' -> Buffer.add_string b "\\\\"
    | '\n' -> Buffer.add_string b "\\n"
    | '\r' -> Buffer.add_string b "\\r"
    | '\t' -> Buffer.add_string b "\\t"
    | c -> Buffer.add_char b c) s;
  Buffer.contents b

let json_string s = "\"" ^ escape s ^ "\""
let json_bool b = if b then "true" else "false"
let json_opt_int = function None -> "null" | Some n -> string_of_int n

let join_json f xs = String.concat "," (List.map f xs)

let to_json t =
  let requirements = join_json (fun r ->
    "{\"id\":" ^ json_string r.id ^ ",\"status\":" ^ json_string r.status ^ "}") t.requirements in
  let artifacts = join_json (fun a ->
    "{\"requirement_id\":" ^ json_string a.requirement_id ^
    ",\"path\":" ^ json_string a.path ^ ",\"digest\":" ^ json_string a.digest ^ "}") t.artifacts in
  let verification = join_json (fun v ->
    "{\"command\":" ^ json_string v.command ^
    ",\"exit_status\":" ^ json_opt_int v.exit_status ^
    ",\"passed\":" ^ json_bool v.passed ^ "}") t.verification in
  "{\"specification_digest\":" ^ json_string t.specification_digest ^
  ",\"requirements\":[" ^ requirements ^ "]" ^
  ",\"artifacts\":[" ^ artifacts ^ "]" ^
  ",\"verification\":[" ^ verification ^ "]" ^
  ",\"terminal_status\":" ^ json_string t.terminal_status ^ "}"

let record trace =
  ignore trace
