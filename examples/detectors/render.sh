#!/usr/bin/env bash
set -euo pipefail

example_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$example_dir/../.." && pwd)"
out_dir="$repo_root/out/detectors"
source_dir="$out_dir/source"
render_dir="$out_dir/render"
view_dir="$out_dir/views"
log_dir="$out_dir/logs"
inventory_dir="$out_dir/inventory"
manifest="$example_dir/SOURCES.tsv"

requested_models=("$@")
generated_views=()
if [ "${#requested_models[@]}" -eq 0 ]; then
  requested_models=(trex lbnf l200 bigtes neutron-camera rich bdsim hpge)
fi

for requested_model in "${requested_models[@]}"; do
  case "$requested_model" in
    trex|lbnf|l200|bigtes|neutron-camera|rich|bdsim|hpge) ;;
    *)
      printf 'unknown model: %s\n' "$requested_model" >&2
      printf 'choose from: trex lbnf l200 bigtes neutron-camera rich bdsim hpge\n' >&2
      exit 2
      ;;
  esac
done

want_model() {
  local candidate="$1"
  local requested_model
  for requested_model in "${requested_models[@]}"; do
    [ "$requested_model" = "$candidate" ] && return 0
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

command -v curl >/dev/null 2>&1 || {
  printf 'curl is required to download the pinned GDML files\n' >&2
  exit 1
}
command -v rsvg-convert >/dev/null 2>&1 || {
  printf 'rsvg-convert is required to create the PDF and PNG views\n' >&2
  exit 1
}

mkdir -p "$source_dir" "$render_dir" "$view_dir" "$log_dir" "$inventory_dir"

temporary=""
cleanup() {
  if [ -n "${temporary:-}" ] && [ -f "$temporary" ]; then
    rm -f "$temporary"
  fi
}
trap cleanup EXIT

while IFS=$'\t' read -r model repository revision upstream_path pinned_url expected_sha256 licence; do
  [ "$model" = model ] && continue
  want_model "$model" || continue

  destination="$source_dir/$model/$upstream_path"
  mkdir -p "$(dirname "$destination")"
  if [ ! -f "$destination" ] || [ "$(sha256 "$destination")" != "$expected_sha256" ]; then
    temporary="$(mktemp "$destination.XXXXXX")"
    curl --fail --location --retry 3 "$pinned_url" --output "$temporary"
    actual_sha256="$(sha256 "$temporary")"
    if [ "$actual_sha256" != "$expected_sha256" ]; then
      printf '%s: checksum mismatch\nexpected: %s\nactual:   %s\n' \
        "$upstream_path" "$expected_sha256" "$actual_sha256" >&2
      exit 1
    fi
    mv "$temporary" "$destination"
    temporary=""
  fi
done < "$manifest"

prepare_lbnf() {
  local input="$source_dir/lbnf/detectors/SBN/v1/LBNF/g4lbnf.gdml"
  local output_dir="$render_dir/lbnf"
  local output="$output_dir/g4lbnf.gdml"
  local expected_render_sha256="1c1bc9e774a24dc9d8818139236fcda8afc764f59858982b841002386fcf54e1"

  command -v perl >/dev/null 2>&1 || {
    printf 'perl is required to prepare the LBNF rendering copy\n' >&2
    exit 1
  }
  if [ "$(grep -c '<divisionvol axis="kRho".* unit="mm"' "$input")" -ne 3 ]; then
    printf 'LBNF compatibility guard failed: expected three kRho divisions in mm\n' >&2
    exit 1
  fi

  mkdir -p "$output_dir"
  temporary="$(mktemp "$output.XXXXXX")"
  perl -0pe \
    's/(<divisionvol axis="kRho"[^>]*?) unit="mm"/$1 unit="rad"/g' \
    "$input" > "$temporary"
  if [ "$(sha256 "$temporary")" != "$expected_render_sha256" ]; then
    printf 'LBNF compatibility edit produced an unexpected checksum\n' >&2
    exit 1
  fi
  mv "$temporary" "$output"
  temporary=""
}

prepare_rich() {
  local input="$source_dir/rich/geometry/rich/rich_v13c.gdml"
  local output_dir="$render_dir/rich"
  local output="$output_dir/rich_v13c.gdml"
  local expected_render_sha256="878812f700e6b696b95be0afda7634918b21ffbd3157291b2dee9223b372b30c"

  command -v perl >/dev/null 2>&1 || {
    printf 'perl is required to prepare the RICH rendering copy\n' >&2
    exit 1
  }
  if [ "$(grep -c '<variable name="T" value="1500"/>' "$input")" -ne 1 ] ||
     [ "$(grep -c '\*T' "$input")" -ne 4 ]; then
    printf 'RICH compatibility guard failed: expected one T definition and four uses\n' >&2
    exit 1
  fi

  mkdir -p "$output_dir"
  temporary="$(mktemp "$output.XXXXXX")"
  perl -0pe '
    s/\A(<!--  Full version\. Contains mainframe, small frame and mirror supports\. -->)\r\n\r\n(<\?xml version="1\.0" encoding="UTF-8"\?>)\r\n/$2\n$1\n/;
    s/<variable name="T" value="1500"\/>/<variable name="pmt_distance" value="1500"\/>/;
    s/\*T/\*pmt_distance/g;
  ' "$input" > "$temporary"
  if [ "$(sha256 "$temporary")" != "$expected_render_sha256" ]; then
    printf 'RICH compatibility edit produced an unexpected checksum\n' >&2
    exit 1
  fi
  mv "$temporary" "$output"
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

inventory_model() {
  local model="$1"
  local work_dir="$2"
  local input="$3"
  if ! (
    cd "$work_dir"
    "$repo_root/bin/g4fig" --list "$input"
  ) > "$inventory_dir/$model.tsv" 2> "$log_dir/$model-list.log"; then
    printf '%s: inventory failed; see %s\n' "$model" "$log_dir/$model-list.log" >&2
    tail -n 20 "$log_dir/$model-list.log" >&2
    return 1
  fi
}

render_view() {
  local view_name="$1"
  local work_dir="$2"
  local input="$3"
  shift 3

  temporary="$(mktemp "$view_dir/$view_name.svg.XXXXXX")"
  if ! (
    cd "$work_dir"
    "$repo_root/bin/g4fig" "$@" "$input"
  ) > "$temporary" 2> "$log_dir/$view_name.log"; then
    printf '%s: render failed; see %s\n' "$view_name" "$log_dir/$view_name.log" >&2
    tail -n 20 "$log_dir/$view_name.log" >&2
    return 1
  fi
  mv "$temporary" "$view_dir/$view_name.svg"
  temporary=""
  convert_view "$view_name"
  generated_views+=("$view_dir/$view_name.svg")
}

render_trex() {
  local work="$source_dir/trex/NPSimulation/Detectors/TRex"
  local input="TRex_Miniball.gdml"
  local base=(
    --size 1400x900 --fade 0.105 --depth-fade 0.62
    --line-width 1.05 --padding 0.06 --sides 32
    --style 'Aluminum|Aluminium=#ff5a1f'
    --style 'pcb=#10b7d5'
    --style 'silicon=#22df55'
    --style 'Mylar=#d82bd6'
    --style 'HPGermanium=#2452ff'
  )

  inventory_model trex "$work" "$input"
  render_view trex-miniball-oblique "$work" "$input" \
    "${base[@]}" --exclude 'Vacuum_7$' --view '1,0.65,0.42' --up '0,0,1'
  render_view trex-miniball-axial "$work" "$input" \
    "${base[@]}" --exclude 'Vacuum_7$' --view '0,0,1' --up '0,1,0'
  render_view trex-miniball-cutaway "$work" "$input" \
    "${base[@]}" --exclude 'Vacuum_7$|cluster[4-7]_' \
    --view '1,0.62,0.38' --up '0,0,1'
  render_view trex-active-detectors "$work" "$input" \
    "${base[@]}" --include 'HPGermanium|silicon|target' \
    --style 'target=#ff5a1f' --view '1,0.58,0.34' --up '0,0,1'
}

render_lbnf() {
  local work="$render_dir/lbnf"
  local input="g4lbnf.gdml"
  local base=(
    --size 1400x900 --fade 0.105 --depth-fade 0.62
    --line-width 1.05 --padding 0.06 --sides 32
  )
  local engineering_styles=(
    --style 'Air$|Air[0-9A-Za-z_]+$|CONC$|Concrete$=#6fc6d1'
    --style 'MIX1$|WATR$|Water$=#18bad5'
    --style 'DecayPipe=#d62bd6'
    --style 'HadronAbsorber=#23d957'
    --style 'Target|tCore|Bafflet=#2452ff'
    --style 'Horn=#ff4b2b'
  )

  prepare_lbnf
  inventory_model lbnf "$work" "$input"
  render_view lbnf-engineering-longitudinal "$work" "$input" \
    "${base[@]}" "${engineering_styles[@]}" \
    --view '1,0.24,-0.035' --up '0,1,0'
  render_view lbnf-horn-train "$work" "$input" \
    "${base[@]}" --view '1,0.26,-0.07' --up '0,1,0' \
    --include 'Horn|Target|Bafflet' --exclude 'Air$|Air[0-9A-Za-z_]+$' \
    --style 'Water$|WATR$=#18bad5' --style 'Target|tCore|Bafflet=#2452ff' \
    --style 'Horn=#ff4b2b'
  render_view lbnf-horn-axial "$work" "$input" \
    "${base[@]}" --view '0,0,1' --up '0,1,0' --include 'Horn' \
    --exclude 'Air$|Water$|WATR$' --style 'Horn=#ff4b2b' \
    --style 'Aluminum=#ff8a25'
  render_view lbnf-horn3-detail "$work" "$input" \
    --size 1400x900 --fade 0.105 --depth-fade 0.62 --line-width 1.05 \
    --padding 0.075 --sides 40 --view '1,0.34,-0.10' --up '0,1,0' \
    --include 'LBNFConceptHornC' --style 'Horn=#ff4b2b' \
    --style 'Water$|WATR$=#18bad5' --style 'Alumina=#2452ff'
  render_view lbnf-absorber-cutaway "$work" "$input" \
    "${base[@]}" --view '1,0.35,-0.12' --up '0,1,0' \
    --include 'HadronAbsorber' --exclude 'Air$|CONC$|Concrete$' \
    --style 'HadronAbsorber=#23d957' --style 'MIX1$=#ff5a1f' \
    --style 'Water$|WATR$=#18bad5' --style 'Aluminum=#ff8a25'
}

render_l200() {
  local work="$source_dir/l200/src"
  local input="l200_gerdaSetup.gdml"
  local styles=(
    --style 'metal_steel$=#17324d'
    --style 'G4_WATER$=#36a8ff'
    --style 'LiquidArgon$=#27d3ef'
    --style 'metal_copper$=#ff9d00'
    --style 'EnrichedGermanium[^[:space:]]*$=#ff3b30'
    --style 'pen$=#8e3bff'
    --style 'tpb_on_nylon$=#2ee65f'
    --style 'tpb_on_tetratex$=#00c853'
    --style 'tetratex$=#5bf076'
    --style 'Gadolinium.*$=#ee2bd1'
    --style 'polyethylene$=#ffd400'
  )
  local active='EnrichedGermanium[^[:space:]]*$|pen$|metal_copper$|tpb_on_nylon$|Gadolinium.*$|polyethylene$|string_gerda'
  local base=(
    --size 1400x900 --fade 0.095 --depth-fade 0.72
    --line-width 1.15 --padding 0.075
  )

  inventory_model l200 "$work" "$input"
  render_view l200-hero-oblique "$work" "$input" \
    "${base[@]}" "${styles[@]}" --view '1,0.58,0.32' --up '0,0,1'
  render_view l200-vertical-section "$work" "$input" \
    "${base[@]}" "${styles[@]}" --view '1,0.22,0.06' --up '0,0,1' \
    --include "$active" --exclude 'wlsr_|top_plate'
  render_view l200-array-oblique "$work" "$input" \
    "${base[@]}" "${styles[@]}" --view '0.86,-0.62,0.28' --up '0,0,1' \
    --include "$active" --exclude 'wlsr_|top_plate'
  render_view l200-array-axial "$work" "$input" \
    "${base[@]}" "${styles[@]}" --view '0,0,1' --up '0,1,0' \
    --include "$active" --exclude 'wlsr_|top_plate'
  render_view l200-detector-strings "$work" "$input" \
    "${base[@]}" "${styles[@]}" --view '0.92,-0.48,0.18' --up '0,0,1' \
    --include 'EnrichedGermanium[^[:space:]]*$|pen$|metal_copper$' \
    --exclude 'wlsr_|top_plate'
}

render_bigtes() {
  local work="$source_dir/bigtes"
  local input="geometry/configBigTES.gdml"
  local styles=(
    --style 'Al=#ff5a1f'
    --style 'Cu=#ff9d00'
    --style 'G4_Ni=#13b8a6'
    --style 'SiliconMaterial=#2452ff'
    --style 'siliconOxide=#22df55'
    --style 'siliconNitride=#e833a4'
    --style 'G4_Galactic=#8aa4bf'
  )
  local base=(
    --size 1400x900 --fade 0.095 --depth-fade 0.72
    --line-width 1.15 --padding 0.075
  )

  inventory_model bigtes "$work" "$input"
  render_view bigtes-hero-oblique "$work" "$input" \
    "${base[@]}" "${styles[@]}" --view '1,0.52,-0.24' --up '0,1,0'
  render_view bigtes-cryostat-profile "$work" "$input" \
    "${base[@]}" "${styles[@]}" --view '1,0.03,0.08' --up '0,1,0'
  render_view bigtes-instrument-cutaway "$work" "$input" \
    "${base[@]}" "${styles[@]}" --view '0.86,0.46,-0.31' --up '0,1,0' \
    --include 'Cu$|G4_Ni$|SiliconMaterial$|siliconOxide$|siliconNitride$'
  render_view bigtes-instrument-axial "$work" "$input" \
    "${base[@]}" "${styles[@]}" --view '0,1,0' --up '0,0,1' \
    --include 'Cu$|G4_Ni$|SiliconMaterial$|siliconOxide$|siliconNitride$'
  render_view bigtes-sensor-core "$work" "$input" \
    --size 1400x900 --fade 0.095 --depth-fade 0.42 --line-width 1.45 \
    --padding 0.075 "${styles[@]}" --view '0.86,0.58,-0.34' --up '0,1,0' \
    --include '(^|[[:space:]])Cu$|SiliconMaterial$|siliconOxide$|siliconNitride$'
}

render_neutron_camera() {
  local work="$source_dir/neutron-camera"
  local input="NeutronCameraExport_EJ-276D_ORB1B_cathodeclub_neutron-worldVOL.gdml"
  local styles=(
    --style 'G4_STAINLESS-STEEL$=#1f4f78'
    --style 'Vacuum$=#22b8cf'
    --style 'EJ-276D$=#ff4d00'
    --style 'Polymat$=#7c3aed'
  )
  local base=(
    --size 1400x900 --fade 0.095 --depth-fade 0.72
    --line-width 1.15 --padding 0.075
  )

  inventory_model neutron-camera "$work" "$input"
  render_view neutron-camera-hero-oblique "$work" "$input" \
    "${base[@]}" "${styles[@]}" --view '1,0.58,-0.34' --up '0,0,1'
  render_view neutron-camera-detector-oblique "$work" "$input" \
    "${base[@]}" "${styles[@]}" --view '0.88,-0.58,0.38' --up '0,0,1' \
    --include 'EJ-276D$|Polymat$'
  render_view neutron-camera-front "$work" "$input" \
    "${base[@]}" "${styles[@]}" --view '0,1,0' --up '0,0,1' \
    --include 'EJ-276D$|Polymat$'
  render_view neutron-camera-side "$work" "$input" \
    "${base[@]}" "${styles[@]}" --view '1,0,0' --up '0,0,1' \
    --include 'EJ-276D$|Polymat$|G4_STAINLESS-STEEL$'
}

render_rich() {
  local work="$render_dir/rich"
  local input="rich_v13c.gdml"
  local styles=(
    --style 'aluminium=#ff4d30'
    --style 'RICHglass=#244cff'
    --style 'CsI=#e72fa8'
  )
  local base=(
    --size 1400x900 --up '0,1,0' --exclude 'RICHgas_CO2_dis$|vacuum$'
    --fade 0.09 --depth-fade 0.68 --line-width 0.82 --padding 0.07 --sides 32
  )

  prepare_rich
  inventory_model rich "$work" "$input"
  render_view rich-hero-oblique "$work" "$input" \
    "${base[@]}" "${styles[@]}" --view '1,0.65,0.4'
  render_view rich-axial "$work" "$input" \
    --size 1400x900 --view '0,0,1' --up '0,1,0' \
    --exclude 'RICHgas_CO2_dis$|vacuum$' "${styles[@]}" \
    --fade 0.09 --depth-fade 0.52 --line-width 0.82 --padding 0.07 --sides 32
  render_view rich-open-frame "$work" "$input" \
    --size 1400x900 --view '1,0.68,0.42' --up '0,1,0' \
    --exclude 'RICHgas_CO2_dis$|vacuum$|RICH_covering' "${styles[@]}" \
    --fade 0.09 --depth-fade 0.62 --line-width 0.82 --padding 0.07 --sides 32
  render_view rich-optics "$work" "$input" \
    --size 1400x900 --view '1,0.62,0.42' --up '0,1,0' \
    --include 'RICH_mirror_[123]|rich1d|RICH_main_frame' "${styles[@]}" \
    --fade 0.09 --depth-fade 0.58 --line-width 0.92 --padding 0.09 --sides 36
}

render_bdsim() {
  local work="$source_dir/bdsim/examples/model-model/bdsim/singlepass"
  local input="bmm-sp-geometry.gdml"
  local styles=(
    --style 'G4_Cu=#ff4d30'
    --style 'G4_Fe=#244cff'
    --style 'stainlesssteel=#22d968'
    --style 'concrete=#24cbe2'
    --style 'soil=#b77535'
    --style 'G4_W=#e72fa8'
    --style 'G4_C=#9842dc'
  )
  local base=(
    --size 1400x900 --exclude 'vacuum$|G4_Galactic$|G4_AIR$'
    --fade 0.09 --depth-fade 0.76 --line-width 0.48 --padding 0.065
    --sides 12 --max-lines 2000000
  )

  inventory_model bdsim "$work" "$input"
  render_view bdsim-downbeam "$work" "$input" \
    "${base[@]}" "${styles[@]}" --view '0.22,0.14,1' --up '0,1,0'
  render_view bdsim-axial "$work" "$input" \
    --size 1400x900 --view '0,0,1' --up '0,1,0' \
    --exclude 'vacuum$|G4_Galactic$|G4_AIR$' "${styles[@]}" \
    --fade 0.09 --depth-fade 0.48 --line-width 0.56 --padding 0.065 \
    --sides 12 --max-lines 2000000
  render_view bdsim-magnet-module "$work" "$input" \
    --size 1400x900 --view '1,0.72,0.48' --up '0,1,0' \
    --include 'DIPOLE_even_ang_0_pv' --exclude 'vacuum$|G4_Galactic$|G4_AIR$' \
    --style 'G4_Cu=#ff4d30' --style 'G4_Fe=#244cff' \
    --style 'stainlesssteel=#22d968' --fade 0.09 --depth-fade 0.58 \
    --line-width 0.84 --padding 0.09 --sides 24 --max-lines 2000000
}

render_hpge() {
  local work="$source_dir/hpge"
  local input="HPGe-source15cm.gdml"
  local styles=(
    --style 'HPGeSensitive=#244cff'
    --style 'DeadLayer=#e833a4'
    --style 'LeadShielding=#ff4b2f'
    --style 'copperShielding|copperFinger=#ff9a24'
    --style 'plasticShielding=#29dd62'
    --style 'sampleHolder=#20cce0'
    --style 'topLayer=#9b45e6'
    --style 'Cup|shell=#465568'
  )
  local base=(
    --size 1400x900 --up '0,0,1' --fade 0.09 --depth-fade 0.64
    --line-width 0.78 --padding 0.07
  )

  inventory_model hpge "$work" "$input"
  render_view hpge-hero-oblique "$work" "$input" \
    "${base[@]}" "${styles[@]}" --view '1,0.66,0.45'
  render_view hpge-axial "$work" "$input" \
    --size 1400x900 --view '0,0,1' --up '0,1,0' "${styles[@]}" \
    --fade 0.09 --depth-fade 0.46 --line-width 0.78 --padding 0.07
  render_view hpge-cutaway "$work" "$input" \
    --size 1400x900 --view '1,0.62,0.43' --up '0,0,1' \
    --exclude 'LeadShielding|plasticShielding' "${styles[@]}" \
    --fade 0.09 --depth-fade 0.56 --line-width 0.86 --padding 0.09
  render_view hpge-detector-core "$work" "$input" \
    --size 1400x900 --view '1,0.58,0.40' --up '0,0,1' \
    --include 'innerDeadLayer|outterDeadLayer|HPGeSensitive|copperFinger|topLayer|Cup|sampleHolder' \
    "${styles[@]}" --fade 0.09 --depth-fade 0.48 --line-width 0.92 \
    --padding 0.11
}

want_model trex && render_trex
want_model lbnf && render_lbnf
want_model l200 && render_l200
want_model bigtes && render_bigtes
want_model neutron-camera && render_neutron_camera
want_model rich && render_rich
want_model bdsim && render_bdsim
want_model hpge && render_hpge

printf '%s\n' "${generated_views[@]}"
