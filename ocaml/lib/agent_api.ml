type request = {
  instruction : string;
  context : string list;
}

type response = {
  specification : string;
  context : string list;
}

type error =
  | Transport of string
  | Invalid_response of string

module type S = sig
  val infer : request -> (response, error) result
end
