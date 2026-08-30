(* Capabilities as values.
 *
 * The types here are abstract on purpose. A behavior receives a record holding
 * exactly the capabilities its composition claimed; a capability it did not
 * claim is not a denied field, it is a field that does not exist in its
 * parameter type. There is no ambient namespace to reach through and no
 * permission check to get wrong, because there is nothing to check.
 *
 * `scope` is a constructor argument, not a pattern matched later. An fs_read
 * built at /srv/work IS /srv/work -- the dirfd has no parent. *)

external gw_open_dir     : string -> int         = "gw_open_dir"
external gw_close_fd     : int -> unit           = "gw_close_fd"
external gw_read_at      : int -> string -> string = "gw_read_at"
external gw_have_openat2 : unit -> bool          = "gw_have_openat2"

let have_openat2 = gw_have_openat2

(* ------------------------------------------------------------- fs_read *)

type fs_read = { dirfd : int; root : string }

(* The root is the ONE path this layer resolves by name; everything under it is
 * resolved by the kernel from the dirfd. An empty root would open the process
 * cwd, which is an ambient authority the composition never claimed -- so it is
 * refused here rather than silently becoming "wherever gigwerk was launched".
 * (An earlier version of this guard read `if not (is_relative root) || true`,
 * which is unconditionally true with both branches empty: it checked nothing
 * and read as though it did. Relative-vs-absolute is not the property that
 * matters anyway -- openat2 does not care, and a relative root is a legitimate
 * way to name a directory beneath the launch point.) *)
let fs_read ~root =
  if String.trim root = "" then
    failwith "fs_read: empty capability root would open the process cwd";
  { dirfd = gw_open_dir root; root }

(* Reads are resolved by the kernel with RESOLVE_BENEATH. We do not sanitise
 * the path -- sanitisers have bugs. The kernel returns EXDEV for "..", for an
 * absolute path, and for a symlink pointing out. *)
let read (c : fs_read) name = gw_read_at c.dirfd name

let fs_read_root (c : fs_read) = c.root
let fs_read_close (c : fs_read) = gw_close_fd c.dirfd

(* --------------------------------------------------------- sqlite_query *)

type sqlite_ro = { db : string }

let sqlite_ro ~db = { db }

(* Read-only by construction: the URI carries mode=ro, so a write is refused by
 * sqlite itself rather than by us remembering to check. *)
let query (c : sqlite_ro) sql =
  let uri = Printf.sprintf "file:%s?mode=ro" c.db in
  let cmd = Printf.sprintf "sqlite3 -noheader -separator '\\t' '%s' %s"
              uri (Filename.quote sql) in
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 1024 in
  (try
     while true do Buffer.add_channel buf ic 1 done
   with End_of_file -> ());
  ignore (Unix.close_process_in ic);
  Buffer.contents buf |> String.split_on_char '\n'
  |> List.filter (fun s -> String.trim s <> "")

let sqlite_db (c : sqlite_ro) = c.db
