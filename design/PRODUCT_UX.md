# Product and UX specification

## Product statement

XSky is an interactive equatorial star atlas for exploring cataloged stars and
deep-sky objects and producing carefully framed finder-chart views. It should
feel like a modern scientific instrument: dark, precise, quiet, fast, and
legible.

It is intentionally not a live-sky application. The first release does not
request location, calculate local horizon coordinates, show the current sky,
or calculate moving solar-system bodies.

## Primary user stories

The user can:

- Open the app and immediately see a useful J2000 chart using YBS and RNGC.
- Pan by dragging and zoom with a pinch while the chart remains responsive.
- See the center RA/Dec and current angular scale at all times.
- Tap near an object to select it and inspect its catalog details.
- Search by constellation, common name, or supported catalog designation and
  center the chart on the result.
- Import a legacy `usercat.dat` file containing transient objects such as a
  comet, asteroid, or observing target.
- Enable or disable catalogs, coordinate grid, constellation boundaries,
  constellation outlines, and labels.
- Change stellar and non-stellar limiting magnitudes.
- Add, move, hide, and remove chart labels without losing their sky anchors.
- Select a rectangular chart region and zoom it to fit.
- Use a red-on-black night mode.
- Undo and redo navigation and chart-setting changes.
- Leave and relaunch without losing the current chart state.

## Landscape iPad layout

Use a collapsible two-region workspace with an optional inspector:

```text
┌──────────────────────────────────────────────────────────────────────────┐
│ toolbar: sidebar · search · center/scale · undo/redo · night · inspector │
├──────────────────┬───────────────────────────────────────┬───────────────┤
│ sidebar          │                                       │ inspector     │
│                  │                                       │ when selected │
│ Catalogs         │              SKY CHART                │               │
│ Layers           │                                       │ identity      │
│ Magnitudes       │                                       │ designations  │
│ Labels           │                                       │ position      │
│ Display          │                                       │ catalog data  │
│                  │                                       │ label actions │
├──────────────────┴───────────────────────────────────────┴───────────────┤
│ optional chart HUD: pointer RA/Dec · field size · equinox J2000          │
└──────────────────────────────────────────────────────────────────────────┘
```

- Default sidebar width: approximately 300 points.
- Default inspector width: approximately 340 points.
- The chart receives all remaining width and is never placed inside a scrolling
  container.
- Sidebar and inspector are independently collapsible from toolbar buttons and
  keyboard shortcuts.
- On narrower widths or portrait, use one visible auxiliary column at a time;
  do not shrink the chart into an unusable strip.

SwiftUI `NavigationSplitView` is acceptable, but a custom composition is also
acceptable if it provides more deterministic chart sizing. Keep navigation
state separate from chart state.

## Visual language

- Background: near black, not a textured or gradient space illustration.
- Stars: filled circles sized by apparent magnitude and colored by spectral
  class when color mode is enabled.
- Grid, boundaries, and outlines: visually distinct, subdued strokes.
- Labels: high-contrast text with a subtle dark halo or backing treatment so
  labels remain readable over symbols and lines.
- Selection: a restrained accent ring and crosshair; do not recolor the object
  so heavily that its catalog symbol becomes ambiguous.
- Use monospaced digits for RA/Dec and scale readouts.
- Night mode: red symbols, strokes, controls, and text on black. Avoid white
  sheets or system backgrounds that destroy dark adaptation.
- Use Dynamic Type in controls and inspector. Chart-label scaling is a separate
  display preference with a sensible lower bound.

Preserve the legacy non-stellar symbol vocabulary:

| Object | Symbol |
|---|---|
| Galaxy | Ellipse |
| Open cluster | Circle |
| Globular cluster | Crossed circle |
| Diffuse/cluster nebula | Square |
| Planetary nebula | Diamond |
| QSO, unknown, user object | X mark |

## Chart interactions

### Touch

- One-finger drag: pan the celestial chart. The sky point under the finger at
  gesture start should remain under that finger, avoiding latitude-dependent
  linear-RA approximations.
- Pinch: zoom continuously around the pinch centroid. Clamp to documented
  minimum and maximum field scales.
- Tap: select the nearest eligible visible object within an adaptive hit radius.
  Prefer non-stellar objects over stars when symbols overlap, matching legacy
  selection priority.
