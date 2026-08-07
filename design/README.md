# XSky for iPad: implementation handoff

This directory is the design and execution package for implementing XSky as a
native iPad application. The primary target is iPad in landscape orientation;
the minimum deployment target is iOS 18.

This package lives in the standalone `xsky-ios` repository. The legacy C
reference implementation is the sibling repository `../xsky`. Runtime catalog
sources copied for the app are in `../Resources/LegacyCatalogs` relative to
this design directory. If the sibling checkout is mounted elsewhere, locate
the legacy repository before implementation and keep its source read-only.

Start with [FABLE5_IMPLEMENTATION_PROMPT.md](FABLE5_IMPLEMENTATION_PROMPT.md).
It tells the implementation model how to use the other documents and the
legacy C source.

## Documents

- [PRODUCT_UX.md](PRODUCT_UX.md) defines the product, interaction model, and
  visual behavior.
- [ARCHITECTURE.md](ARCHITECTURE.md) defines module boundaries, state,
  concurrency, rendering, and persistence.
- [ASTRONOMY_DATA.md](ASTRONOMY_DATA.md) defines the projection, precession,
  catalogs, symbols, search behavior, and reference-test strategy.
- [DELIVERY_ACCEPTANCE.md](DELIVERY_ACCEPTANCE.md) defines phases, required
  tests, performance targets, and the definition of done.
- [LEGACY_RESOURCES.md](LEGACY_RESOURCES.md) records the copied runtime data,
  provenance, integrity hashes, and cache policy.

## Binding decisions

1. The original C and its comments are the behavioral reference, especially
   `position.c`, `catalog.h`, the catalog readers, `id_object.c`, `grid.c`,
   `boundary.c`, `outline.c`, and `sky.c`.
2. Preserve astronomical and catalog semantics, not the Athena-widget user
   interface.
3. Use SwiftUI for the application shell and a replaceable chart-renderer
   boundary. Implement the first renderer with SwiftUI `Canvas`.
4. Use Swift 6 concurrency checking and value-oriented, `Sendable` core types.
5. Treat angles as radians inside the core and chart scale as degrees per
   logical point. Never mix degrees, radians, hours, pixels, and points without
   explicit types or conversion functions.
6. The first release includes the copied legacy data in this repository: YBS,
   RNGC, QSO, constellation boundaries and outlines, constellation centers,
   star names, and NGC names/descriptions.
7. Build the iOS implementation at this repository's root. Treat the sibling
   legacy source as a read-only behavioral reference.
8. Do not use the legacy `.bin` cache format. It is a native memory dump and is
   not portable.
9. Correctness comes before optimization. Optimize only behind measured
   interfaces and retain golden tests.
10. Before distribution, a human must review the repository's copyright and
    redistribution terms and decide the required attribution and commercial
    distribution policy. The implementation model must preserve notices and
    must not make legal conclusions.

## Apple platform references

- [SwiftUI Canvas](https://developer.apple.com/documentation/swiftui/canvas)
- [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [SpatialTapGesture](https://developer.apple.com/documentation/swiftui/spatialtapgesture)
- [Observation](https://developer.apple.com/documentation/observation)
- [Swift Testing](https://developer.apple.com/documentation/testing)
- [Apple testing guidance](https://developer.apple.com/documentation/xcode/testing)
