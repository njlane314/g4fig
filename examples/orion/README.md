# Orion spacecraft

This example renders the partial, simplified Orion spacecraft geometry supplied
with Geant4's `gorad` advanced example.

```sh
./examples/orion/render.sh
```

The script downloads the official 21 MB GDML file on first use, verifies its
SHA-256 digest, and writes:

```text
out/orion/orion.gdml
out/orion/orion.svg
out/orion/orion.png   # when rsvg-convert is installed
```

The source contains two aluminium tessellated placements with about 53,700
facets. The rendering uses a three-quarter orthographic view, stronger depth
fading, a dark accent for the smaller mesh, and a paper halo behind the label.
No geometry is rescaled or simplified.

Sources:

- [Geant4 `gorad` example](https://geant4.web.cern.ch/docs/advanced_examples_doc/example_gorad.html)
- [Orion GDML](https://geant4-data.web.cern.ch/datasets/examples/advanced/gorad/orion.gdml)
