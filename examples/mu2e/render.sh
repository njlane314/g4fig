#!/usr/bin/env bash
set -euo pipefail

example_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$example_dir/../.." && pwd)"
out_dir="$repo_root/out/mu2e"
source_dir="$out_dir/source"
view_dir="$out_dir/views"
log_dir="$out_dir/logs"
inventory_dir="$out_dir/inventory"
manifest="$example_dir/SOURCES.tsv"
g4fig_bin="${G4FIG_BIN:-$repo_root/bin/g4fig}"

requested_views=("$@")
generated_views=()
if [ "${#requested_views[@]}" -eq 0 ]; then
  requested_views=(
    solenoid-train
    facility-cutaway
    detector-cutaway
    detector-core
    detector-axial
  )
fi

for requested_view in "${requested_views[@]}"; do
  case "$requested_view" in
    solenoid-train|facility-cutaway|detector-cutaway|detector-core|detector-axial) ;;
    *)
      printf 'unknown view: %s\n' "$requested_view" >&2
      printf '%s\n' \
        'choose from: solenoid-train facility-cutaway detector-cutaway detector-core detector-axial' >&2
      exit 2
      ;;
  esac
done

want_view() {
  local candidate="$1"
  local requested_view
  for requested_view in "${requested_views[@]}"; do
    [ "$requested_view" = "$candidate" ] && return 0
  done
  return 1
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

for required_command in curl tar rsvg-convert; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf '%s is required\n' "$required_command" >&2
    exit 1
  }
done
[ -x "$g4fig_bin" ] || {
  printf 'g4fig is not executable: %s\n' "$g4fig_bin" >&2
  exit 1
}

if [ "$(awk 'END {print NR}' "$manifest")" -ne 2 ]; then
  printf 'expected exactly one source row in %s\n' "$manifest" >&2
  exit 1
fi

IFS=$'\t' read -r model image tag layer_digest member expected_sha256 \
  source_page licence < <(sed -n '2p' "$manifest")
if [ "$model" != mu2e-v7.4.1 ] ||
   [ "$image" != mu2e/user ] ||
   [ "$tag" != tutorial_1-03 ] ||
   [ "$layer_digest" != sha256:fb87d37d1862fa08d8fdc65c34294ea7b58c4abe905c1259e4dda06a19bec8f2 ] ||
   [ "$member" != Tutorials_2019/GeometryBrowsing/mu2e_v7_4_1.gdml ] ||
   [ "$expected_sha256" != 83839a4a488a7f77f5b2cd25c3d091c09095298f2349b9b93c60e35da7e6eec1 ]; then
  printf 'unexpected Mu2e source manifest entry\n' >&2
  exit 1
fi

mkdir -p "$source_dir" "$view_dir" "$log_dir" "$inventory_dir"
gdml_path="$source_dir/mu2e_v7_4_1.gdml"
temporary=""
cleanup() {
  if [ -n "${temporary:-}" ] && [ -f "$temporary" ]; then
    rm -f "$temporary"
  fi
}
trap cleanup EXIT

