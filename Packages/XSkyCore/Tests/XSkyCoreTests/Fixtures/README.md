# Golden fixtures

`golden.json` contains reference values generated directly from the legacy
XSky C implementation (the sibling `../xsky` checkout), never from the
Swift code under test:

- `tools/golden/goldengen.c` is compiled together with the **unmodified**
  legacy `position.c` (`-DMEEUS`, the active branch in both legacy build
  systems) and with the Herget precession functions extracted verbatim from
  `boundary.c` plus the Roman constellation table from `con-bounds.h`.
- The inputs (test displays and positions) are duplicated in
  `GoldenFixtures.swift` (`GoldenInputs`); the outputs come from the C code.
- The legacy `display->scale` was a C `float`; the Swift tests reproduce
  that rounding (`Double(Float(scale))`) so comparisons stay exact.

## Regenerating

```sh
tools/golden/generate.sh [path-to-legacy-xsky-checkout]
```

The default legacy path is `../xsky` relative to this repository. The
script never writes into the legacy tree. Regenerate only if the fixture
inputs in `goldengen.c` change; commit the resulting `golden.json`.

Legacy code copyright 1992-6 Terry R. Friedrichsen. Roman boundary table
due to Dr. Nancy G. Roman (1987, PASP, 99, 695); Herget precession credited
to Dr. Wayne H. Warren, Jr.

## `hipparcos/`

Fixture for the Hipparcos parser prototype evaluated in
[ADR 0001](../../../../../design/adr/0001-hipparcos-star-catalog.md). It
supports a design spike; no Hipparcos data is bundled with the app.

- `hip_main_sample.dat` is 16 records copied byte for byte from CDS/VizieR
  I/239 `hip_main.dat` (ESA 1997), chosen to cover every parser branch:
  both declination signs, each kind of missing field, the spectral-type
  characters the legacy colour mapping does not know, a record with no
  astrometric solution, and the double-star entries the `starnames.dat`
  cross-match has to reach through an HD neighbour.
- `hip_main_expected.json` holds the expected parse. Its values come from
  `tools/hipparcos/make_fixture.py`, which implements the published CDS
  byte-by-byte layout independently of the Swift code under test.

### Regenerating

```sh
tools/hipparcos/fetch.sh
tools/hipparcos/make_fixture.py
```

`fetch.sh` downloads about 24 MB from CDS Strasbourg into
`tools/hipparcos/build`, which is gitignored, and prints SHA-256 checksums
to compare against the recorded ones. Commit both regenerated files. To
change which records are covered, edit `SELECTED` in `make_fixture.py`;
each entry carries the reason it was chosen.

Hipparcos data credited to ESA 1997, ESA SP-1200 (Perryman et al.,
1997A&A...323L..49P), distributed by the Centre de Données astronomiques de
Strasbourg.
