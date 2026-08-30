#!/bin/sh
# Per-language linters for gigwerk. One checker per language, because a single
# checker over five languages is a checker that shares a failure mode with
# whatever generated the code.
#
#   ./lint.sh          run everything
#   ./lint.sh sql      run one language
#
# Every checker here has been proven able to FAIL on a real fault -- a linter
# that only ever prints "clean" is a linter you have not located, you have only
# found. The fault each one was proven against is named in its comment.

set -u
cd "$(dirname "$0")" || exit 2
fails=0
want="${1:-all}"
run() { [ "$want" = all ] || [ "$want" = "$1" ]; }
say() { printf '\n== %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }
ok()  { printf '  ok   %s\n' "$1"; }

OCAMLLIB="$(ocamlc -where 2>/dev/null || echo /usr/lib/ocaml)"

# ---------------------------------------------------------------- ocaml
# dune's @check builds .cmi/.cmt without linking, so it typechecks everything
# including tests. Proven against: `let f x = 1` -> warning 27, unused variable,
# which dune promotes to an error in the dev profile.
if run ocaml; then
  say "ocaml -- dune @check (typecheck, warnings are errors)"
  if (cd ocaml && dune build @check 2>&1) | grep -q .; then
    (cd ocaml && dune build @check 2>&1) | head -30
    bad "dune @check"
  else ok "dune @check"; fi

  # ocamlformat is advisory here: the repo has no .ocamlformat, and adopting one
  # would reflow every WHY comment in the tree. Reported, never failed on.
  if command -v ocamlformat > /dev/null 2>&1; then
    say "ocaml -- ocamlformat (advisory, no .ocamlformat in repo)"
    if [ -f .ocamlformat ]; then
      for f in ocaml/lib/*.ml ocaml/bin/*.ml ocaml/test/*.ml; do
        ocamlformat --check "$f" > /dev/null 2>&1 || printf '  drift %s\n' "$f"
      done
    else printf '  skipped: no .ocamlformat (adopting one would reflow every comment)\n'; fi
  fi
fi

# ------------------------------------------------------------------- c
# Proven against: `syscal` for `syscall` -> implicit-declaration warning. This is
# the one language where a typo compiles and then fails at runtime, so -Werror
# is not paranoia.
if run c; then
  say "c -- gcc -fsyntax-only -Wall -Wextra -Werror"
  for f in ocaml/lib/*.c; do
    if gcc -fsyntax-only -Wall -Wextra -Werror -I"$OCAMLLIB" "$f" 2>&1 | grep -q .; then
      gcc -fsyntax-only -Wall -Wextra -Werror -I"$OCAMLLIB" "$f" 2>&1 | head -20
      bad "$f"
    else ok "$f"; fi
  done
  if command -v clang > /dev/null 2>&1; then
    say "c -- clang --analyze (path-sensitive; catches what -Wall cannot)"
    for f in ocaml/lib/*.c; do
      out=$(clang --analyze -Xanalyzer -analyzer-output=text \
              -I"$OCAMLLIB" "$f" -o /dev/null 2>&1 | grep -c warning)
      [ "$out" = 0 ] && ok "$f" || { clang --analyze -Xanalyzer -analyzer-output=text -I"$OCAMLLIB" "$f" -o /dev/null 2>&1 | head -20; bad "$f (analyser)"; }
    done
  fi
fi

# ----------------------------------------------------------------- sql
# sqlite's own parser IS the linter, and it does more than parse: loading the
# file exercises every CHECK, FK declaration and trigger. Proven against:
# decision='maybe' and attaches_to='elsewhere', both rejected by CHECK.
#
# The `wal`/`memory` filter is the journal_mode pragma echoing its result, not
# output. -bail turns the first error into a nonzero exit.
if run sql; then
  say "sql -- sqlite3 parse + constraint load"
  for f in sql/persist.sql sql/memory.sql sql/soul.sql sql/seed.sql; do
    out=$(sqlite3 :memory: ".bail on" ".read sql/schema.sql" ".read $f" 2>&1 \
          | grep -vE '^(wal|memory)$')
    [ -z "$out" ] && ok "$f" || { printf '  %s\n' "$out"; bad "$f"; }
  done
  out=$(sqlite3 :memory: ".bail on" ".read sql/schema.sql" 2>&1 | grep -vE '^(wal|memory)$')
  [ -z "$out" ] && ok "sql/schema.sql" || { printf '  %s\n' "$out"; bad "sql/schema.sql"; }

  say "sql -- the CHECKs must actually reject (a check that cannot fail is not a check)"
  neg=$(sqlite3 :memory: ".read sql/schema.sql" ".read sql/seed.sql" \
    "INSERT INTO booking_verdict (entity_id,composition_sig,decision,reasons,decided_at,decided_by,attaches_to) VALUES (1,'x','maybe','r',0,'conditions','composition');" 2>&1 | grep -c "CHECK constraint failed")
  [ "$neg" -ge 1 ] && ok "decision CHECK rejects an unknown verdict" \
                   || bad "decision CHECK did NOT reject 'maybe'"
  neg=$(sqlite3 :memory: ".read sql/schema.sql" ".read sql/seed.sql" \
    "INSERT INTO booking_verdict (entity_id,composition_sig,decision,reasons,decided_at,decided_by,attaches_to) VALUES (1,'x','book','r',0,'elpi','elsewhere');" 2>&1 | grep -c "CHECK constraint failed")
  [ "$neg" -ge 1 ] && ok "attaches_to CHECK rejects an unknown attachment" \
                   || bad "attaches_to CHECK did NOT reject 'elsewhere'"
fi

# -------------------------------------------------------------- prolog
# consult catches syntax and singleton variables; check/0 catches predicates
# referenced but never defined -- the failure mode that matters most here,
# because a missing predicate makes a goal FAIL rather than error, and a failed
# confidence goal looks exactly like a low band.
# Proven against: `go :- nope(1).` -> "brk:nope/1 ... not defined", and
# `p(X) :- q(1).` -> "Singleton variables: [X]".
if run prolog; then
  say "prolog -- swipl consult + check/0"
  for f in prolog/*.pl; do
    out=$(swipl -q -g "consult('$f'), check" -t halt 2>&1 | grep -vE '^\s*$')
    [ -z "$out" ] && ok "$f" || { printf '  %s\n' "$out" | head -20; bad "$f"; }
  done
  say "prolog -- the test suite is part of the lint"
  out=$(swipl -q -g "consult('prolog/confidence.pl'), run_tests" -t halt 2>&1 | tail -3)
  case "$out" in
    *failed*|*error*) printf '  %s\n' "$out"; bad "confidence.pl tests" ;;
    *) ok "confidence.pl tests" ;;
  esac
fi

# ---------------------------------------------------------------- elpi
# elpi typechecks on load; there is no separate -typecheck flag in 3.7.2 (it was
# tried, and it is not an option). Accumulating the file from a driver is
# therefore the check. Proven against: changing `type capability string -> ...`
# to `int -> ...` -> "Cap has type string but capability expects ... int".
if run elpi; then
  say "elpi -- typecheck on accumulate"
  for f in elpi/gate.elpi elpi/hoas.elpi; do
    [ -f "$f" ] || continue
    base=$(printf '%s' "$f" | sed 's/\.elpi$//')
    drv=$(mktemp /tmp/gwlint_XXXXXX.elpi)
    # The probe predicate needs its own name AND its own type declaration.
    # `main` is already declared in gate.elpi as `pred main i:list string`, so a
    # driver defining a nullary `main` fails the typechecker on the driver rather
    # than on the file under test -- which is a checker reporting its own bug as
    # the subject's. Declaring the probe also silences elpi's undeclared-globals
    # warning, so a real warning is not lost in noise.
    printf 'accumulate "%s/%s".\npred gw_lint_probe i:list string.\ngw_lint_probe _ :- print "typechecked".\n' \
      "$PWD" "$base" > "$drv"
    out=$(elpi "$drv" -exec gw_lint_probe 2>&1 \
          | grep -E "Typechecker:|Fatal error|Parsing error|Undeclared globals" | head -5)
    rm -f "$drv"
    [ -z "$out" ] && ok "$f" || { printf '  %s\n' "$out"; bad "$f"; }
  done
fi

printf '\n%s\n' "-----------------------------------------------"
if [ "$fails" -eq 0 ]; then printf 'lint: clean\n'; else printf 'lint: %d failing\n' "$fails"; fi
exit $((fails > 0))