download_gdml() {
  local token blob_url curl_status tar_status actual_sha256
  local download_log="$log_dir/source-download.log"
  local pipeline_status

  if [ -f "$gdml_path" ] &&
     [ "$(sha256 "$gdml_path")" = "$expected_sha256" ]; then
    printf 'using verified %s\n' "$gdml_path" > "$download_log"
    return
  fi

  token="$(
    curl --fail --silent --show-error --location --retry 3 \
      "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$image:pull" \
      2> "$download_log" |
      sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
  )"
  if [ -z "$token" ]; then
    printf 'could not obtain a Docker Registry token; see %s\n' "$download_log" >&2
    exit 1
  fi

  temporary="$(mktemp "$source_dir/mu2e_v7_4_1.gdml.XXXXXX")"
  blob_url="https://registry-1.docker.io/v2/$image/blobs/$layer_digest"

  # tar stops the stream after the requested member. curl may then report 23
  # or 56 because its consumer deliberately closed the pipe.
  set +e
  curl --fail --silent --show-error --location --retry 3 \
    --header "Authorization: Bearer $token" \
    "$blob_url" 2>> "$download_log" |
    tar --fast-read -xOzf - "$member" > "$temporary"
  pipeline_status=("${PIPESTATUS[@]}")
  set -e
  curl_status="${pipeline_status[0]}"
  tar_status="${pipeline_status[1]}"

  case "$curl_status" in
    0|23|56) ;;
    *)
      printf 'Mu2e layer stream failed; see %s\n' "$download_log" >&2
      exit 1
      ;;
  esac
  if [ "$tar_status" -ne 0 ]; then
    printf 'Mu2e member extraction failed; see %s\n' "$download_log" >&2
    exit 1
  fi

  actual_sha256="$(sha256 "$temporary")"
  if [ "$actual_sha256" != "$expected_sha256" ]; then
    printf '%s: checksum mismatch\nexpected: %s\nactual:   %s\n' \
      "$member" "$expected_sha256" "$actual_sha256" >&2
    exit 1
  fi
  mv "$temporary" "$gdml_path"
  temporary=""
}

convert_view() {
  local view_name="$1"
  rsvg-convert --width 1000 \
    --output "$view_dir/$view_name.png" \
    "$view_dir/$view_name.svg"
  rsvg-convert --format pdf --dpi-x 96 --dpi-y 96 \
    --output "$view_dir/$view_name.pdf" \
    "$view_dir/$view_name.svg"
}

render_view() {
  local view_name="$1"
  shift

  temporary="$(mktemp "$view_dir/$view_name.svg.XXXXXX")"
  if ! (
    cd "$repo_root"
    "$g4fig_bin" "$@" "out/mu2e/source/mu2e_v7_4_1.gdml"
  ) > "$temporary" 2> "$log_dir/$view_name.log"; then
    printf '%s: render failed; see %s\n' \
      "$view_name" "$log_dir/$view_name.log" >&2
    tail -n 20 "$log_dir/$view_name.log" >&2
    exit 1
  fi
  mv "$temporary" "$view_dir/$view_name.svg"
  temporary=""
  convert_view "$view_name"
  generated_views+=(
    "$view_dir/$view_name.svg"
    "$view_dir/$view_name.pdf"
    "$view_dir/$view_name.png"
  )
}

download_gdml

if ! (
  cd "$repo_root"
  "$g4fig_bin" --list "out/mu2e/source/mu2e_v7_4_1.gdml"
) > "$inventory_dir/mu2e-v7.4.1.tsv" 2> "$log_dir/inventory.log"; then
  printf 'Mu2e inventory failed; see %s\n' "$log_dir/inventory.log" >&2
  tail -n 20 "$log_dir/inventory.log" >&2
  exit 1
fi

if want_view solenoid-train; then
  render_view mu2e-solenoid-train \
    --size 1400x900 --view '1,0.58,0.36' --up '1,-0.32,0' \
    --include 'PSVac|PSRing|PSEnclosure|PSCoil|PSShield|ProductionTarget|TS[1-5]|DSInner|DSOuter|DSCryo|DSCoil|DSUpEndWall|DSDownEndWall|DSFront|DSRing' \
    --exclude 'dirt|Dirt|foundation|Foundation|CONCRETE|MBOverburden|CA7Backfill|VirtualDetector' \
    --style 'SCCable=#21d94f' \
    --style 'DS1CoilMix|DS2CoilMix=#e833a4' \
    --style 'G4_Al=#ff5a1f' \
    --style 'StainlessSteel=#0057ff' \
    --style 'PSVacuum|DSVacuum=#00a7c4' \
    --style 'StoppingTarget_Al=#ed4141' \
    --fade 0.095 --depth-fade 0.72 --line-width 0.86 --padding 0.06 \
    --sides 28 --max-lines 2000000
fi

