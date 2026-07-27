#!/usr/bin/env bash
set -euo pipefail

binary="${1:-g4fig}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/g4fig-depth.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

"$binary" --list --max-depth 0 "$repo_root/test/minimal.gdml" \
  > "$scratch/depth-zero.tsv"
"$binary" --list --max-depth 1 "$repo_root/test/minimal.gdml" \
  > "$scratch/depth-one.tsv"

test "$(wc -l < "$scratch/depth-zero.tsv" | tr -d ' ')" = 2
test "$(wc -l < "$scratch/depth-one.tsv" | tr -d ' ')" = 3
test "$(tail -n +2 "$scratch/depth-zero.tsv" | cut -f5)" = 0
test "$(tail -n 1 "$scratch/depth-one.tsv" | cut -f5)" = 1

if "$binary" --max-depth -1 "$repo_root/test/minimal.gdml" \
  > /dev/null 2> "$scratch/negative.log"; then
  printf '%s\n' '--max-depth -1 unexpectedly succeeded' >&2
  exit 1
fi
grep -q -- '--max-depth must be a non-negative integer' "$scratch/negative.log"
