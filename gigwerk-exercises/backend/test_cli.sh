#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# The prebuilt CLI if present, otherwise the dune build of main.ml in this dir.
BIN="$ROOT/synquid-ocaml"
[[ -x "$BIN" ]] || BIN="$ROOT/_build/default/main.exe"
if [[ ! -x "$BIN" ]]; then
  echo 'FAIL: generic backend CLI is missing' >&2
  exit 1
fi
# Repo-relative; this was /home/ubuntu/synquid-validation in the sandbox it was written in.
VALIDATION="$ROOT/../../synquid-validation"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
printf 'Empty\t0\tBST\tnamed:Empty\nNode\t3\tBST\tnamed:Node\n' > "$WORK/constructors.tsv"
: > "$WORK/primitives.txt"
"$BIN" "$VALIDATION/evidence/synquid-BST-Insert.out" "$WORK/constructors.tsv" "$WORK/primitives.txt" > "$WORK/body.ml"
printf "type 'a bst = Empty | Node of 'a * 'a bst * 'a bst\n" > "$WORK/generated_bst.ml"
cat "$WORK/body.ml" >> "$WORK/generated_bst.ml"
cp "$VALIDATION/ocaml/test_bst.ml" "$WORK/test_bst.ml"
cd "$WORK"
printf "type 'a bst = Empty | Node of 'a * 'a bst * 'a bst\nval insert : int -> int bst -> int bst\n" > generated_bst.mli
ocamlc -c generated_bst.mli
ocamlc -w +8+11 -warn-error +8+11 generated_bst.ml test_bst.ml -o test_bst
./test_bst
printf 'PASS: generic backend lowered real Synquid output and preserved BST semantics\n'

# A required interface must reject a wrongly typed synthesized module.
printf 'val insert : bool -> int bst -> int bst\n' > wrong_signature.txt
printf "type 'a bst = Empty | Node of 'a * 'a bst * 'a bst\n" > generated_bst.mli
cat wrong_signature.txt >> generated_bst.mli
ocamlc -c generated_bst.mli
if ocamlc -c generated_bst.ml > interface-negative.log 2>&1; then
  echo 'FAIL: mismatched required interface was accepted' >&2
  exit 1
fi
grep -q 'not included' interface-negative.log
printf 'PASS: incompatible required OCaml interface rejected\n'
