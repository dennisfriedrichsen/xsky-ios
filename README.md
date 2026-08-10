# XSky

A native SwiftUI port of [XSky](../xsky), Terry R. Friedrichsen's
interactive X Window System sky atlas (copyright 1992–6). XSky is a static
J2000 equatorial star atlas — deliberately not a live-sky planetarium — for
exploring the bundled Yale Bright Star, Revised NGC, and QSO catalogs and
producing carefully framed finder-chart views.

- Minimum deployment target: iOS 18. Primary experience: iPad, landscape.
- Swift 6 with strict concurrency checking.
- No third-party dependencies.

## Layout

```
XSky.xcodeproj          Xcode project (app + unit tests + UI tests)
XSkyApp/                SwiftUI application and feature views
  App/                  App entry, workspace model, root layout
  Features/             Chart, Sidebar, Inspector, Search, Settings
  Rendering/            Canvas renderer and chart style
Packages/XSkyCore/      Swift package: astronomy, catalogs, search,
                        scene construction, persistence (no UIKit/SwiftUI)
Resources/LegacyCatalogs  Canonical byte-for-byte legacy data files
XSkyAppTests/           App-hosted unit tests (Swift Testing)
XSkyAppUITests/         UI tests (XCTest)
tools/golden/           Golden-fixture generator (compiles legacy C)
design/                 The implementation handoff documents
```

Dependency direction: SwiftUI app → renderer ← immutable `RenderSnapshot`
← `ChartSceneBuilder` ← `XSkyCore` (value types) ← `CatalogRepository`
actor. `XSkyCore` never imports SwiftUI or UIKit.

## Building and testing

Discover an installed iPad simulator first (`xcrun simctl list devices
available`). The commands below use the iPad Pro 13-inch (M4) that ships
with Xcode 26.x; because two similarly named iPad Pro models exist, the OS
version is included.

```sh
# build the app
xcodebuild -project XSky.xcodeproj -scheme XSky \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=18.5' build

# app-hosted unit tests and UI tests
xcodebuild -project XSky.xcodeproj -scheme XSky \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=18.5' test

# core package tests (astronomy, catalogs, search, scene) on macOS
swift test --package-path Packages/XSkyCore

# the same core tests on an iOS simulator
cd Packages/XSkyCore && xcodebuild -scheme XSkyCore \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=18.5' test
```

Core tests locate `Resources/LegacyCatalogs` relative to the repository,
so run them from a full checkout.

## Astronomical fidelity

The astronomical core is ported from the legacy C (`position.c`, `MEEUS`
branch): azimuthal equidistant projection and its inverse, IAU 1976
precession, Herget precession + Nancy Roman's boundary table for
constellation identification, tolerant sexagesimal parsing, viewport
limits, and the "nice interval" grid tables.

Correctness is enforced by golden fixtures generated **from the legacy C
itself** (`tools/golden/generate.sh` compiles the unmodified `position.c`
and extracted Herget routines from the sibling `../xsky` checkout and
writes `Packages/XSkyCore/Tests/XSkyCoreTests/Fixtures/golden.json`). The
Swift implementation is never used to produce its own expected values.

Catalog parity: 9,110 YBS records → 9,096 positioned stars (14 skipped for
blank positions), 8,163 RNGC objects (1975.0 → J2000), 1,549 QSOs (B1950 →
J2000), 89 constellation boundary paths, outlines, centers, 301 star-name
records, 83 NGC common names, RNGC description expansion with the legacy
NF/S ambiguity handling, and the documented legacy user-catalog import
format (`usercat.doc`).

## Measured performance

On an Apple-silicon Mac host driving the iPad Pro 13-inch (M4) simulator
(Xcode 26.6, iOS 18.5 runtime):

- Cold catalog load (parse + spatial index + search corpus for all three
  bundled catalogs plus support tables): ~0.4 s, asserted under 2 s by
  `PerformanceTests.catalogLoadIsFast`. The first chart appears as soon as
  the load completes, well inside the 2-second first-chart target.
- Settled scene rebuild: worst case across four representative viewports
  with boundaries and outlines enabled is asserted under 150 ms
  (`snapshotBuildIsFastEnough`); typical builds run well under 100 ms.
- Search suggestions: five representative queries complete in under
  250 ms total (`suggestionsAreFastEnough`), i.e. p95 well under the
  50 ms-per-query target once the index is ready.
- Memory: 100 repeated pan/zoom scene rebuilds show no monotonic
  render-snapshot growth (`repeatedRebuildsKeepMemoryBounded`).
- Gestures draw the last snapshot through a cheap first-order transform
  while exact rebuilds stream in with stale-generation protection, keeping
  interaction at display refresh rates.

## Data attribution

Everything in `Resources/LegacyCatalogs` is a byte-for-byte copy from the
legacy repository (provenance and SHA-256 hashes in
`design/LEGACY_RESOURCES.md`). Original notices (`ACKNOWLEDGEMENTS`,
`Copyright.txt`, `Warranty.txt`) ship in the app bundle and are surfaced
in the About screen. **A human must review the redistribution terms before
any App Store or commercial release**; the original license forbids sale
and requires crediting the original author.

The pointer used when a mouse or trackpad is attached (`X11Trek` in
`XSkyApp/Assets.xcassets`) is the X11 Trek Cursor, the original cursor
glyph from the X Window System `cursor` font (`XC_trek`, glyph 142),
distributed as part of X.Org's `font-cursor-misc` package; its upstream
`COPYING` file describes these glyphs as "unencumbered." Attribution is
also surfaced in the About screen.

## Known limitations and deviations

- No live-sky/AR mode, location, horizon coordinates, rise/set times, or
  solar-system ephemerides (explicit non-goals of the first release).
- No PostScript/PDF export yet; the renderer boundary supports adding it.
- The legacy native-struct `.bin` caches are intentionally not used.
- User-catalog automatic numbering starts at 1 per `usercat.doc`; the
  legacy `user.c` numbered from 0 (recorded conflict — the documentation
  wins).
- Blank YBS magnitudes read as 0.0 exactly as in the legacy parser; the
  occurrences are counted in load diagnostics.
- Sky-anchored dragging is physically unsatisfiable for some polar drags
  on a north-up chart (the legacy app used scrollbars and never faced
  this); the pan solver clamps at the pole and slides gracefully.
- Two-finger double-tap zoom-out is not implemented; zoom out is on the
  toolbar, keyboard (⌘-), and pinch.
- The legacy SAO/GCVS/UGC/WDS/double-star catalogs are out of scope; the
  architecture accepts new catalogs without touching the chart pipeline.
