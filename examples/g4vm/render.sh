#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out_dir="$repo_root/out/g4vm"
source_dir="$out_dir/source"
render_dir="$out_dir/render"
view_dir="$out_dir/views"
log_dir="$out_dir/logs"
manifest="$repo_root/examples/g4vm/SOURCES.tsv"
source_base="https://raw.githubusercontent.com/spearhead-he/G4VM/ef99820da246495c3acdd6602f84aff389befe56"
source_rel="out/g4vm/source"
render_rel="out/g4vm/render"
view_rel="out/g4vm/views"
erne_member_sha256="e4c4519ac6e576548748876689098fd433d1f976c6a962ac7c9bdab65e9c679e"

requested_models=("$@")
if [ "${#requested_models[@]}" -eq 0 ]; then
  requested_models=(het ephin ket sixs erne)
fi

for requested_model in "${requested_models[@]}"; do
  case "$requested_model" in
    het|ephin|erne|ket|sixs) ;;
    *)
      printf 'unknown model: %s\n' "$requested_model" >&2
      printf 'choose from: het ephin erne ket sixs\n' >&2
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

mkdir -p "$source_dir" "$render_dir" "$view_dir" "$log_dir"

temporary=""
cleanup() {
  if [ -n "${temporary:-}" ] && [ -f "$temporary" ]; then
    rm -f "$temporary"
  fi
}
trap cleanup EXIT

while IFS=$'\t' read -r manifest_model upstream_path expected_sha256; do
  [ "$manifest_model" = model ] && continue
  want_model "$manifest_model" || continue

  destination="$source_dir/$upstream_path"
  mkdir -p "$(dirname "$destination")"
  if [ ! -f "$destination" ] || [ "$(sha256 "$destination")" != "$expected_sha256" ]; then
    temporary="$(mktemp "$destination.XXXXXX")"
    curl --fail --location --retry 3 \
      "$source_base/$upstream_path" \
      --output "$temporary"
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

if want_model het; then
  command -v xmllint >/dev/null 2>&1 || {
    printf 'xmllint is required to expand the HET entity files\n' >&2
    exit 1
  }
  xmllint --nonet --noent \
    --output "$render_dir/HET-expanded.gdml" \
    "$source_dir/HET/HET.gdml"
  xmllint --nonet --noent \
    --output "$render_dir/HET-shield-expanded.gdml" \
    "$source_dir/HET/HET_shield.gdml"
fi

if want_model erne; then
  command -v unzip >/dev/null 2>&1 || {
    printf 'unzip is required to extract ERNE.gdml\n' >&2
    exit 1
  }
  erne_path="$source_dir/ERNE/ERNE.gdml"
  if [ ! -f "$erne_path" ] || [ "$(sha256 "$erne_path")" != "$erne_member_sha256" ]; then
    temporary="$(mktemp "$source_dir/ERNE/ERNE.gdml.XXXXXX")"
    unzip -p "$source_dir/ERNE/ERNE.zip" ERNE.gdml > "$temporary"
    actual_sha256="$(sha256 "$temporary")"
    if [ "$actual_sha256" != "$erne_member_sha256" ]; then
      printf '%s: checksum mismatch\nexpected: %s\nactual:   %s\n' \
        'ERNE.zip:ERNE.gdml' "$erne_member_sha256" "$actual_sha256" >&2
      exit 1
    fi
    mv "$temporary" "$erne_path"
    temporary=""
  fi
fi

compact_svg_lines() {
  local input="$1"
  local output="$2"
  command -v perl >/dev/null 2>&1 || {
    printf 'perl is required to compact the full ERNE SVG for conversion\n' >&2
    exit 1
  }
  perl -ne '
    sub flush_path {
      if (defined $attrs) {
        print qq{<path d="$path_data" $attrs/>\n};
        undef $attrs;
        $path_data = "";
      }
    }
    if (/^<line x1="([^"]+)" y1="([^"]+)" x2="([^"]+)" y2="([^"]+)" (.+)\/>$/) {
      ($x1, $y1, $x2, $y2, $next_attrs) = ($1, $2, $3, $4, $5);
      flush_path() if defined($attrs) && $next_attrs ne $attrs;
      $attrs = $next_attrs unless defined $attrs;
      $path_data .= "M $x1 $y1 L $x2 $y2 ";
    } else {
      flush_path();
      print;
    }
    END { flush_path(); }
  ' "$input" > "$output"
}

