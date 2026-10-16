(* The interface an Actor implements to produce an artifact.
 *
 * It receives the part (the requirement) and the stage (the workspace), and
 * nothing else. There used to be a third argument, `context : string list`,
 * passed in by whoever called produce. Producer always passed [], but the slot
 * existed, and a slot for the caller to hand the performer notes is a slot for
 * line readings. The Agent casts; it does not direct.
 *
 * So the Actor declares its own machine and its own policy over it, and the
 * Agency only walks it (Actor.run_machine): the actor picks each input, the
 * machine says whether that input exists, Obligations says whether it is
 * affordable. `deliver` is read only at a terminal phase.
 *
 * Refused is the actor declining the part. It is range, not failure, and it is
 * recorded as its own outcome. The words are optional: an actor that declines
 * without saying why has still declined, and an absent reason is stored as
 * absent rather than filled in by whoever reads the refusal. *)
type error =
  | Workspace_error of string
  | Refused of string option

module type S = sig
  (* Whose work this is. Stamped on every artifact the actor produces, so the
     record credits the talent rather than whoever booked it. *)
  val name : string
  val machine : Phases.machine
  (* What each input spends. Declared by the actor, charged by the Agency. *)
  val cost : string -> Grants.action list
  type state
  (* Read the part. Refused here is the actor declining before it starts. *)
  val prepare : Production.requirement -> Workspace.t -> (state, error) result
  val choose : state -> string -> string option
  val perform : state -> string -> (state, string) result
  val deliver : state -> Production.artifact
end
