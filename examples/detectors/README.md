# Detector geometry suite

Render the eight pinned detector and beamline models:

```sh
./examples/detectors/render.sh
```

Pass one or more selectors to render only those models:

```sh
./examples/detectors/render.sh trex
./examples/detectors/render.sh lbnf rich hpge
./examples/detectors/render.sh l200 bigtes neutron-camera bdsim
```

The accepted selectors are `trex`, `lbnf`, `l200`, `bigtes`,
`neutron-camera`, `rich`, `bdsim`, and `hpge`. With no selector, the script
renders all eight.

The script downloads only the exact GDML closure listed in
[`SOURCES.tsv`](SOURCES.tsv), at immutable upstream revisions, and verifies
every SHA-256 checksum before parsing. It does not clone a repository or vendor
the source geometry here. Downloads, compatibility copies, inventories, logs,
and generated views stay under ignored `out/detectors/` directories. Each
canonical view is written as SVG plus a 1000-pixel-wide PNG and a 96-dpi PDF.

## Source closures

Seven models are represented by one self-contained GDML file. BigTES is the
only modular closure: its top-level file references five sibling GDML files,
so the manifest contains those six files and nothing else.

| Selector | Geometry | Downloaded files | Placements | Logical volumes | Materials |
| --- | --- | ---: | ---: | ---: | ---: |
| `trex` | TRex with Miniball | 1 | 2,519 | 2,271 | 7 |
| `lbnf` | LBNF target, horns, decay line, and absorber | 1 | 1,342 | 889 | 28 |
| `l200` | L200/GERDA cryostat and detector strings | 1 | 113 | 58 | 19 |
| `bigtes` | BigTES cryostat and sensor package | 6 | 11 | 10 | 8 |
| `neutron-camera` | EJ-276D neutron camera | 1 | 22 | 23 | 5 |
| `rich` | CBM RICH v13c | 1 | 1,348 | 71 | 6 |
| `bdsim` | BDSIM single-pass beamline | 1 | 5,156 | 528 | 10 |
| `hpge` | HPGe detector and shielding | 1 | 13 | 13 | 2 |

The counts above are from `g4fig --list` on the pinned files (or the
geometry-equivalent compatibility copy described below). A fresh inventory for
each selected model is written to `out/detectors/inventory/` on every run.

## Render-only compatibility copies

The downloaded files remain byte-for-byte unchanged. Two inputs need narrowly
guarded fixes for Geant4's GDML reader; the script writes the results under
`out/detectors/render/` and verifies their expected checksums:

- LBNF declares three radial-division widths with `unit="mm"`. For a `kRho`
  division Geant4 expects an angular unit, so only those three attributes are
  changed to `unit="rad"`.
- RICH places its XML declaration after a comment and uses the one-character
  expression variable `T`. The declaration is moved to byte one, and that one
  definition plus its four uses are renamed to `pmt_distance`.

No geometric value, placement, material, or upstream source file is changed.

## Licences and diagnostics

TRex follows nptool's GPL-2.0 terms, CBM RICH follows cbmroot's LGPL-2.1
terms, and BDSIM is GPL-3.0. No repository licence was found for the pinned
LBNF, L200, BigTES, neutron-camera, or HPGe sources; treat those five as
reference/view-only unless their authors grant further rights. The per-file
manifest keeps this caveat beside every affected URL.

Geant4 treats BigTES's volume-level `rotation` element as an unknown extension,
and reports duplicate-material and degenerate-facet warnings while reading the
CAD-converted HPGe file. These upstream diagnostics are preserved in
`out/detectors/logs/`; the downloaded inputs are not rewritten to silence them.