convert_view() {
  local view_name="$1"
  local pdf_dpi="$2"
  if command -v rsvg-convert >/dev/null 2>&1; then
    local conversion_svg="$view_dir/$view_name.svg"
    if [ "$view_name" = erne ]; then
      conversion_svg="$render_dir/$view_name.compact.svg"
      compact_svg_lines "$view_dir/$view_name.svg" "$conversion_svg"
    fi
    rsvg-convert --width 1000 \
      --output "$view_dir/$view_name.png" \
      "$conversion_svg"
    rsvg-convert --dpi-x "$pdf_dpi" --dpi-y "$pdf_dpi" --format pdf \
      --output "$view_dir/$view_name.pdf" \
      "$conversion_svg"
  fi
}

run_render() {
  local view_name="$1"
  local input_path="$2"
  local pdf_dpi="$3"
  shift 3

  if ! (
    cd "$repo_root"
    ./bin/g4fig \
      "$@" \
      -o "$view_rel/$view_name.svg" \
      "$input_path"
  ) 2> "$log_dir/$view_name.log"; then
    printf '%s: render failed; see %s\n' \
      "$view_name" "$log_dir/$view_name.log" >&2
    tail -n 20 "$log_dir/$view_name.log" >&2
    return 1
  fi
  convert_view "$view_name" "$pdf_dpi"
}

render_het() {
  local instrument="$render_rel/HET-expanded.gdml"
  local shield="$render_rel/HET-shield-expanded.gdml"
  local styles=(
    --style 'AluminiumAlloy|Aluminum=#ff5a1f'
    --style 'Silicon=#0057ff'
    --style 'BGO=#e833a4'
    --style 'PTFE|Kapton|polyimide|Al2O3=#ed4141'
    --style 'sp-=#21d94f'
  )

  run_render het-instrument-oblique "$instrument" 72 \
    --size 1050x675 --view '1,0.7,0.45' --up '0,0,1' \
    "${styles[@]}" --label 'Scope_V=Solar Orbiter HET' \
    --fade 0.09 --depth-fade 0.74 --line-width 0.70 --padding 0.065 \
    --aux-edges --max-lines 500000

  run_render het-detector-cutaway "$instrument" 72 \
    --size 1050x675 --view '0.9,0.35,0.5' --up '0,0,1' \
    "${styles[@]}" --label 'HETBmiddle1=HET detector stack' \
    --exclude 'EBox_V|Scope_V|CrystalHolder_V|PTFE_V|PhDiodeC_V' \
    --fade 0.09 --depth-fade 0.74 --line-width 0.70 --padding 0.065 \
    --aux-edges --max-lines 500000

  run_render het-active-stack "$instrument" 72 \
    --size 1050x675 --view '0.85,0.3,0.35' --up '0,0,1' \
    "${styles[@]}" --label 'Crystal_V=BGO crystal' \
    --include 'Silicon|BGO|Kapton|Aluminum' \
    --fade 0.09 --depth-fade 0.66 --line-width 0.78 --padding 0.075 \
    --aux-edges --max-lines 500000

  run_render het "$shield" 72 \
    --size 1050x675 --view '1,0.7,0.45' --up '0,0,1' \
    "${styles[@]}" --label 'Scope_V=Solar Orbiter HET' \
    --fade 0.09 --depth-fade 0.74 --line-width 0.70 --padding 0.065 \
    --max-lines 500000

  run_render het-shield-cutaway "$shield" 72 \
    --size 1050x675 --view '1,0.7,0.45' --up '0,0,1' \
    "${styles[@]}" --label 'Scope_V=HET within shielding' \
    --exclude 'sp-(5|10|15|20|25|30|35|40|45|50|55|60|65|70|75|80)_dp5' \
    --fade 0.09 --depth-fade 0.72 --line-width 0.70 --padding 0.065 \
    --max-lines 500000
}

