#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOTFS=${SYNQUID_ROOTFS:-/home/ubuntu/synquid-runtime/bundle/rootfs}
if [[ ! -x "$ROOTFS/root/.cabal/bin/synquid" ]]; then
  echo 'Set SYNQUID_ROOTFS to the unpacked digest-pinned Synquid rootfs; see README.md.' >&2
  exit 1
fi
mkdir -p "$ROOT/evidence"
TIMEFORMAT='elapsed_seconds=%3R user_seconds=%3U system_seconds=%3S'
{ time timeout 120s proot -R "$ROOTFS" -b "$ROOT:/work" -w /work \
    /root/.cabal/bin/synquid contracts/BST-Insert.sq --output=Plain --print-stats \
    > "$ROOT/evidence/synquid-BST-Insert.out" \
    2> "$ROOT/evidence/synquid-BST-Insert.err"; } \
    2> "$ROOT/evidence/synthesis-timing.txt"
python3 "$ROOT/tools/lower.py" "$ROOT/evidence/synquid-BST-Insert.out" "$ROOT/ocaml/generated_bst.ml"
"$ROOT/run-ocaml-tests.sh"
