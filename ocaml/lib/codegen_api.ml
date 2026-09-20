type request = {
  requirement : Production.requirement;
  context : string list;
  workspace : Workspace.t;
}

type response = {
  artifact : Production.artifact;
  note : string;
}

type error =
  | Transport of string
  | Rejected of string
  | Invalid_response of string

module type S = sig
  val generate : request -> (response, error) result
end
