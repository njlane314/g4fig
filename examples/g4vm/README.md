# G4VM flight instruments

Render the complete 19-view HET, EPHIN, ERNE, KET, and SIXS suite:

```sh
./examples/g4vm/render.sh
```

Pass one or more selectors to render only those instruments:

```sh
./examples/g4vm/render.sh het
./examples/g4vm/render.sh ephin
./examples/g4vm/render.sh erne
./examples/g4vm/render.sh ket
./examples/g4vm/render.sh sixs
```

In usage notation, the command is
`./examples/g4vm/render.sh [het|ephin|erne|ket|sixs ...]`; with no selector it
renders all five instruments.

The five families come from
[`spearhead-he/G4VM`](https://github.com/spearhead-he/G4VM) under BSD-3-Clause.
The script makes 71 selective downloads at a pinned upstream revision and
verifies their checksums before rendering. Downloads and generated working
geometry remain under ignored `out/` directories; no upstream source geometry
is vendored in this repository. The ERNE distribution is an archive, from
which the script extracts only `ERNE.gdml`. Its full-instrument SVG exceeds
the converter's XML-node limit, so consecutive same-style lines are combined
into equivalent paths in a render-only intermediate before PDF/PNG conversion.

HET is supplied as a modular GDML document with external XML entities. Its
downloaded fragments remain unchanged; the script expands them only into a
rendering copy under `out/`.

The pinned upstream geometries have several known diagnostics:

- Chandra EPHIN repeats material names in its shielding table.
- SIXS contains degenerate tessellated facets.
- HET emits zero-density material and GDML-extension notices.

These diagnostics are written to `out/g4vm/logs/`, and the downloaded inputs
are not rewritten to suppress them. The complete download manifest is
[`SOURCES.tsv`](SOURCES.tsv); top-level provenance and licences are recorded in
[`gallery/SOURCES.tsv`](../../gallery/SOURCES.tsv). See the [stacked G4VM
gallery](../../gallery/g4vm-views.md) for every canonical view.
