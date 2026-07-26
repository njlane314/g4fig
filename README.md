# g4fig

`g4fig` turns Geant4 GDML geometry into quiet, publication-ready SVG.
It is a batch filter rather than an interactive event display: diagnostics go to
standard error and SVG goes to standard output.

```sh
g4fig detector.gdml > detector.svg
g4fig --view 1,0.25,-0.12 --exclude 'rock|world' detector.gdml > beamline.svg
g4fig --label 'target=Graphite target' detector.gdml > labelled.svg
```

The default rendering is a vivid orange wireframe on white paper, with depth
fading and a soft fade at the canvas edge. Labels have feathered white halos so
geometry recedes behind the text without an opaque callout box.

## Gallery

[![Orion spacecraft](gallery/previews/orion.png)](gallery/orion.pdf)

[Orion spacecraft (PDF)](gallery/orion.pdf)

[![Orion spacecraft, axial view](gallery/previews/orion-axial.png)](gallery/orion-axial.pdf)

[Orion spacecraft — axial view (PDF)](gallery/orion-axial.pdf)

[![AGATA spherical honeycomb](gallery/previews/agata-honeycomb.png)](gallery/agata-honeycomb.pdf)

[AGATA spherical honeycomb (PDF)](gallery/agata-honeycomb.pdf)

[![AGATA spherical honeycomb, oblique view](gallery/previews/agata-honeycomb-oblique.png)](gallery/agata-honeycomb-oblique.pdf)

[AGATA spherical honeycomb — oblique view (PDF)](gallery/agata-honeycomb-oblique.pdf)

[![KEK ATF2 final-focus beamline](gallery/previews/atf2.png)](gallery/atf2.pdf)

[KEK ATF2 final-focus beamline (PDF)](gallery/atf2.pdf)

[![KEK ATF2 down-beam final-focus region](gallery/previews/atf2-downbeam.png)](gallery/atf2-downbeam.pdf)

[KEK ATF2 — down-beam final-focus region (PDF)](gallery/atf2-downbeam.pdf)

## Commands

```text
g4fig [options] FILE.gdml

  -o FILE                  write SVG to FILE instead of stdout
  --list                   list placed volumes as TSV instead of rendering
  --size WIDTHxHEIGHT      canvas size (default: 1200x675)
  --view X,Y,Z             direction from the scene toward the camera
  --up X,Y,Z               approximate screen-up direction
  --include REGEX          keep matching volume paths, names, or materials
  --exclude REGEX          omit matching volume paths, names, or materials
  --style REGEX=COLOUR     colour matching volumes; may be repeated
  --label REGEX=TEXT       label the centre of matching geometry; repeatable
  --tracks FILE            overlay `x1 y1 z1 x2 y2 z2 [class]` rows
  --track-scale NUMBER     multiply track coordinates by NUMBER
  --fade FRACTION          canvas-edge fade width (default: 0.07)
  --depth-fade STRENGTH    distant-line fade from 0 to 1 (default: 0.65)
  --line-width NUMBER      geometry line width (default: 0.85)
  --padding FRACTION       fitted-geometry margin (default: 0.055)
  --sides NUMBER           curved-solid tessellation (default: 24)
  --max-lines NUMBER       geometry-line safety limit (default: 1000000)
  --show-world             include the top-level world solid
  --aux-edges              include normally hidden tessellation edges
```

Patterns are POSIX extended regular expressions. A style uses any SVG colour,
for example `--style 'target=#253746' --style 'horn=#e66b43'`. Track classes
have built-in high-contrast particle colours (`proton`, `pi+`, `pi-`, `kaon+`,
`kaon-`, `mu+`, and `mu-`); unknown classes are dark blue.

To inspect a file before deciding what to draw:

```sh
g4fig --list detector.gdml | column -ts $'\t' | less -S
```

## Build

With a GDML-enabled Geant4 installation:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
cmake --install build --prefix ~/.local
```

Geant4 11.4 and C++17 are the supported baseline. No Geant4 visual driver,
window system, ROOT installation, or physics data set is needed.

For a self-contained Docker build, use the wrapper from a directory containing
the GDML file:

```sh
/path/to/g4fig/bin/g4fig detector.gdml > detector.svg
```

It builds the pinned `g4fig:local` image on first use and mounts only the
current directory at `/work`.

## Example: Orion spacecraft

Render the partial, simplified Orion model distributed with Geant4's `gorad`
advanced example:

```sh
./examples/orion/render.sh
```

This downloads and verifies the upstream GDML, then writes a labelled SVG and,
when `rsvg-convert` is available, a PNG under `out/orion/`. See
[`examples/orion/`](examples/orion/) for the exact camera and styling choices.

## Example: HIRAX spacecraft

Render ten whole-spacecraft, orthographic, axial, and instrument-detail views:

```sh
./examples/hirax/render.sh
```

The script downloads and verifies only the standalone HIRAX GDML, then writes
SVG and, when `rsvg-convert` is available, matching PDF and PNG files under
`out/hirax/`. See the [stacked HIRAX gallery](gallery/hirax-views.md).

## Track input

Track rows are deliberately simple and pipe-friendly:

```text
# x1 y1 z1 x2 y2 z2 class
0 0 -600  0 0 -300  proton
0 0 -300  90 30 700 pi+
```

Coordinates are interpreted in Geant4's internal length unit (mm). Use
`--track-scale 1000` for metre-valued data. Preparing transport output is kept
outside this renderer; `awk`, a simulation-specific exporter, or another event
reader can all produce the same seven-column stream.

The track stream need not become an intermediate file:

```sh
awk '!/^#/ {print $7,$8,$9,$10,$11,$12,$4}' transport.dat |
  g4fig --tracks /dev/stdin --track-scale 1000 detector.gdml > event.svg
```
