# Prompt for Fable 5

You are the senior engineer responsible for implementing a native iPad version
of XSky in this repository. Work autonomously but transparently. Plan the work,
make small reviewable changes, build frequently, run tests after every phase,
and report concrete evidence. Do not merely scaffold or produce mock screens:
deliver a working star-chart application.

## Mission

Port the behavior and spirit of the legacy XSky C application to a native
SwiftUI application for iPad, with a minimum deployment target of iOS 18. The
primary experience is iPad landscape. The original is a static equatorial sky
atlas, not a real-time planetarium; preserve that scope.

The first production milestone must load and display the bundled YBS, RNGC,
and QSO catalogs, constellation boundaries/outlines, constellation centers,
and name tables. It must also import the documented legacy user-catalog format
for transient objects. It must support smooth chart navigation, object
selection, search, layer/catalog controls, labels, magnitude controls, night
mode, undo/redo of chart-state changes, and restoration of saved state.

## Read before editing

Read these documents completely, in order:

1. `design/README.md`
2. `design/PRODUCT_UX.md`
3. `design/ARCHITECTURE.md`
4. `design/ASTRONOMY_DATA.md`
5. `design/LEGACY_RESOURCES.md`
6. `design/DELIVERY_ACCEPTANCE.md`

Then survey the legacy source directly in the sibling `../xsky` repository.
Its comments are source material, not noise. If that checkout is mounted at a
different path, locate it before editing. At minimum read:

- `README`, `xsky.man`, `catalogs.doc`, and `usercat.doc`
- `catalog.h`, `catalog.c`, `catdefs.h`, and `catreader.h`
- `position.c` and `pos.h`
- `ybs_read.c`, `rngc_read.c`, `qso_read.c`, and their display files
- `id_object.c`, `draw.c`, `grid.c`, `boundary.c`, and `outline.c`
- the startup, layout, drawing, gesture, zoom, scroll, save, and undo sections
  of `sky.c`

You have direct access to both repositories. Read the legacy source in place;
do not ask for pasted excerpts and do not treat this prompt as a substitute
for reading it. Treat the legacy repository as read-only.

When a handoff document and the legacy implementation appear to conflict,
record the conflict. Follow the handoff for modern UI/product behavior and the
active `-DMEEUS` legacy path for astronomical behavior. Do not silently guess.

## Non-negotiable engineering constraints

- Use Swift and SwiftUI. Prefer async/await and Observation.
- Minimum deployment target: iOS 18. Primary device: iPad landscape.
- Enable Swift 6 strict concurrency checking.
- Do not force unwrap in production code.
- Keep the astronomical/catalog core independent of SwiftUI and UIKit.
- Use `Double` for angles and projection calculations.
- Use typed identifiers and typed angle/scale wrappers where they prevent unit
  mistakes.
- Do not translate `sky.c` line by line or recreate its global-state design.
- Do not modify or delete the sibling legacy C source or original data files.
- Do not use the legacy native-structure `.bin` caches.
- Do not add third-party dependencies unless the standard frameworks cannot
  reasonably solve the problem; document and justify any exception first.
- Do not commit, push, or change repository remotes unless explicitly asked.
- Keep source files under 500 lines when practical.
- Preserve original author attribution in the app's About screen and source
  documentation. Flag licensing for human review; do not offer legal advice.

## Required repository shape

At this repository's root, create:

- A buildable Xcode project or workspace.
- `XSkyApp`, the SwiftUI application and feature views.
- `XSkyCore`, a local Swift package containing astronomy, catalogs, search,
  scene construction, and persistence value types.
- Unit/integration tests using Swift Testing.
- UI tests using XCTest.
- A root `README.md` with exact build/test commands and architecture.

Use `Resources/LegacyCatalogs` as the canonical in-repository runtime source.
These files are byte-for-byte copies from the legacy repository. Add them to
the app bundle by explicit resource references or a deterministic copy step;
do not hand-edit them. Preserve the accompanying notices and provenance file.

## Execution method

1. Inspect the available Xcode/Swift toolchain and installed simulator
   runtimes. Do not assume device names.
2. Establish a buildable empty app and core package.
3. Before building UI, port and test coordinate conversion, precession, active
   projection/inverse projection, visibility, and parsers.
4. Create golden fixtures from the legacy C behavior. Do not use the new Swift
   implementation to generate its own expected values.
5. Implement catalog loading and search off the main actor.
6. Build an immutable render snapshot and the Canvas renderer.
7. Add chart gestures and then the surrounding UI.
8. Add persistence, accessibility, UI tests, performance tests, and visual QA.
9. Run the full build/test matrix from `DELIVERY_ACCEPTANCE.md`.
10. Finish with a concise report of behavior delivered, commands run, test
    results, remaining known issues, and any documented deviations.

If work is too large for one pass, complete it in the numbered phases from
`DELIVERY_ACCEPTANCE.md`. Each phase must leave the repository building and
tested. Do not hide incomplete behavior behind buttons that do nothing.

## Product priorities

In descending order:

1. Astronomical correctness and deterministic parsing.
2. A chart that is delightful and legible on iPad in landscape.
3. Fast, direct pan/pinch/select interactions.
4. Complete behavior for bundled catalogs.
5. Accessibility, keyboard, pointer, and Apple Pencil support.
6. Extensibility to additional catalogs and a Metal renderer.

## Final acceptance

Do not call the task complete until all mandatory checks in
`DELIVERY_ACCEPTANCE.md` pass. A screenshot or successful launch alone is not
completion. The app must build from a clean checkout, tests must pass, catalog
counts and golden astronomical fixtures must match, and the primary iPad
landscape workflows must work end to end.
