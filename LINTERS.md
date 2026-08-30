# Linters and LSP — located, and each one proven able to fail

`./lint.sh` runs everything. `./lint.sh sql` runs one language.

A checker that only ever prints "clean" has not been located, it has been
*found*. Every entry below names the real fault it was proven against, by
introducing that fault and watching the checker reject it.

## Per language

| language | checker | where | proven to fail against |
|---|---|---|---|
| OCaml | `dune build @check` | `/usr/bin/dune` 3.14.0 | `let unused_probe x = 1` → warning 27 promoted to error |
| C | `gcc -fsyntax-only -Wall -Wextra -Werror` | `/usr/bin/gcc` | `syscal` for `syscall` → implicit-declaration |
| C | `clang --analyze` (path-sensitive) | `/usr/bin/clang` | — clean on `caps_stubs.c`; kept because `-Wall` cannot see paths |
| SQL | `sqlite3 :memory: .read` with `.bail on` | `/usr/bin/sqlite3` | `decision='maybe'`, `attaches_to='elsewhere'` → CHECK rejects |
| Prolog | `swipl -g "consult(F), check"` | `/usr/bin/swipl` 9.0.4 | `go :- nope(1).` → *nope/1 not defined*; `p(X) :- q(1).` → singleton `X` |
| Elpi | typecheck on `accumulate` | `/usr/local/bin/elpi` 3.7.2 | `type capability int -> …` → *Cap has type string but capability expects int* |

Three of these are not conventional linters and are the more valuable half:

**sqlite's own parser is the SQL linter, and it does more than parse.** Loading a
file exercises every CHECK, every FK declaration and every trigger. `lint.sh`
additionally attempts two inserts that *must* be rejected, because a schema whose
constraints do not fire is indistinguishable from a schema without them.

**`check/0` is the Prolog check that matters.** Syntax errors are the easy case.
The dangerous failure is a predicate referenced but never defined: the goal
*fails* rather than erroring, and a failed confidence goal looks exactly like a
low band. `check/0` names those.

**Elpi has no `-typecheck` flag** in 3.7.2 — it was tried, and it is not an
option. Typechecking happens on load, so accumulating the file from a driver is
the check. The driver's probe predicate must be `pred gw_lint_probe i:list
string` and not a nullary `main`: `gate.elpi` already declares `pred main i:list
string`, so a driver defining its own `main` fails the typechecker *on the
driver*, and the checker reports its own bug as the subject's.

## Not obtainable in this sandbox

`ocamlformat` and `ocaml-lsp-server` both resolve cleanly against the local opam
repository (`ocaml-lsp-server.1.21.0-4.14`, `ocamlformat.0.29.0`) and both fail
to install, because the egress allowlist blocks the hosts their sources live on:

- `erratique.ch` (uutf, uuseg, uucp, topkg) — curl exit 56
- `ocaml.janestreet.com` (base, sexplib0, stdio, ppx_yojson_conv_lib) — curl 56
- `gitlab.inria.fr` (menhir) — curl 56
- `github.com/*/archive/refs/tags/*` — HTTP 403

`github.com/*/releases/download/*` is *not* blocked (yojson 2.2.2 installed from
there), so this is a per-host allowlist rather than a general block. Nothing in
the repo can fix it.

On a machine without that allowlist — Parrot OS included — `opam install
ocaml-lsp-server ocamlformat` is the whole story, and the dry-run above says it
will resolve for this 4.14.1 switch without pinning anything.

## LSP: merlin, and it works

`ocaml-lsp-server` is a thin LSP wrapper around merlin. Merlin itself is in apt
and is installed:

    /usr/bin/ocamlmerlin
    /usr/bin/ocamlmerlin-server      ocaml-merlin 4.13-414
    /usr/bin/ocp-indent              1.8.2

Verified against this tree, not assumed. Type-at-point on `Booking.form_sig`:

    $ ocamlmerlin single type-enclosing -position 137:5 -filename lib/booking.ml
    "cap_set:string list -> policy_set:string list ->
     state_shape:string -> widen_epoch:int -> string"

and error reporting on a buffer with an unbound field:

    $ ocamlmerlin single errors -filename lib/terms.ml
    {"type":"typer","message":"Unbound record field nope","line":79,"col":27}

Merlin reads dune's generated config, so it needs `dune build @check` to have run
once and nothing else. Editors with a merlin plugin (vim, emacs) talk to it
natively. An editor that speaks only LSP needs `ocaml-lsp-server`, which is the
one piece this sandbox cannot fetch.

## What is deliberately NOT here

`ocamlformat` is listed as advisory in `lint.sh` and skipped when no
`.ocamlformat` exists — which is the current state. Adopting a profile would
reflow every WHY comment in the tree, and those comments carry most of the
argument. Formatting is worth adding once the design stops moving, not before.

Shell has no checker: `shellcheck` is not installed and not in apt here.
`lint.sh` is the only shell in the repo, which makes this a small hole and a
named one.
