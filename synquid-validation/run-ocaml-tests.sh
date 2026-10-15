#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT

python3 "$ROOT/tools/test_lower.py"
python3 "$ROOT/tools/lower.py" "$ROOT/evidence/synquid-BST-Insert.out" "$BUILD/generated_bst.ml"
cmp "$ROOT/ocaml/generated_bst.ml" "$BUILD/generated_bst.ml"
cp "$ROOT/ocaml/test_bst.ml" "$BUILD/test_bst.ml"
cd "$BUILD"
ocamlc -w +8+11+26+27 -warn-error +8+11+26+27 generated_bst.ml test_bst.ml -o test_bst
./test_bst
ocamlopt -w +8+11+26+27 -warn-error +8+11+26+27 generated_bst.ml test_bst.ml -o test_bst_native
./test_bst_native

# Prove the property test detects a missing implementation, not just compilation.
cp "$ROOT/ocaml/control/generated_bst.ml" generated_bst.ml
ocamlc generated_bst.ml test_bst.ml -o negative_control
if ./negative_control > negative_control.log 2>&1; then
  echo 'ERROR: negative control unexpectedly passed' >&2
  exit 1
fi
grep -q 'exact set union' negative_control.log
printf 'PASS: negative control rejected; mechanical output reproduced\n'
