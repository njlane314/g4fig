#!/usr/bin/env bash
set -euo pipefail

binary="${1:-g4fig}"
entrypoint="${2:-}"
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
grep -q 'stroke="#ff5a1f"' "$scratch/view.svg"
grep -q 'stroke="#2145f5"' "$scratch/view.svg"

if [[ -n "$entrypoint" ]]; then
  G4FIG_RENDERER="$binary" "$entrypoint" \
    "$repo_root/test/minimal.gdml" > "$scratch/entrypoint.svg"
  G4FIG_RENDERER="$binary" "$entrypoint" \
    -o "$scratch/view.png" "$repo_root/test/minimal.gdml"
  G4FIG_RENDERER="$binary" "$entrypoint" \
    -o "$scratch/view.pdf" "$repo_root/test/minimal.gdml"
  G4FIG_RENDERER="$binary" "$entrypoint" \
    -o "$scratch/list.png" --list "$repo_root/test/minimal.gdml"
  G4FIG_RENDERER="$binary" "$entrypoint" \
    --list "$repo_root/test/minimal.gdml" > "$scratch/list.tsv"

  test "$(head -c 4 "$scratch/entrypoint.svg")" = '<svg'
  test "$(od -An -tx1 -N8 "$scratch/view.png" | tr -d ' \n')" = '89504e470d0a1a0a'
  test "$(head -c 4 "$scratch/view.pdf")" = '%PDF'
  test "$(head -n 1 "$scratch/list.png")" = $'path\tphysical\tlogical\tmaterial\tdepth\tsolid\tfacets'
  cmp "$scratch/list.png" "$scratch/list.tsv"
fi
