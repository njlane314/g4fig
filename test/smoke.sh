#!/usr/bin/env bash
set -euo pipefail

binary="${1:-g4fig}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/g4fig-smoke.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

"$binary" --list "$repo_root/test/minimal.gdml" > "$scratch/volumes.tsv"
"$binary" \
  --style 'target=#253746' \
  --label 'target=Graphite target' \
  --tracks "$repo_root/test/tracks.dat" \
  "$repo_root/test/minimal.gdml" > "$scratch/view.svg"

test "$(head -n 1 "$scratch/volumes.tsv")" = $'path\tphysical\tlogical\tmaterial\tdepth\tsolid\tfacets'
test "$(head -c 4 "$scratch/view.svg")" = '<svg'
grep -q 'mask="url(#mask-x)"' "$scratch/view.svg"
grep -q 'filter="url(#paper-halo)"' "$scratch/view.svg"
grep -q 'stroke="#2145f5"' "$scratch/view.svg"
