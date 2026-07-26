#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out_dir="$repo_root/out/cusp"
source_dir="$out_dir/source"
model_dir="$out_dir/model"
view_dir="$out_dir/views"
source_base="https://raw.githubusercontent.com/giovixo/g4cusp-rs/041373e2b7c592455c21ff170019b61396bc53e0/gdml-mass-model"
model_name="CUSP_GEANT4_Model_20240502.gdml"

source_records=(
  "CUSP_GEANT4_Model_20240502.gdml e9592832e0aa311ec4991baa701d15db103bc45015fe429dee0d6501e68df45c"
  "CUSP_GEANT4_Model_20240502-solids.xml fc1a8cdf81038c330a528cee74452c0bfe633c199a54934f1f3e0cbf41d44b43"
  "CUSP_GEANT4_Model_20240502-structure.xml 2804b52e0f6a6d8f3dc55ab4c0b67c9e5ee2fc87594ca7dcdc388625cec4abec"
  "define.xml 084f7f17b546eb2a21f8ad8eb0fbfadac5d7d9e4998ebf99bc2d25da00a45b9b"
  "materials.xml d6c6a368fa05061b665f267aaffa31ffc5722e764b414ecc09610ba694a01139"
  "setup.xml b4748b4138bccd3ab13023cc36220a11df804af11cfa3e18151f34ae19a8eca9"
)

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

mkdir -p "$source_dir" "$model_dir" "$view_dir"

for source_record in "${source_records[@]}"; do
  read -r source_name expected_sha256 <<< "$source_record"
  source_path="$source_dir/$source_name"
  if [ ! -f "$source_path" ] || [ "$(sha256 "$source_path")" != "$expected_sha256" ]; then
    temporary="$(mktemp "$source_dir/$source_name.XXXXXX")"
    cleanup() {
      [ -z "${temporary:-}" ] || rm -f "$temporary"
    }
    trap cleanup EXIT
    curl --fail --location --retry 3 \
      "$source_base/$source_name" \
      --output "$temporary"
    actual_sha256="$(sha256 "$temporary")"
    if [ "$actual_sha256" != "$expected_sha256" ]; then
      printf '%s: checksum mismatch\nexpected: %s\nactual:   %s\n' \
        "$source_name" "$expected_sha256" "$actual_sha256" >&2
      exit 1
    fi
    mv "$temporary" "$source_path"
    temporary=""
  fi
done

for source_name in \
  CUSP_GEANT4_Model_20240502.gdml \
  CUSP_GEANT4_Model_20240502-solids.xml \
  CUSP_GEANT4_Model_20240502-structure.xml \
  define.xml \
  setup.xml
do
  cp "$source_dir/$source_name" "$model_dir/$source_name"
done
cp "$repo_root/examples/cusp/materials.xml" "$model_dir/materials.xml"

convert_view() {
  view_name="$1"
  pdf_dpi="${2:-96}"
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert --width 1000 \
      --output "$view_dir/$view_name.png" \
      "$view_dir/$view_name.svg"
    rsvg-convert --dpi-x "$pdf_dpi" --dpi-y "$pdf_dpi" --format pdf \
      --output "$view_dir/$view_name.pdf" \
      "$view_dir/$view_name.svg"
  fi
}

render_whole() {
  view_name="$1"
  view_vector="$2"
  up_vector="$3"

  (
    cd "$repo_root"
    ./bin/g4fig \
      --size 1050x675 \
      --view "$view_vector" \
      --up "$up_vector" \
      --style 'G4_Al|Al10=#ff5a1f' \
      --style 'G4_PLASTIC_SC_VINYLTOLUENE=#0057ff' \
      --style 'GAGG=#e833a4' \
      --style 'G4_W=#ed4141' \
      --style 'G4_Ti|FR4=#21d94f' \
      --style 'TEFLON|POLYTRIFLUORO|PLEXIGLASS=#21d94f' \
      --label 'Detector_Frame=CUSP CubeSat' \
      --fade 0.09 \
      --depth-fade 0.72 \
      --line-width 0.66 \
      --padding 0.07 \
      --aux-edges \
      --max-lines 500000 \
      -o "out/cusp/views/$view_name.svg" \
      "out/cusp/model/$model_name"
  )
  convert_view "$view_name" 72
}

render_detail() {
  view_name="$1"
  view_vector="$2"
  up_vector="$3"
  selection_mode="$4"
  selection_pattern="$5"
  label_rule="$6"
  depth_fade="${7:-0.52}"
  line_width="${8:-0.72}"
  padding="${9:-0.07}"

  selection_args=("--$selection_mode" "$selection_pattern")
  (
    cd "$repo_root"
    ./bin/g4fig \
      --size 1400x900 \
      --view "$view_vector" \
      --up "$up_vector" \
      "${selection_args[@]}" \
      --style 'Frame|Truss|Column|Spacer=#ff5a1f' \
      --style 'PCB|MAPMT=#0057ff' \
      --style 'Scatterer=#21d94f' \
      --style 'Absorber=#ed4141' \
      --style 'Collimator|Filter|filter|Wrapping=#e833a4' \
      --label "$label_rule" \
      --fade 0.09 \
      --depth-fade "$depth_fade" \
      --line-width "$line_width" \
      --padding "$padding" \
      --max-lines 500000 \
      -o "out/cusp/views/$view_name.svg" \
      "out/cusp/model/$model_name"
  )
  convert_view "$view_name"
}

render_whole cusp-hero-oblique       '1,0.7,0.45'       '0,0,1'
render_whole cusp-opposite-oblique   '-1,-0.7,0.45'     '0,0,1'
render_whole cusp-x-profile          '1,0,0'            '0,0,1'
render_whole cusp-y-profile          '0,1,0'            '0,0,1'
render_whole cusp-z-axial            '0,0,1'            '0,1,0'
render_whole cusp-underside-oblique  '0.75,-0.55,-0.72' '0,0,1'
render_whole cusp-high-rear-oblique  '-0.65,0.85,0.9'   '0,0,1'

render_detail \
  cusp-detector-cutaway '1,-1,0.72' '0,0,1' exclude \
  'Ext_Panel|Top_Lid|Bottom_Lid|IF_Payload_Truss|Scintillator_Frame|Detector_Frame|Collimator_frame|PCB_ext' \
  'Scatterer_001=CUSP detector cutaway'

render_detail \
  cusp-scatterer-array '1,-1,0.72' '0,0,1' include \
  'Scatterer' \
  'Scatterer_001=CUSP scatterer array' \
  0.48 0.82 0.08

render_detail \
  cusp-absorber-array '0,1,0' '0,0,1' include \
  'Absorber|PCB_APD|MAPMT|PCB_board_MAPMT' \
  'Absorber_001=CUSP absorber array' \
  0.48 0.82 0.08

render_detail \
  cusp-axial-detector '0,1,0' '0,0,1' exclude \
  'PCB_ext' \
  'Detector_Frame=CUSP axial detector view'

render_detail \
  cusp-side-section '1,0,0' '0,0,1' exclude \
  'Ext_Panel|Top_Lid|Bottom_Lid|PCB_ext' \
  'Detector_Frame=CUSP side section'

printf '%s\n' "$view_dir"/cusp-*.svg
