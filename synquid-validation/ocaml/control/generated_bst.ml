(* Negative control only. This is NOT Synquid output or a product implementation. *)
type 'a bst = Empty | Node of 'a * 'a bst * 'a bst
let insert _x tree = tree
