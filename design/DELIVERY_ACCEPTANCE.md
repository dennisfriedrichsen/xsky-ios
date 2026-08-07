# Delivery plan and acceptance criteria

Every phase must leave the repository building and its completed tests passing.
Do not defer correctness tests until the UI is finished.

## Phase 0: project and reference baseline

Deliver:

- Root project/workspace and local `XSkyCore` package.
- iOS 18 deployment target and Swift 6 strict concurrency.
- Exact documented `xcodebuild` commands using an installed iPad simulator.
- Legacy-generated golden fixture and regeneration instructions.
- CI-friendly test scheme shared in the project.

Acceptance:

- App target builds from the command line.
- Empty launch test passes.
- Core package tests run independently where supported.
- No changes to the sibling legacy source/data.

## Phase 1: astronomical core

Deliver:

- Angle/coordinate/equinox value types.
- Sexagesimal conversion and tolerant input parser.
- IAU 1976 precession transform.
- Active forward/inverse projection.
- Conservative viewport bounds and exact visibility.
- Roman/Herget constellation identification.
- Grid interval selection.

Acceptance:

- Golden fixtures match within written tolerances.
- Forward/inverse property tests cover random valid centers/points plus poles
  and RA wrap.
- All outputs are finite for valid inputs.
- Normal and downunder orientation tests pass.

## Phase 2: bundled catalogs and search

Deliver:

- Robust byte-oriented parsers for YBS, RNGC, QSO, boundary, outline, center,
  star-name, NGC-name, required description tables, and the legacy user-catalog
  format.
- Normalized catalog model, repository actor, indexes, and load diagnostics.
- Preferred names, symbols, detail models, and search index.

Acceptance:

- Bundled sources parse deterministically with expected counts.
- Every skipped record is counted and covered by a reason/test.
- Representative malformed and truncated records fail safely.
- Search tests cover every documented designation form.
- User-catalog tests cover alternate equinoxes, omitted automatic numbers,
  long descriptions, malformed records, label search, and object removal.
- Loading/parsing does not run on the main actor.
- No use of legacy `.bin` files.

## Phase 3: chart rendering and navigation

Deliver:

- Immutable render snapshot and scene builder.
- Canvas renderer for stars, object symbols, grid, boundaries, outlines,
  labels, and selection.
- Pan, pinch, tap selection, double-tap zoom, region zoom, pointer/Pencil hover,
  keyboard zoom/pan, and chart HUD.
- Generation cancellation/stale-result protection.

Acceptance:

- Orion-area and M31-area reference views visually contain the correct major
  stars/objects and orientations.
- Tap selection prefers a non-stellar object over a coincident star.
- Pinch is anchored to its centroid within one logical point after commit.
- Pan remains stable at high declination and across 0h RA.
- No stale render snapshot replaces a newer viewport.
- Layer order matches the design specification.

## Phase 4: complete product UI

Deliver:

- Landscape workspace, collapsible sidebar, toolbar, search, and inspector.
- Catalog/layer/magnitude/display controls.
- Object, constellation, and user labels with manual positioning.
- User-catalog import, app-owned persistence, visibility, search, and removal.
- Night mode, monochrome mode, and downunder orientation.
- Undo/redo and versioned state restoration.
- About/credits and licensing-review notice.

Acceptance:

- All primary user stories in `PRODUCT_UX.md` work end to end.
- A continuous gesture creates one undo entry.
- Relaunch restores chart state and labels.
- Hidden-catalog search works without silently enabling the catalog.
- Night mode has no unintended bright sheet or control surfaces.

## Phase 5: quality gate

Deliver:

- Swift Testing unit/integration suite.
- XCTest UI suite for primary workflows.
- Accessibility audit and labels.
- Performance and memory measurements on an available iPad simulator and, when
  available, a physical iPad.
- README with architecture, data attribution, build/test commands, and known
  limitations.

Mandatory command checks:

```text
xcodebuild -project <project> -scheme <scheme> \
  -destination 'platform=iOS Simulator,name=<installed iPad>' build

xcodebuild -project <project> -scheme <scheme> \
  -destination 'platform=iOS Simulator,name=<installed iPad>' test
```

If the implementation uses a workspace, substitute `-workspace`. Discover the
actual installed destination with `xcrun simctl list devices available`; do not
hard-code a simulator that does not exist.

## Correctness requirements

- Zero known projection/precession golden-test failures.
- Zero catalog count/search golden-test failures.
- No crashes or force unwraps on corrupt persistence or malformed catalog
  fixtures.
- No data races reported by strict concurrency checking; run Thread Sanitizer
  on focused integration tests when practical.
- No main-thread catalog parsing.

## Performance targets

Measure rather than claim. For bundled catalogs on a representative landscape
iPad viewport:

- First useful chart visible within 2 seconds after a cold launch on a current
  simulator host or current physical iPad; record environment and result.
- Settled scene rebuild p95 under 100 ms for typical views.
- Gesture preview should maintain approximately 60 fps; exact scene rebuild
  may settle immediately after the gesture if necessary.
- Search suggestion update p95 under 50 ms after the index is ready.
- Memory must remain bounded across 100 repeated pan/zoom operations with no
  monotonic render-snapshot growth.

These are product targets, not permission to weaken correctness. If Canvas
misses the frame target after measured batching/indexing improvements, record
the profile and implement the Metal renderer behind the existing boundary.

## UI test workflows

Automate at least:

1. Launch → chart appears → default YBS/RNGC layers enabled.
2. Search `M 31` → center/select → inspector shows M31/RNGC data.
3. Search `Sirius` → center/select → YBS details visible.
4. Toggle boundaries/outlines/grid and verify state survives relaunch.
5. Pan and pinch → undo → redo.
6. Enter night mode and verify the app's declared state and screenshot baseline.
7. Add, move, remove, undo, and restore a label.
8. Region zoom and cancel paths.
9. Import `usercat.example` → locate `Test Object` → remove the imported
   catalog without altering the source file.

Use stable accessibility identifiers for controls needed by UI tests.

## Visual review matrix

Capture landscape screenshots for at least:

- 11-inch iPad size class, sidebar open, no inspector.
- 13-inch iPad size class, sidebar and inspector open.
- Sidebar collapsed for maximum chart area.
- Dynamic Type at default and an accessibility size.
- Normal color, monochrome, and night mode.
- North-up and downunder orientations.
- Sparse wide field and dense zoomed field.

Inspect for clipped controls, illegible labels, symbol ambiguity, bright night
mode surfaces, chart jumps, and incorrect north/RA orientation.

## Definition of done

The implementation is done only when:

- A clean checkout builds and tests using documented commands.
- All mandatory phases and workflows pass.
- The bundled data appears in a usable, responsive chart.
- Astronomy/catalog results match independent legacy-derived fixtures.
- There are no placeholder screens, dead controls, or silently swallowed fatal
  load errors.
- Documentation lists remaining non-goals and known limitations honestly.
- The legacy tree remains intact and the git diff contains only intentional
  iOS implementation and documentation changes.
