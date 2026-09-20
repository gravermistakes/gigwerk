open Gigwerk

module Main_fail = struct
  let generate _ = Error (Codegen_api.Transport "main unavailable")
end

module Backup_ok = struct
  let generate _ =
    Ok Codegen_api.{
      artifact = Production.{ requirement_id = "r"; paths = ["r.ml"] };
      note = "backup";
    }
end

module Both_fail = struct
  let generate _ = Error (Codegen_api.Rejected "unacceptable")
end

module Main_ok = struct
  let generate _ =
    Ok Codegen_api.{
      artifact = Production.{ requirement_id = "r"; paths = ["r.ml"] };
      note = "main";
    }
end

module R_main_backup = Codegen_router.Make(struct
  module Main = Main_fail
  module Backup = Backup_ok
end)

module R_both_fail = Codegen_router.Make(struct
  module Main = Main_fail
  module Backup = Both_fail
end)

module R_main = Codegen_router.Make(struct
  module Main = Main_ok
  module Backup = Both_fail
end)

let request =
  Codegen_api.{
    requirement = Production.{ id = "r"; statement = "produce"; depends_on = []; acceptance = None };
    context = [];
    workspace = Workspace.{ root = "." };
  }

let pass = ref 0
let fail = ref 0

let check label condition =
  if condition then incr pass
  else begin incr fail; Printf.eprintf "FAIL: %s\n" label end

let () =
  begin match R_main_backup.generate request with
  | Codegen_router.Generated response -> check "backup is used after main failure" (response.note = "backup")
  | Codegen_router.Failed _ -> check "backup is used after main failure" false
  end;
  begin match R_main.generate request with
  | Codegen_router.Generated response -> check "main response is preserved" (response.note = "main")
  | Codegen_router.Failed _ -> check "main response is preserved" false
  end;
  begin match R_both_fail.generate request with
  | Codegen_router.Failed (Codegen_api.Transport _, Some (Codegen_api.Rejected _)) -> incr pass
  | _ -> check "both failures are preserved" false
  end;
  Printf.printf "codegen_router: %d passed, %d failed\n" !pass !fail;
  exit (if !fail = 0 then 0 else 1)
