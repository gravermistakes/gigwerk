(* What a part asks for, as the writer reads it: for each value the interface
 * names, its type and the examples it must satisfy. Examples come from the
 * part's own tests or statement, never from a reference solution. *)

type example = { args : Value.t list; out : Value.t }

type target = {
  name : string;
  ty : Types.ty;
  examples : example list;
}

type t = {
  part : string;
  iface : Iface.t;
  targets : target list;
  notes : string list;          (* what was read and what was not, and why *)
}

let example_to_string name ex =
  Printf.sprintf "%s %s = %s" name
    (String.concat " " (List.map Value.to_ocaml ex.args)) (Value.to_ocaml ex.out)
