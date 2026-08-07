# Technical architecture

## Goals

- Keep astronomy and catalog behavior deterministic and testable without UI.
- Keep the renderer replaceable.
- Keep file I/O and catalog indexing off the main actor.
- Make chart state explicit rather than reproducing legacy globals.
- Allow additional catalogs without editing the scene, search, or UI pipeline.

## Suggested repository structure

```text
XSky.xcodeproj
XSkyApp/
  App/
  Features/
    Chart/
    Sidebar/
    Inspector/
    Search/
    Settings/
  Rendering/
    CanvasChartRenderer.swift
    ChartCanvasView.swift
Packages/
  XSkyCore/
    Package.swift
    Sources/XSkyCore/
      Astronomy/
      Catalogs/
      Constellations/
      Search/
      Scene/
      Persistence/
    Tests/XSkyCoreTests/
Resources/
  LegacyCatalogs/
XSkyAppTests/
XSkyAppUITests/
design/
README.md
```

The exact grouping may change, but dependency direction may not:

```text
SwiftUI app → renderer adapter → immutable render snapshot
     ↓                              ↑
workspace model → scene builder → XSkyCore
     ↓                              ↑
persistence                    catalog repository actor
```

`XSkyCore` must not import SwiftUI or UIKit. Foundation and CoreGraphics value
types are acceptable, although a small project-owned `Point2D` type is
preferred for projection tests that should also run on macOS/Linux Swift.

## Core value types

Use semantic types instead of naked tuples:

```swift
struct EquatorialCoordinate: Hashable, Sendable {
    var rightAscension: Radians
    var declination: Radians
    var equinox: Equinox
}

struct ChartViewport: Hashable, Sendable {
    var center: EquatorialCoordinate
    var degreesPerPoint: Double
    var sizeInPoints: Size2D
    var orientation: ChartOrientation
}

struct CatalogObjectID: Hashable, Codable, Sendable { ... }
struct CatalogID: Hashable, Codable, Sendable { ... }
```

Define and enforce invariants:

- RA normalized to `[0, 2π)`.
- Declination limited to `[-π/2, π/2]`.
- Positive finite scale.
- J2000 internal catalog coordinates for the first release.
- No `NaN` or infinity crosses a public core boundary.

Avoid a class hierarchy for catalog objects. A value type with optional,
typed properties plus catalog-specific detail data is easier to send between
actors and render.

## Catalog contract

The legacy `cat_header` is the conceptual source, but split its responsibilities
instead of copying the vtable literally:

```swift
protocol CatalogParser: Sendable {
    associatedtype Record: Sendable
    func parse(data: Data) throws -> [Record]
}

protocol CatalogDefinition: Sendable {
    var descriptor: CatalogDescriptor { get }
    func preferredLabel(for object: CatalogObject) -> ChartLabel?
    func searchKeys(for object: CatalogObject) -> [SearchKey]
    func symbol(for object: CatalogObject) -> ChartSymbol
}
```

If associated types make heterogeneous storage cumbersome, erase them at the
repository boundary, not throughout the core.

`CatalogRepository` is an actor responsible for:

- Loading bundled resources.
- Parsing and validating catalogs.
- Building immutable object arrays and search indexes.
- Returning catalog snapshots and load status.
- Building or querying a spatial index.
- Importing the legacy user-catalog format through data supplied by the app,
  then storing an app-owned copy and provenance metadata in Application
  Support. The core repository does not present a file picker itself.

The UI observes a small main-actor projection of load state; it does not own
the catalog arrays.

## Spatial query strategy

Start with deterministic declination/RA bins or a unit-sphere index. The index
must correctly handle RA wrap and polar regions. Do not use a rectangular RA
distance as the final hit test.

Required queries:

- Candidate objects intersecting a viewport's coarse spherical bounds.
- Nearest eligible visible object to a screen point.
- Object by stable identifier.
- Search-key lookup independent of current visibility.

The final visibility and hit tests use the active projection. Magnitude and
catalog filters should be applied before producing render primitives.

## Scene building

`ChartSceneBuilder` accepts immutable inputs and returns a `RenderSnapshot`:

