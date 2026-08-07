# Astronomy and data specification

## Scope and source of truth

The active legacy implementation is the `MEEUS` branch compiled for
`position.c` by both supplied build systems. Reproduce that branch before
considering numerical improvements.

The app is a J2000 equatorial atlas. Catalog epochs are normalized to the
common equinox during loading. This is precession between catalog coordinate
systems, not time animation.

## Units and conventions

- Internal angles: radians as `Double`.
- Catalog RA input: hours/minutes/seconds or decimal hours.
- Catalog declination input: signed degrees/minutes/seconds or decimal degrees.
- View scale: degrees per logical point.
- Normal orientation: north is up and RA increases toward the left.
- Downunder orientation: rotate the normal chart 180 degrees.
- RA is normalized to `[0, 2π)` after every operation that can wrap.
- Clamp inverse-trigonometric inputs to `[-1, 1]` on every platform.

## Active forward projection

Given chart center `(α₀, δ₀)`, object `(α, δ)`, and
`H = α₀ - α`:

```text
sinAltitude = sin(δ₀)sin(δ) + cos(δ₀)cos(δ)cos(H)
z = π/2 - asin(clamp(sinAltitude, -1, 1))
A = atan2(sin(H), cos(H)sin(δ₀) - tan(δ)cos(δ₀))

xDistance = radiansToDegrees(z sin(A)) / degreesPerPoint
yDistance = radiansToDegrees(z cos(A)) / degreesPerPoint
```

For normal orientation:

```text
x = width/2 + xDistance
y = height/2 + yDistance
```

For downunder orientation:

```text
x = width/2 - xDistance
y = height/2 - yDistance
```

The exact center is a special case with both distances zero. The projection is
azimuthal equidistant: radial screen distance is proportional to angular
separation from the chart center.

Keep projected coordinates as `Double`. Do not reproduce the legacy `floor`
until a raster-specific boundary truly requires it.

## Inverse projection

Port the active inverse equations from `X_to_pos_rad()` in `position.c`. The
inverse must satisfy round-trip tests across:

- Both orientations.
- RA wrap around 0h/24h.
- Centers near both celestial poles.
- Points at viewport center, edges, and corners.
- Very wide and very narrow fields.

For representable points, forward → inverse and inverse → forward errors must
be substantially below one display point and below the precision of catalog
coordinates. Define tolerances explicitly in tests.

Do not use a flat `ΔRA`, `ΔDec` pan approximation. To pan, inverse-project the
gesture's start and current positions and update the center using spherical
geometry so behavior remains stable near poles.

## Precession

Port the IAU 1976 rotation-matrix implementation from `init_precess()` and
`precess()` in `position.c` as a pure value type:

```swift
struct PrecessionTransform: Sendable {
    init(from source: Equinox, to destination: Equinox)
    func apply(to coordinate: EquatorialCoordinate) -> EquatorialCoordinate
}
```

The matrix belongs to the transform instance; it must not be global. Preserve
the legacy constants and arcsecond conversion. Test identity, known epoch
pairs, RA normalization, and repeated deterministic application.

Constellation identification uses a separate Herget transform from J2000 to
B1875 followed by Nancy Roman's boundary table. Preserve this distinction;
do not identify a constellation by point-in-polygon against the decorative
J2000 drawing paths.

## Bundled data

Canonical runtime source files are in `Resources/LegacyCatalogs`. They are
byte-for-byte copies from the sibling legacy repository:

| Resource | Source records | Expected legacy role |
|---|---:|---|
| `ybs.dat` | 9,110; 9,096 positioned | Yale Bright Star catalog |
| `rngc.dat` | 8,163 | Revised NGC deep-sky objects |
| `qso.dat` | 1,549 | Optical QSO catalog |
| `boundaries.dat` | 13,047 | Decorative constellation boundaries |
| `outlines.dat` | 929 | Constellation line drawings |
| `concenters.dat` | 89 | Constellation label/search centers |
| `starnames.dat` | 301 | Common star names keyed by HR number |
| `ngc_names.dat` | 83 | Common NGC names |

Also include the RNGC description/name support tables required by the legacy
formatter. The parser tests must establish the exact loaded counts and explain
every skipped source record.

Read fixed-width data as ASCII-compatible bytes. Field offsets in legacy
headers are byte offsets, not Swift `String.Index` offsets. Parse slices from
`Data` or `[UInt8]`, trim safely, then decode. Never index a Unicode `String`
with catalog byte offsets.

## Catalog object model

The common normalized representation contains:

- Stable `(catalogID, catalogRecordID)` identity.
- J2000 coordinate.
- Optional magnitude.
- Star spectral class or non-stellar object kind.
- Preferred name and alternate designations.
- A reference to catalog-specific detail fields.
- Flags such as nonexistent/unverified or unknown magnitude.