render_ephin() {
  local instrument="$source_rel/EPHIN/ephin.gdml"
  local soho="$source_rel/EPHIN/ephin_soho_shield.gdml"
  local chandra="$source_rel/EPHIN/ephin_chandra_shield.gdml"
  local instrument_styles=(
    --style 'Aluminum=#ff5a1f'
    --style 'Semiconductor=#0057ff'
    --style 'Scintillator=#21d94f'
    --style 'Kaptonfoil|Titanfoil=#ed4141'
    --style 'Delrin=#e833a4'
  )
  local shield_styles=(
    --style 'Aluminum=#e833a4'
    --style 'Semiconductor=#0057ff'
    --style 'Scintillator=#21d94f'
    --style 'Kaptonfoil|Titanfoil=#ed4141'
    --style 'Delrin=#21d94f'
    --style 'density=#ff5a1f'
  )

  run_render ephin-axial "$instrument" 96 \
    --size 1400x900 --view '0,0,1' --up '0,1,0' \
    "${instrument_styles[@]}" --label 'vd10=EPHIN axial view' \
    --fade 0.09 --depth-fade 0.52 --line-width 0.78 --padding 0.07 \
    --max-lines 500000

  run_render ephin-longitudinal "$instrument" 96 \
    --size 1400x900 --view '1,0.16,0.10' --up '0,0,1' \
    "${instrument_styles[@]}" --label 'vd10=EPHIN longitudinal section' \
    --fade 0.09 --depth-fade 0.50 --line-width 0.82 --padding 0.07 \
    --max-lines 500000

  run_render ephin-active-stack "$instrument" 96 \
    --size 1400x900 --view '1,-1,0.65' --up '0,0,1' \
    --include 'Semiconductor|Scintillator|Kaptonfoil|Titanfoil' \
    --style 'Semiconductor=#0057ff' --style 'Scintillator=#21d94f' \
    --style 'Kaptonfoil|Titanfoil=#ed4141' \
    --label 'vd10=EPHIN active stack' \
    --fade 0.09 --depth-fade 0.44 --line-width 0.88 --padding 0.08 \
    --max-lines 500000

  run_render ephin-soho "$soho" 96 \
    --size 1400x900 --view '1,-1,0.65' --up '0,0,1' \
    "${shield_styles[@]}" --label 'density=SOHO shielding' \
    --fade 0.09 --depth-fade 0.72 --line-width 0.56 --padding 0.07 \
    --max-lines 500000

  run_render ephin-chandra "$chandra" 96 \
    --size 1400x900 --view '1,-1,0.65' --up '0,0,1' \
    "${shield_styles[@]}" --label 'density=Chandra shielding' \
    --fade 0.09 --depth-fade 0.72 --line-width 0.56 --padding 0.07 \
    --max-lines 500000
}

render_ket() {
  local input="$source_rel/KET/ket.gdml"
  local styles=(
    --style 'Aluminum=#ff5a1f'
    --style 'Delrin=#253746'
    --style 'NE104=#0057ff'
    --style 'Silicon=#e833a4'
    --style 'Kapton=#ed4141'
    --style 'Quartz|Aerogel|PBF2=#21d94f'
  )

  run_render ket "$input" 96 \
    --size 1400x900 --view '1,0.45,0.28' --up '0,1,0' \
    "${styles[@]}" --label 'S2box_V=SOHO KET' \
    --fade 0.09 --depth-fade 0.68 --line-width 0.82 --padding 0.07 \
    --sides 36 --max-lines 500000

  run_render ket-axial "$input" 96 \
    --size 1400x900 --view '0,0,1' --up '0,1,0' \
    "${styles[@]}" --label 'S2box_V=KET axial view' \
    --fade 0.09 --depth-fade 0.68 --line-width 0.82 --padding 0.07 \
    --sides 36 --max-lines 500000
}