```swift
struct RenderSnapshot: Sendable {
    var viewport: ChartViewport
    var stars: [RenderedStar]
    var objects: [RenderedObject]
    var gridPaths: [Polyline]
    var boundaryPaths: [Polyline]
    var outlinePaths: [Polyline]
    var labels: [RenderedLabel]
    var selection: RenderedSelection?
}
```

The snapshot contains projected coordinates and drawing semantics, not UI
objects or closures. It should be safe to construct off the main actor and
cheap to hand to the renderer.

Scene generation is cancellable. When the viewport changes rapidly, cancel or
discard obsolete builds using a monotonically increasing request generation.
Only the newest snapshot may replace the displayed scene.

## Renderer boundary

Implement the first renderer using SwiftUI `Canvas` and `GraphicsContext`.
Keep all symbol/path/color choices behind a renderer-facing style model.

The renderer must:

- Draw in logical points and let the display scale handle Retina resolution.
- Draw only the immutable snapshot; never perform catalog I/O.
- Preserve layer order: objects, grid, boundaries, outlines, labels, selection.
- Batch stars by spectral color and size where practical.
- Cache resolved label text and static paths when safe.
- Avoid implicit per-symbol animations during pan and zoom.

If measured device performance fails acceptance targets after indexing and
batching, add a Metal renderer behind the same snapshot contract. Do not move
astronomical calculations into shaders merely to conceal an inefficient core.

## Workspace state

Use one `@MainActor @Observable` workspace model for user-visible state:

- `ChartViewport`
- Catalog and layer visibility.
- Magnitude/display settings.
- Current selection.
- User labels.
- Sidebar/inspector visibility.
- Loading, error, and scene-generation status.
- Undo manager integration.

Do not make the catalog repository main-actor isolated. Avoid detached tasks
unless actor inheritance is demonstrably wrong; prefer structured tasks and
explicit cancellation.

During a gesture, maintain transient gesture state separately from committed
viewport state. Commit once at gesture end and register one undo action.

## Labels

Distinguish:

- Object labels anchored to an object's sky coordinate.
- Constellation labels anchored to cataloged constellation centers.
- User labels anchored to an explicit sky coordinate.

Persist label anchors in celestial coordinates and store their text offset in
logical chart points. Reproject anchors whenever the viewport changes. This
fixes the legacy behavior in which some user labels were effectively tied to
screen coordinates.

Automatic label placement may begin with a deterministic offset and simple
collision avoidance. It must never change the underlying object position, and
manual placement always wins.

## Persistence

Use a versioned, Codable document stored in Application Support:

```swift
struct SavedWorkspaceV1: Codable, Sendable {
    var viewport: SavedViewport
    var catalogVisibility: [CatalogID: Bool]
    var layerSettings: LayerSettings
    var magnitudeSettings: MagnitudeSettings
    var displaySettings: DisplaySettings
    var labels: [SavedLabel]
}
```

Write atomically. Decode defensively and migrate by schema version. A corrupt
save must fall back to defaults while preserving the corrupt file for diagnosis
when practical.

Use `SceneStorage` only for ephemeral presentation state. The scientific chart
state needs explicit versioned persistence.

## Errors and diagnostics

Catalog parsing errors contain catalog, record number or byte offset, field,
and a safe excerpt. Decide per catalog whether malformed records are fatal or
skippable; count and expose skipped records in diagnostics.

No parsing path may crash on short records, invalid UTF-8/ASCII, missing
delimiters, unexpected magnitude formats, or absent resources.

Use unified logging categories for startup, catalog loading, scene generation,
search, and persistence. Do not log entire catalog records by default.

## Extensibility

Additional historical catalogs should require:

1. A parser and catalog definition.
2. A bundled or imported resource descriptor.
3. Parser/search/symbol tests.
4. Registration in a catalog registry.

They must not require edits to the chart view, scene builder control flow,
search UI, or persistence schema.

The legacy user catalog is part of the first release. Parse its catalog name,
input equinox, backslash-delimited records, tolerant sexagesimal positions,
user number, label, and description as documented by `usercat.doc` and
`user.c`. Precess imported coordinates to J2000 and search by user number or
label. Use SwiftUI file importing in the app layer and security-scoped access
only for the duration needed to copy/read the selected file.
