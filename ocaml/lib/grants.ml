(* Grants — what an actor is permitted to do.
 *
 * A closed variant, not a string. An action nobody defined is not "unknown",
 * it is unrepresentable, so a typo in a composition fails to parse rather than
 * silently granting nothing.
 *
 * Grants answer WHAT. Terms answer HOW MANY and UNTIL WHEN. Caps answer WHERE.
 * Three different questions; keeping them separate is why none of them has to
 * be a string match. *)

type action =
  | Read      (* read a file beneath the capability root *)
  | Write     (* write a file beneath the capability root *)
  | Spawn     (* start a subprocess *)
  | Query     (* EXACT lookup against the fact store *)
  | Retrieve  (* RANKED retrieval -- RAG. composer only. see below. *)
  | Emit      (* send a message to another entity's inbox *)

(* Query and Retrieve are not two flavours of reading. They differ in
 * determinism, and that difference decides who may hold them.
 *
 *   Query     exact. same facts in, same answer out. an actor can hold this
 *             and stay deterministic.
 *   Retrieve  ranked. the answer depends on what else is in the corpus, on
 *             embedding drift, on a threshold. an actor holding this is no
 *             longer deterministic code, and every claim made about actors
 *             here -- that a failing critic means something is actually wrong,
 *             that the same input gives the same verdict -- stops being true.
 *
 * So the AI retrieves in order to decide how to assemble an actor and what it
 * should do. The actor it assembles references facts. Actors do not RAG.
 * That is not a convention: `composer_only` makes the gate refuse it. *)

let composer_only = function
  | Retrieve -> true
  | Read | Write | Spawn | Query | Emit -> false

let action_to_string = function
  | Read -> "read" | Write -> "write" | Spawn -> "spawn"
  | Query -> "query" | Retrieve -> "retrieve" | Emit -> "emit"

let action_of_string = function
  | "read" -> Some Read | "write" -> Some Write | "spawn" -> Some Spawn
  | "query" -> Some Query | "retrieve" -> Some Retrieve
  | "emit" -> Some Emit | _ -> None

type t = {
  entity   : string;
  snapshot : string;   (* which composition revision these grants belong to *)
  actions  : action list;
}

let make ~entity ~snapshot ~actions = { entity; snapshot; actions }
let allows g action = List.mem action g.actions
let snapshot g = g.snapshot
let entity g = g.entity
let actions g = g.actions

let to_string g =
  Printf.sprintf "%s@%s[%s]" g.entity g.snapshot
    (String.concat "," (List.map action_to_string g.actions))
