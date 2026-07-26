# CUSP CubeSat

Render twelve views of the CUSP CubeSat Compton-polarimeter mass model:

```sh
./examples/cusp/render.sh
```

The script downloads only the six files in the upstream `gdml-mass-model`
directory, pins and verifies every checksum, and writes SVG output under
`out/cusp/views/`. When `rsvg-convert` is available it also writes matching PDF
and PNG files.

The upstream `materials.xml` is intentionally empty because the application
defines `Al10`, `FR4`, and `GAGG` in C++ before reading GDML. The example keeps
the six downloads unchanged and creates a separate render copy using the
source-faithful definitions in [`materials.xml`](materials.xml). Source
provenance is recorded in
[`gallery/SOURCES.tsv`](../../gallery/SOURCES.tsv).

The geometry and material construction are pinned to
[`g4cusp-rs` commit `041373e`](https://github.com/giovixo/g4cusp-rs/tree/041373e2b7c592455c21ff170019b61396bc53e0/gdml-mass-model)
under its [MIT licence](https://github.com/giovixo/g4cusp-rs/blob/041373e2b7c592455c21ff170019b61396bc53e0/LICENSE).
