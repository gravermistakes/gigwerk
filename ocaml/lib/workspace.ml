type error =
  | Invalid_root of string
  | Invalid_path of string
  | Io_error of string

type t = { root : string }

let canonical path =
  try Ok (Unix.realpath path) with Unix.Unix_error (e, _, _) -> Error (Unix.error_message e)

let create root =
  try
    if not (Sys.file_exists root) then Unix.mkdir root 0o755;
    match canonical root with
    | Ok root -> Ok { root }
    | Error e -> Error (Invalid_root e)
  with Sys_error e -> Error (Invalid_root e)

let components path = String.split_on_char '/' path

let valid_relative path =
  path <> ""
  && path.[0] <> '/'
  && not (List.exists (fun x -> x = "..") (components path))

let resolve t path =
  if not (valid_relative path) then Error (Invalid_path path)
  else
    let candidate = Filename.concat t.root path in
    try
      let parent = Filename.dirname candidate in
      let parent_real = Unix.realpath parent in
      let prefix = t.root ^ "/" in
      if parent_real <> t.root && not (String.length parent_real > String.length prefix && String.sub parent_real 0 (String.length prefix) = prefix) then
        Error (Invalid_path path)
      else Ok candidate
    with Unix.Unix_error (e, _, _) -> Error (Io_error (Unix.error_message e))

let write t ~path ~contents =
  match resolve t path with
  | Error e -> Error e
  | Ok filename ->
      try
        let parent = Filename.dirname filename in
        let rec mkdir_p dir =
          if dir = t.root || Sys.file_exists dir then ()
          else (mkdir_p (Filename.dirname dir); Unix.mkdir dir 0o755)
        in
        mkdir_p parent;
        let oc = open_out_bin filename in
        output_string oc contents;
        close_out oc;
        Ok ()
      with Sys_error e -> Error (Io_error e)

let read t ~path =
  match resolve t path with
  | Error e -> Error e
  | Ok filename ->
      try
        let ic = open_in_bin filename in
        let len = in_channel_length ic in
        let s = really_input_string ic len in
        close_in ic;
        Ok s
      with Sys_error e -> Error (Io_error e)
