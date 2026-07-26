#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out_dir="$repo_root/out/orion"
gdml_path="$out_dir/orion.gdml"
source_url="https://geant4-data.web.cern.ch/datasets/examples/advanced/gorad/orion.gdml"
expected_sha256="27d5f01c1393911309e69b65fe601f0ab9cf5e5e43b04bbb585f2e47783d425a"

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

mkdir -p "$out_dir"

if [ ! -f "$gdml_path" ] || [ "$(sha256 "$gdml_path")" != "$expected_sha256" ]; then
  temporary="$(mktemp "$out_dir/orion.gdml.XXXXXX")"
  cleanup() {
    [ -z "${temporary:-}" ] || rm -f "$temporary"
  }
  trap cleanup EXIT
  curl --fail --location --retry 3 "$source_url" --output "$temporary"
  actual_sha256="$(sha256 "$temporary")"
  if [ "$actual_sha256" != "$expected_sha256" ]; then
    printf 'orion.gdml: checksum mismatch\nexpected: %s\nactual:   %s\n' \
      "$expected_sha256" "$actual_sha256" >&2
    exit 1
  fi
  mv "$temporary" "$gdml_path"
  temporary=""
fi

(
  cd "$repo_root"
  ./bin/g4fig \
    --size 1400x900 \
    --view 1,0.18,-0.16 \
    --line-width 0.48 \
    --depth-fade 0.88 \
    --fade 0.09 \
    --padding 0.07 \
    --style 's2_orion=#e56f47' \
    --style 's3_orion=#263f50' \
    --label 's2_orion=Orion spacecraft' \
    -o out/orion/orion.svg \
    out/orion/orion.gdml
)

printf '%s\n' "$out_dir/orion.svg"
if command -v rsvg-convert >/dev/null 2>&1; then
  rsvg-convert --output "$out_dir/orion.png" "$out_dir/orion.svg"
  printf '%s\n' "$out_dir/orion.png"
fi
