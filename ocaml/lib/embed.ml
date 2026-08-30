(* Feature-hashed embeddings. Zero dependencies, deterministic, no training run
 * between you and turn one.
 *
 * Not good embeddings. Good enough that retrieval is better than recency, and
 * the interface does not change when you swap in a real encoder -- which is
 * the only property that matters at this stage. *)

let dim = 256

type vec = float array

let tokens text =
  let out = ref [] and buf = Buffer.create 16 in
  let flush () =
    if Buffer.length buf > 0 then (out := Buffer.contents buf :: !out; Buffer.clear buf) in
  String.iter (fun c ->
      if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
         || (c >= '0' && c <= '9') || c = '_'
      then Buffer.add_char buf (Char.lowercase_ascii c)
      else flush ()) text;
  flush ();
  (* character trigrams catch near-misses whole words miss *)
  let n = String.length text in
  let tri = ref [] in
  for i = 0 to min (n - 3) 400 do
    tri := String.lowercase_ascii (String.sub text i 3) :: !tri
  done;
  !out @ !tri

let of_text text : vec =
  let v = Array.make dim 0.0 in
  List.iter (fun t ->
      let h = Hashtbl.hash t land 0xffffff in
      let i = h mod dim in
      let s = if (h lsr 12) land 1 = 1 then 1.0 else -1.0 in
      v.(i) <- v.(i) +. s)
    (tokens text);
  let n = sqrt (Array.fold_left (fun a x -> a +. (x *. x)) 0.0 v) in
  if n > 0.0 then Array.map (fun x -> x /. n) v else v

let cosine (a : vec) (b : vec) =
  let s = ref 0.0 in
  Array.iteri (fun i x -> s := !s +. (x *. b.(i))) a;
  !s

(* Blob round-trip, so a vector can live in a column instead of a sidecar file
   that drifts out of sync with the row it describes. *)
let to_string (v : vec) =
  String.concat "," (Array.to_list (Array.map (fun x -> Printf.sprintf "%.6f" x) v))

let of_string s : vec =
  let parts = String.split_on_char ',' s in
  let a = Array.make dim 0.0 in
  List.iteri (fun i p -> if i < dim then a.(i) <- float_of_string p) parts;
  a
