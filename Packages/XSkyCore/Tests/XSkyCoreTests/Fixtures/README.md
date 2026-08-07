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
