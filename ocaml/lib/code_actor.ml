type error =
  | Workspace_error of string
  | Actor_error of string

type context = string list

module type S = sig
  type context = string list
  val produce : context -> Production.requirement -> Workspace.t ->
    (Production.artifact, error) result
end
