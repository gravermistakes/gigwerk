open Gigwerk
let pairs_unrelated = [
  "the gate refused a widened envelope", "quarterly revenue in the northeast region";
  "a critic checked the artifact and passed", "migrating beelines to opentelemetry";
  "the smell of hot dust off a server rack", "scope narrowing against a directory handle";
  "budget exhausted after twenty actions", "a song playing in another room";
  "openat2 resolve beneath refused the traversal", "brand voice guidelines for cold email";
]
let pairs_related = [
  "the gate refused a widened envelope", "a composition widened its scope and was refused";
  "a critic checked the artifact and passed", "the critic emitted a passing verdict on the file";
  "budget exhausted after twenty actions", "terms ran out of budget partway through the gig";
  "openat2 resolve beneath refused the traversal", "the kernel refused a dotdot escape from the root";
  "prediction error is the surprise signal", "surprise comes from the gap between predicted and observed";
]
let pairs_paraphrase = [
  "the gate refused a widened envelope", "the gate rejected a widened envelope";
  "a critic checked the artifact", "a critic inspected the artifact";
  "budget exhausted after twenty actions", "budget exhausted after 20 actions";
]
let stats name ps =
  let xs = List.map (fun (a,b) -> Embed.cosine (Embed.of_text a) (Embed.of_text b)) ps in
  let n = float_of_int (List.length xs) in
  let mean = List.fold_left (+.) 0.0 xs /. n in
  let sd = sqrt (List.fold_left (fun acc x -> acc +. ((x -. mean) ** 2.)) 0.0 xs /. n) in
  let lo = List.fold_left min 1.0 xs and hi = List.fold_left max (-1.0) xs in
  Printf.printf "  %-14s n=%d  mean=%.3f  sd=%.3f  range=[%.3f, %.3f]\n"
    name (List.length xs) mean sd lo hi
let () =
  print_string "semantic cosine, feature-hashed 256d\n";
  stats "unrelated" pairs_unrelated;
  stats "related" pairs_related;
  stats "paraphrase" pairs_paraphrase;
  print_string "\naffect resonance, 6-tone vector\n";
  let dread   = { Affect.zero with Affect.hazard=0.9; surprise=0.9; dissonance=0.5; valence=(-0.9) } in
  let dread2  = { Affect.zero with Affect.hazard=0.88; surprise=0.92; dissonance=0.48; valence=(-0.85) } in
  let elation = { Affect.zero with Affect.hazard=0.9; surprise=0.9; dissonance=0.5; valence=0.9 } in
  let routine = { Affect.zero with Affect.novelty=0.1; cost=0.2 } in
  let novel   = { Affect.zero with Affect.novelty=1.0; surprise=0.3 } in
  Printf.printf "  dread vs near-dread     %.3f\n" (Affect.resonance dread dread2);
  Printf.printf "  dread vs elation        %.3f   (same magnitudes, opposite sign)\n" (Affect.resonance dread elation);
  Printf.printf "  dread vs routine        %.3f\n" (Affect.resonance dread routine);
  Printf.printf "  routine vs novel        %.3f\n" (Affect.resonance routine novel);
  Printf.printf "  is_flat routine?        %b   norm=%.3f\n"
    (Affect.is_flat routine) (Affect.norm (Affect.to_vector routine));
  Printf.printf "  is_flat dread?          %b   norm=%.3f\n"
    (Affect.is_flat dread) (Affect.norm (Affect.to_vector dread));
  print_string "\nnovelty curve 1/sqrt(n+1)\n";
  List.iter (fun n -> Printf.printf "  prior_runs=%-4d %.3f\n" n (Affect.novelty_of ~prior_runs:n))
    [0;1;3;8;15;35;99]
