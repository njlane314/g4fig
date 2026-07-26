# HIRAX spacecraft

Render ten views of the HIRAX X-ray-interferometer spacecraft model:

```sh
./examples/hirax/render.sh
```

The script downloads only the pinned `geometry_hirax.gdml` file, verifies its
SHA-256 checksum, and writes SVG output under `out/hirax/`. When
`rsvg-convert` is available it also writes matching PDF and PNG files.

The upstream file is self-contained apart from a stale local GDML schema hint;
`g4fig` deliberately loads GDML without schema validation. Source provenance is
recorded in [`gallery/SOURCES.tsv`](../../gallery/SOURCES.tsv).