if want_view facility-cutaway; then
  render_view mu2e-facility-cutaway \
    --size 1400x900 --view '1,0.58,0.36' --up '1,-0.32,0' \
    --include 'CONCRETE_MARS|PSVac|PSRing|PSEnclosure|PSCoil|PSShield|ProductionTarget|TS[1-5]|DSInner|DSOuter|DSCryo|DSCoil|DS[123]Vacuum|CRSScintillatorBar' \
    --exclude 'dirt|Dirt|backfill|Backfill|Foundation|Ceiling|Upper|Roof|VirtualDetector|Straw|Wire|ROBox|ROPV|ROElectro|Electronics|Readout|FEB|Cable' \
    --style 'CONCRETE_MARS=#76b7c4' \
    --style 'CRSScintillatorBar|CRV_R1=#e833a4' \
    --style 'SCCable=#21d94f' \
    --style 'DS1CoilMix|DS2CoilMix=#f2b705' \
    --style 'G4_Al=#ff5a1f' \
    --style 'StainlessSteel=#0057ff' \
    --style 'PSVacuum|DSVacuum=#00a7c4' \
    --style 'StoppingTarget_Al=#ed4141' \
    --fade 0.095 --depth-fade 0.80 --line-width 0.58 --padding 0.055 \
    --sides 20 --max-lines 1500000
fi

if want_view detector-cutaway; then
  render_view mu2e-detector-cutaway \
    --size 1400x900 --view '0.38,1,0.30' --up '1,-0.38,0' \
    --include 'DS1Vacuum|DS2Vacuum|DS3Vacuum|DSInner|DSOuter|DSCryo|DSCoil|DSUpEndWall|DSDownEndWall|DSFront|DSRing' \
    --exclude 'VirtualDetector|Straw|Wire|ROBox|ROPV|ROElectro|Electronics|Readout|FEB|Cable' \
    --style 'DS1Vacuum|DS2Vacuum|DS3Vacuum=#00a7c4' \
    --style 'DSInner|DSOuter|DSCryo|DSFront|DSRing=#0057ff' \
    --style 'DSCoil=#f2b705' \
    --style 'StoppingTarget|TargetFoil|FoilSupport=#ed4141' \
    --style 'Tracker|Panel|Plane|ThinSupport|TTracker=#21d94f' \
    --style 'Calorimeter|Disk|Crystal|Crys=#e833a4' \
    --style 'MBS|protonabs=#253746' \
    --fade 0.09 --depth-fade 0.77 --line-width 0.64 --padding 0.07 \
    --sides 30 --max-lines 650000
fi

render_detector_core() {
  local view_name="$1"
  shift
  render_view "$view_name" \
    --size 1400x900 "$@" \
    --include 'TrackerMother|CalorimeterMother|StoppingTargetMother' \
    --exclude 'VirtualDetector|Straw|Wire|ROBox|ROPV|ROElectro|Electronics|Readout|FEB|Cable' \
    --style 'StoppingTarget|TargetFoil|FoilSupport=#ed4141' \
    --style 'Tracker|Panel|Plane|ThinSupport|TTracker=#21d94f' \
    --style 'Calorimeter|calo|Disk|Crystal|Crys=#e833a4' \
    --style 'G4_Al|Aluminum=#ff5a1f' \
    --style 'G4_Cu|Copper|Bronze|Brass=#ff9d00' \
    --fade 0.09 --line-width 0.82 --padding 0.07 \
    --sides 30 --max-lines 900000
}

if want_view detector-core; then
  render_detector_core mu2e-detector-core \
    --view '0.60,1,0.45' --up '1,-0.40,0' --depth-fade 0.76
fi

if want_view detector-axial; then
  render_detector_core mu2e-detector-axial \
    --view '0,0,1' --up '0,1,0' --depth-fade 0.55
fi

printf '%s\n' "$inventory_dir/mu2e-v7.4.1.tsv"
printf '%s\n' "${generated_views[@]}"
