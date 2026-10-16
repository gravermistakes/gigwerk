open Generated_bst

module IntSet = Set.Make (Int)

let checks = ref 0
let require message condition =
  incr checks;
  if not condition then failwith message

let rec contents = function
  | Empty -> []
  | Node (x, left, right) -> contents left @ (x :: contents right)

let rec valid_between lower upper = function
  | Empty -> true
  | Node (x, left, right) ->
      (match lower with None -> true | Some lo -> lo < x)
      && (match upper with None -> true | Some hi -> x < hi)
      && valid_between lower (Some x) left
      && valid_between (Some x) upper right

let valid tree = valid_between None None tree

let rec subsets = function
  | [] -> [[]]
  | x :: xs ->
      let rest = subsets xs in
      rest @ List.map (fun tail -> x :: tail) rest

(* Generate every BST shape from sorted distinct keys, independently of insert. *)
let rec shapes = function
  | [] -> [Empty]
  | keys ->
      let rec choose left_prefix = function
        | [] -> []
        | root :: right_keys ->
            let left_keys = List.rev left_prefix in
            let current =
              List.concat_map
                (fun left -> List.map (fun right -> Node (root, left, right))
                   (shapes right_keys))
                (shapes left_keys)
            in
            current @ choose (root :: left_prefix) right_keys
      in
      choose [] keys

let check_insert tree x =
  let before = contents tree in
  let expected = IntSet.elements (IntSet.add x (IntSet.of_list before)) in
  let result = insert x tree in
  require "strict BST invariant" (valid result);
  require "exact set union; no lost or invented keys" (contents result = expected);
  require "input remains unchanged" (contents tree = before);
  require "exact size delta" (List.length (contents result) = List.length expected);
  let repeated = insert x result in
  require "duplicate insertion preserves keys" (contents repeated = expected);
  require "duplicate insertion preserves ordering" (valid repeated)

let () =
  let domain = [-3; -2; -1; 0; 1; 2; 3] in
  let trees = List.concat_map shapes (subsets domain) in
  let exhaustive_cases = ref 0 in
  List.iter
    (fun tree ->
      require "independent generator produces a valid BST" (valid tree);
      List.iter (fun x -> incr exhaustive_cases; check_insert tree x)
        (-4 :: domain @ [4]))
    trees;
  let random = Random.State.make [|2026; 1014; 0|] in
  let random_steps = ref 0 in
  for _run = 1 to 200 do
    let tree = ref Empty in
    let expected = ref IntSet.empty in
    for _step = 1 to 100 do
      let x = Random.State.int random 201 - 100 in
      check_insert !tree x;
      tree := insert x !tree;
      expected := IntSet.add x !expected;
      require "sequence agrees with independent Set oracle"
        (contents !tree = IntSet.elements !expected);
      incr random_steps
    done
  done;
  let extreme_tree = Node (0, Node (min_int, Empty, Empty), Node (max_int, Empty, Empty)) in
  List.iter (check_insert extreme_tree) [min_int; max_int; -1; 0; 1];
  List.iter
    (fun keys ->
      let tree = ref Empty in
      List.iter (fun x -> check_insert !tree x; tree := insert x !tree) keys)
    [List.init 500 Fun.id; List.init 500 (fun i -> 499 - i)];
  Printf.printf
    "PASS: %d independently generated BSTs; %d exhaustive insertion cases; %d random sequence steps; %d assertions\n"
    (List.length trees) !exhaustive_cases !random_steps !checks