Keep “unknown magnitude” as `nil`, not the legacy sentinel `99.99`.

## YBS behavior

- Parse fixed-width YBS fields as defined by `ybs.h`.
- Skip records with no position, yielding 9,096 positioned objects from the
  bundled source unless a golden check proves otherwise.
- Use visual magnitude for filtering and size.
- Map spectral families to O/B/A/F/G/K/M colors. Preserve legacy grouping of
  W with O and C/N/S-like cool classes with M; unknown classes use the neutral
  star color and produce a diagnostic count rather than a crash.
- Preferred label order: Bayer, Flamsteed, HD/HDE, BD, then HR.
- Search HR/YBS number, Bayer designation, Flamsteed designation, and common
  names from `starnames.dat`.

## RNGC behavior

- Parse fixed-width fields from `rngc.h` and precess 1975.0 positions to J2000.
- Preserve main object-type normalization and symbol mapping.
- Treat malformed/missing magnitude as unknown.
- Respect settings for unknown magnitude and nonexistent/unverified objects.
- Preferred label: Messier designation when available, otherwise NGC/RNGC.
- Search Messier, NGC/RNGC number, and common names.
- Convert description abbreviations into semantic details using the bundled
  description tables. Do not expose the abbreviation stream as the primary UI.

## QSO behavior

- Parse fixed-width fields from `qso.h` and precess B1950 positions to J2000.
- Unknown magnitude is `nil`.
- Render an X mark.
- Search and label by the catalog's positional designation, including the
  `QSO` prefix.

## Legacy user-catalog behavior

- Import the format documented in `usercat.doc` and implemented in `user.c`.
- The first line is the chart/catalog title and the second is the coordinate
  equinox.
- Remaining records are backslash-delimited: user number, RA/Dec, label, and
  description.
- Accept up to the legacy limits at minimum, but do not impose a fixed array
  capacity in the Swift model.
- Precess coordinates from the declared equinox to J2000.
- Render imported objects with an X mark and search by `USER <number>` or the
  user label.
- Malformed records generate actionable diagnostics and do not corrupt valid
  records from the same file.

## Magnitude and symbols

Preserve the legacy relation as a compatibility baseline:

```text
diameter = maxStarDiameter - floor(magnitude - maxSizeMagnitude)
diameter = max(diameter, minimumStarDiameter)
```

Express sizes in points and tune defaults for Retina displays without changing
relative ordering. The faintest visible star must remain selectable without
requiring an oversized visible dot; hit target and drawn diameter are separate.

Non-stellar objects use a separate limiting magnitude. Apply filters before
emitting render primitives.

## Visibility and grid

Preserve the two-stage philosophy:

1. Obtain conservative spherical candidates from the spatial index.
2. Project candidates and perform exact viewport intersection.

A coarse filter may include extra objects but may never exclude a visible
object. Test RA discontinuity and pole-containing views explicitly.

Port the legacy “nice interval” tables for RA and declination grid spacing.
The grid should place at least roughly three major divisions across each chart
dimension and increase RA-line density appropriately near poles. Render paths,
not thousands of independent SwiftUI views.

## Boundaries and outlines

Parse the `-1` path separators and produce celestial polylines. Project paths
with enough subdivision that curved spherical segments are visually smooth at
the current scale. A segment crossing the viewport must not disappear merely
because both endpoints lie outside it.

Cache celestial source paths; rebuild projected paths when the viewport or
scale requires it.

## Golden reference strategy

Before relying on Swift results, create a small host-side reference harness
from the legacy pure C routines or checked-in hand-verified fixture output.
Golden fixtures must cover:

- Sexagesimal parsing and formatting.
- Precession from 1900, 1950, and 1975 to 2000.
- Forward and inverse projection for normal/downunder charts.
- RA wrap and pole cases.
- Representative parsed records from YBS, RNGC, and QSO, including missing
  fields and unknown magnitude.
- Preferred labels and search forms.
- Constellation identification at known interior points and boundaries.

Store fixture inputs and expected outputs in a human-readable versioned file.
Document how to regenerate them. The Swift test target consumes the fixture;
it does not call legacy C during normal app tests.

## Known legacy behavior not to copy blindly

- Native struct `.bin` cache files.
- Platform-specific clamping only on SPARC; clamp universally.
- Global precession matrices.
- Fixed array capacities and unchecked record counts.
- Destructive `strtok` parsing.
- Pixel-flooring inside the mathematical projection.
- The inactive non-Meeus projection branch.
- Screen-coordinate user labels.
- Fixed 80-column detail strings.