- Double tap: zoom in one step around the tapped sky position.
- Two-finger double tap or toolbar action: zoom out one step.
- Long press: show a context menu for labeling, centering, and copying the
  coordinate. Do not overload long press with required primary behavior.
- “Zoom Region” tool: when armed, drag a rectangular marquee. On release,
  center and scale the selected spherical region to fit the viewport while
  preserving the chart viewport aspect ratio. Provide Cancel.

Gestures may update a cheap preview transform during interaction and rebuild
the exact projected scene when the gesture settles, provided symbols do not
visibly jump.

### Pointer, keyboard, and Pencil

- Pointer/Pencil hover updates the RA/Dec HUD without changing selection.
- Trackpad click behaves like tap; trackpad scrolling pans.
- `Command-F`: focus search.
- `Command-+` and `Command--`: zoom.
- Arrow keys: pan; add Shift for larger steps.
- `Command-Z` / `Shift-Command-Z`: undo/redo.
- `Command-B`: toggle sidebar.
- `Command-I`: toggle inspector.
- Escape: cancel region selection or dismiss transient UI.
- Apple Pencil tap selects precisely; Pencil hover supplies coordinates where
  supported. Core functionality must not require Pencil.

## Search

Search is case-insensitive and whitespace-tolerant. Preserve these forms:

- YBS: `HR 1999`, `YBS 1999`, `alpha Ori`, `61 Cygni`, common star names.
- RNGC: `M 31`, `NGC 7293`, `RNGC 4565`, supported common names.
- QSO: `QSO 1317-277`.
- Full constellation names and standard abbreviations.

Show grouped, ranked suggestions rather than waiting for an exact submission.
Exact catalog identifiers rank first, then exact common names, then prefix and
token matches. Selecting a result centers the chart, selects the object when
applicable, and opens the inspector. Finding an object in a hidden catalog must
work; offer to enable that catalog rather than silently changing layer state.

## Sidebar sections

### Catalogs

Show toggles, object counts, load/error state, and a short catalog name. YBS and
RNGC are enabled initially; QSO is available but disabled initially. Provide
an Import User Catalog action. Imported catalogs appear as ordinary catalog
entries and can be removed without deleting the user's original file.

### Layers

Toggles for coordinate grid, constellation boundaries, constellation outlines,
object labels, star labels, and constellation labels.

### Magnitudes

Separate controls for stellar limiting magnitude, non-stellar limiting
magnitude, and magnitude mapped to maximum star size. Include switches for
unknown-magnitude and catalog-marked nonexistent/unverified objects.

### Labels

Commands to generate eligible labels, generate constellation labels, hide/show
labels, and clear user-generated labels. Destructive clearing requires a
confirmation or an immediately available undo.

### Display

Color/monochrome, north-up/downunder orientation, night mode, chart-label size,
and reset-to-default-view.

## Inspector

The inspector shows:

- Preferred display name and catalog.
- All useful designations.
- J2000 RA/Dec.
- Magnitude and spectral/object class when known.
- The legacy catalog description formatted into semantic rows, not a single
  preformatted 80-column string.
- Actions: center, add/remove label, copy designation, copy coordinate.

Avoid exposing blank fixed-width fields. Preserve their meaning, not their
spacing.

## State and undo

Undoable actions include center, scale, orientation, magnitude limits, catalog
visibility, layer visibility, and label creation/movement/removal. A continuous
pan or pinch produces one undo entry when it ends, not one per frame.

Persist the current view, enabled catalogs/layers, magnitude settings, display
settings, labels, and sidebar/inspector preferences. The undo stack does not
need to survive relaunch.

## Accessibility

- Every control has a meaningful label, value, and hint.
- The chart exposes the selected object and chart center as accessible content.
- Provide a rotor or equivalent navigable list of visible labeled/selected
  objects; thousands of individual invisible accessibility elements are not
  useful.
- Do not encode spectral class or object kind with color alone.
- Respect Reduce Motion by avoiding animated inertial transitions and using
  short cross-fades for scene replacement.

## Explicit non-goals for the first release

- Current-sky or AR mode.
- Device location, horizon, rise/set, or sidereal-time calculations.
- Solar-system ephemerides.
- Editing the bundled catalogs.
- Network catalog downloads.
- PostScript generation. A future PDF/vector export can use the renderer
  boundary after the on-screen app is correct.
- Full parsers for historical catalogs not included in this repository. The
  documented legacy user-catalog format is the exception and is required.
