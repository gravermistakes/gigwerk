(* Mechanically lowered Synquid output; no algorithm substitution. *)
type 'a bst = Empty | Node of 'a * 'a bst * 'a bst

let rec insert (x : int) (t : int bst) : int bst =
  match t with
  | Empty ->
    Node (x, Empty, Empty)
  | Node (x7, x8, x9) ->
    if ((x <= x7) && (x7 <= x)) then
      t
    else
      if (x7 <= x) then
        Node (x7, x8, (insert (x) (x9)))
      else
        Node (x7, (insert (x) (x8)), x9)
