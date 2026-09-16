type outcome =
  | Generated of Codegen_api.response
  | Failed of Codegen_api.error * Codegen_api.error option

module type CONFIG = sig
  module Main : Codegen_api.S
  module Backup : Codegen_api.S
end

module Make (C : CONFIG) = struct
  let generate request =
    match C.Main.generate request with
    | Ok response -> Generated response
    | Error main_error ->
        match C.Backup.generate request with
        | Ok response -> Generated response
        | Error backup_error -> Failed (main_error, Some backup_error)
end
