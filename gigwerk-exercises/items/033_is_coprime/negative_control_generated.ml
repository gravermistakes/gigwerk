(* TEST NEGATIVE CONTROL ONLY — deliberately incorrect; never a candidate.
   When compiled as generated.ml, this defines module Generated solely to prove
   that test_generated.ml rejects a plausible but semantically wrong function. *)

let coprime (_ : int) (_ : int) : bool = true
