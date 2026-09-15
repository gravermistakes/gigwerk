module type S = sig
  type context
  val produce : context -> Production.requirement -> Workspace.t -> (Production.artifact, error) result
end
and error =
  | Workspace_error of string
  | Actor_error of string

module type PRODUCER = sig
  type context
  val produce : context -> Production.requirement -> Workspace.t -> (Production.artifact, error) result
end

module type S = PRODUCER
