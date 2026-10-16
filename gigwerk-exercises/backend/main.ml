open Synquid_backend

let read path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in channel)
    (fun () -> really_input_string channel (in_channel_length channel))
let lines path = read path |> String.split_on_char '\n' |> List.filter (fun s -> String.trim s <> "")
let constructor_line line = match String.split_on_char '\t' line with
  | [source;arity;family;representation] ->
      let output = match representation with
        | "list_nil" -> List_nil | "list_cons" -> List_cons | "tuple" -> Tuple
        | s when String.starts_with ~prefix:"named:" s -> Named(String.sub s 6 (String.length s-6))
        | _ -> failwith ("unknown constructor representation: " ^ representation)
      in {source;arity=int_of_string arity;family;output}
  | _ -> failwith "constructor manifest needs source, arity, family, representation"
let () =
  try
    if Array.length Sys.argv <> 4 then failwith "usage: synquid-ocaml OUTPUT CONSTRUCTORS.tsv PRIMITIVES.txt";
    let constructors = List.map constructor_line (lines Sys.argv.(2)) in
    let primitives = List.map String.trim (lines Sys.argv.(3)) in
    match translate ~constructors ~primitives (read Sys.argv.(1)) with
    | Ok code -> print_string code
    | Error message -> prerr_endline ("lowering refused: " ^ message); exit 1
  with Failure message | Sys_error message -> prerr_endline message; exit 1