render_sixs() {
  local input="$source_rel/SIXS/SIXS_v3.gdml"
  local styles=(
    --style 'ALUMINUM=#ff5a1f'
    --style 'SILICON=#0057ff'
    --style 'TUNGSTEN=#253746'
    --style 'COPPER=#e833a4'
    --style 'Al2O3=#21d94f'
    --style 'KAPTON=#ed4141'
    --style 'BERYLLIUM=#00a7c4'
    --style 'CsI=#f2b705'
  )

  run_render sixs "$input" 96 \
    --size 1400x900 --view '1,0.65,0.45' --up '0,0,1' \
    "${styles[@]}" --label 'CsI=BepiColombo SIXS-P' \
    --fade 0.09 --depth-fade 0.74 --line-width 0.65 --padding 0.07 \
    --max-lines 500000

  run_render sixs-axial "$input" 96 \
    --size 1400x900 --view '0,1,0' --up '0,0,1' \
    "${styles[@]}" --label 'CsI=SIXS-P axial view' \
    --fade 0.09 --depth-fade 0.72 --line-width 0.65 --padding 0.07 \
    --max-lines 500000

  run_render sixs-detector-core "$input" 96 \
    --size 1400x900 --view '1,0.65,0.45' --up '0,0,1' \
    --include 'SILICON|CsI|TUNGSTEN|Al2O3|KAPTON|BERYLLIUM' \
    --style 'SILICON=#0057ff' --style 'TUNGSTEN=#253746' \
    --style 'Al2O3=#21d94f' --style 'KAPTON=#ed4141' \
    --style 'BERYLLIUM=#00a7c4' --style 'CsI=#f2b705' \
    --label 'CsI=SIXS-P detector core' \
    --fade 0.09 --depth-fade 0.58 --line-width 0.76 --padding 0.09 \
    --max-lines 500000

  run_render sixs-silicon-array "$input" 96 \
    --size 1400x900 --view '1,0.65,0.45' --up '0,0,1' \
    --include 'SILICON|CsI' \
    --style 'SILICON=#0057ff' --style 'CsI=#ff5a1f' \
    --label 'CsI=SIXS-P silicon detector array' \
    --fade 0.09 --depth-fade 0.45 --line-width 0.92 --padding 0.12 \
    --max-lines 500000
}

render_erne() {
  local input="$source_rel/ERNE/ERNE.gdml"
  local styles=(
    --style 'ALUMINUM=#ff5a1f'
    --style 'SILICON=#0057ff'
    --style 'FR-4|Resin4PCB=#21d94f'
    --style 'ALUMINUM_OXIDE=#ed4141'
    --style 'STAINLESS|BRONZE=#253746'
    --style 'BGO|CsI=#e833a4'
    --style 'PTFE|PEEK|MYLAR|KAPTON|NYLON|RUBBER=#00a7c4'
  )

  run_render erne "$input" 96 \
    --size 1400x900 --view '1,0.65,0.42' --up '0,0,1' \
    "${styles[@]}" --label 'Al_BOX_0103_v8_lv=SOHO ERNE' \
    --fade 0.09 --depth-fade 0.78 --line-width 0.48 --padding 0.07 \
    --max-lines 1500000

  run_render erne-hed "$input" 96 \
    --size 1400x900 --view '1,-0.55,0.38' --up '0,0,1' \
    --include 'HED' "${styles[@]}" \
    --label 'BGO_HED=ERNE high-energy detector' \
    --fade 0.09 --depth-fade 0.68 --line-width 0.62 --padding 0.09 \
    --max-lines 500000

  run_render erne-led "$input" 96 \
    --size 1400x900 --view '1,0.62,0.40' --up '0,0,1' \
    --include 'LED' --exclude 'ALUMINUM' \
    --style 'SILICON=#0057ff' --style 'FR-4|Resin4PCB=#21d94f' \
    --style 'ALUMINUM_OXIDE=#ed4141' --style 'STAINLESS|BRONZE=#253746' \
    --style 'PTFE|PEEK|MYLAR|KAPTON|NYLON|RUBBER=#00a7c4' \
    --label 'Si_LED_D1_Active__1__lv=ERNE low-energy detector' \
    --fade 0.09 --depth-fade 0.60 --line-width 0.70 --padding 0.10 \
    --max-lines 500000
}

want_model het && render_het
want_model ephin && render_ephin
want_model ket && render_ket
want_model sixs && render_sixs
want_model erne && render_erne

printf '%s\n' "$view_dir"/*.svg
