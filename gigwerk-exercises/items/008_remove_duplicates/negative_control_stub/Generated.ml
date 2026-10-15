(* TEST NEGATIVE-CONTROL STUB ONLY.
   Deliberately wrong non-answer: every input maps to the empty list.  It is
   not synthesized, not a candidate, and not an implementation of benchmark
   008.  Its sole purpose is to make test_generated.ml fail an actual semantic
   assertion before any mechanically lowered candidate exists. *)
let compress _ = []
