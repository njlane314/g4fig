#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out_dir="$repo_root/out/hirax"
gdml_path="$out_dir/geometry_hirax.gdml"
source_url="https://raw.githubusercontent.com/aditikatoch/HIRAX_Radiation_Model/6c9e38c71259acca6c093847c0abd964ab536e53/geometry/geometry_hirax.gdml"
expected_sha256="b8014e648007113d9aabb86151638fc7d028e5cfc74ec998a3410ccef118a624"

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

mkdir -p "$out_dir"

if [ ! -f "$gdml_path" ] || [ "$(sha256 "$gdml_path")" != "$expected_sha256" ]; then
  temporary="$(mktemp "$out_dir/geometry_hirax.gdml.XXXXXX")"
  cleanup() {
    [ -z "${temporary:-}" ] || rm -f "$temporary"
  }
  trap cleanup EXIT
  curl --fail --location --retry 3 "$source_url" --output "$temporary"
  actual_sha256="$(sha256 "$temporary")"
  if [ "$actual_sha256" != "$expected_sha256" ]; then
    printf 'geometry_hirax.gdml: checksum mismatch\nexpected: %s\nactual:   %s\n' \
      "$expected_sha256" "$actual_sha256" >&2
    exit 1
  fi
  mv "$temporary" "$gdml_path"
  temporary=""
fi

convert_view() {
  view_name="$1"
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert --format pdf \
      --output "$out_dir/$view_name.pdf" \
      "$out_dir/$view_name.svg"
    rsvg-convert --width 1000 \
      --output "$out_dir/$view_name.png" \
      "$out_dir/$view_name.svg"
  fi
}

render_whole() {
  view_name="$1"
  view_vector="$2"
  up_vector="$3"

  (
    cd "$repo_root"
    ./bin/g4fig \
      --size 1400x900 \
      --view "$view_vector" \
      --up "$up_vector" \
      --aux-edges \
      --sides 40 \
      --line-width 0.62 \
      --depth-fade 0.58 \
      --fade 0.09 \
      --padding 0.07 \
      --style 'Bus|MLI|Casing=#ff5a1f' \
      --style 'Solar_Panel=#0057ff' \
      --style 'Truss|trussVol=#21d94f' \
      --style 'Detector=#ed4141' \
      --style 'Mirror=#e833a4' \
      --style 'Mirror_2=#0057ff' \
      --style 'Mirror_3=#ed4141' \
      --style 'Mirror_4=#ff5a1f' \
      --label 'Bus=HIRAX spacecraft' \
      -o "out/hirax/$view_name.svg" \
      out/hirax/geometry_hirax.gdml
  )
  convert_view "$view_name"
}

render_technical() {
  view_name="$1"
  view_vector="$2"
  up_vector="$3"
  label_text="$4"

  (
    cd "$repo_root"
    ./bin/g4fig \
      --size 1400x900 \
      --view "$view_vector" \
      --up "$up_vector" \
      --line-width 0.96 \
      --depth-fade 0.50 \
      --fade 0.09 \
      --padding 0.07 \
      --style 'Bus|MLI|Casing=#ff5a1f' \
      --style 'Solar_Panel=#0057ff' \
      --style 'Truss=#21d94f' \
      --style 'Detector=#ed4141' \
      --style 'Mirror_=#e833a4' \
      --style 'Mirror_.*Coat=#0057ff' \
      --style 'Shield=#ff5a1f' \
      --label "MLI=$label_text" \
      -o "out/hirax/$view_name.svg" \
      out/hirax/geometry_hirax.gdml
  )
  convert_view "$view_name"
}

render_whole hirax-hero-oblique '1,0.55,0.32' '0,1,0'
render_whole hirax-opposite-rear '-1,-0.45,0.28' '0,1,0'
render_whole hirax-aft-oblique '0.30,-0.22,-1' '0,1,0'
render_whole hirax-port-profile '1,0,0' '0,1,0'
render_whole hirax-dorsal-profile '0,1,0' '1,0,0'
render_whole hirax-forward-axial '0,0,1' '0,1,0'

render_technical hirax-plan '0.18,1,0.12' '1,0,0' 'HIRAX plan view'
render_technical hirax-underside '-0.22,-1,-0.14' '1,0,0' 'HIRAX underside'

(
  cd "$repo_root"
  ./bin/g4fig \
    --size 1400x900 \
    --view '0.15,0.18,1' \
    --up '0,1,0' \
    --include 'Mirror_[13]' \
    --line-width 1.18 \
    --depth-fade 0.42 \
    --fade 0.09 \
    --padding 0.09 \
    --style 'Mirror_1=#e833a4' \
    --style 'Mirror_3=#ed4141' \
    --style 'Mirror_.*Coat=#0057ff' \
    --label 'Mirror_=Collecting mirror array' \
    -o out/hirax/hirax-mirror-detail.svg \
    out/hirax/geometry_hirax.gdml
)
convert_view hirax-mirror-detail

(
  cd "$repo_root"
  ./bin/g4fig \
    --size 1400x900 \
    --view '0.62,0.46,1' \
    --up '0,1,0' \
    --include 'Bus|Detector|Shield' \
    --aux-edges \
    --sides 40 \
    --line-width 0.82 \
    --depth-fade 0.62 \
    --fade 0.09 \
    --padding 0.08 \
    --style 'Bus=#ff5a1f' \
    --style 'Detector=#ed4141' \
    --style 'Shield=#e833a4' \
    --label 'Detector=Shielded detector bay' \
    -o out/hirax/hirax-detector-bay.svg \
    out/hirax/geometry_hirax.gdml
)
convert_view hirax-detector-bay

printf '%s\n' "$out_dir"/hirax-*.svg
