# gigwerk — Phase 1

A capability-scoped task runner. OCaml 4.14 + `unix` + one C stub. No opam
packages, no Eio (that needs OCaml 5 and is a concurrency question, not a
capability one).

```sh
cd ocaml && dune build && dune test          # 16/16
sqlite3 ../gigwerk.db ".read ../sql/schema.sql"
./_build/default/bin/main.exe doctor
./_build/default/bin/main.exe run echo   --message hello
./_build/default/bin/main.exe run critic --artifact good.txt
```

## What Phase 1 settled

The open question was whether object-capability survives a process boundary.
Two answers, both now demonstrated rather than argued:

**1. A capability root is enforced by the kernel, not by a path check.**
`openat2` with `RESOLVE_BENEATH | RESOLVE_NO_SYMLINKS | RESOLVE_NO_MAGICLINKS`.
The dirfd never leaves C, so OCaml code has nothing to escape *with*, and the
kernel returns `EXDEV` for `..` out of the root, for absolute paths, and for a
symlink pointing outside. No sanitiser to have a bug in.

Sharp edge worth knowing: `RESOLVE_BENEATH` forbids **escaping** the root, not
`..` as syntax. `sub/../inside.txt` resolves fine because it never leaves. My
first test asserted the wrong property here.

**2. For `fork`, capabilities cross by inheritance. For `exec`, they do not.**
The dirfd is opened before the fork, so the child holds the same capability with
no `SCM_RIGHTS` dance. But the fd is `O_CLOEXEC` — passing capabilities across
an `exec` needs `SCM_RIGHTS` or re-derivation under a Landlock ruleset applied
before the exec. Phase 1 uses fork only. **This is the one thing to settle before
subprocess actors with distinct binaries.**

**3. An unclaimed capability is not a field.** Behaviors declare their
requirements in their type — `critic : critic_caps -> artifact:string -> verdict`
versus `echo : unit -> msg:string -> verdict`. Handing echo's empty record to
`critic` is a compile error, verified with a negative build:

```
Error: This expression should not be a unit literal, the expected type is
       Gigwerk.Behaviors.critic_caps
```

## Two bugs the ledger caught

Both were invisible until real rows existed.

`last_insert_rowid()` is per-connection and the `sqlite3` CLI opens a new one per
invocation, so every gig got `id=0` and every outcome was orphaned. Fixed by
running the insert and the rowid read in one script.

`matched` was reporting `yes` for a critic that couldn't read its artifact.
`matched` answers *did the actor do its job*, not *was the artifact good* — a
critic that correctly reports a bad artifact is matched; one that produces no
verdict is not. Since `matched` feeds the confidence rule, mislabeling here
would have silently corrupted every band. The prediction strings were wrong too:
they predicted things about the artifact rather than about the actor.

## Deliberate Phase 1 shortcuts

- **`sqlite3` CLI, not libsqlite3.** Keeps Phase 1 opam-free. Every call goes
  through `lib/store.ml`; swap it when the dependency is worth having.
- **`Unix.alarm`, not `setrlimit`.** Catches the wall clock. Memory and fd
  limits are not enforced yet.
- **No gate.** Compositions are read and constructed; nothing validates them
  beyond the schema's foreign keys. Until Phase 2 exists this is a runner, not a
  harness — it cannot refuse.
- **No Landlock, no seccomp.** The capability root is the only enforcement.
