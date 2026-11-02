# ADR 0001: Hipparcos as a star catalog source

- Status: **Accepted** (decision recorded; no implementation authorized by
  this ADR)
- Date: 2026-08-10
- Issue: [#30](https://github.com/dennisfriedrichsen/xsky-ios/issues/30)
- Supersedes: nothing
- Supporting data:
  [hipparcos-crossmatch.md](../reports/hipparcos-crossmatch.md),
  `Packages/XSkyCore/Sources/XSkyCore/Catalogs/Prototypes/HipparcosParser.swift`,
  `Packages/XSkyCore/Tests/XSkyCoreTests/HipparcosPrototypeTests.swift`

## Decision

**Hybrid, in one direction only: keep `ybs.dat` as the star catalog, and
treat Hipparcos as a future supplementary layer joined to YBS by HD
number. Do not replace YBS.**

Concretely:

1. `ybs.dat` remains the sole source of star positions, labels, and search
   identity. Nothing about the current runtime pipeline changes.
2. Full replacement is **rejected**, primarily because Hipparcos carries no
   Bayer or Flamsteed designations at all. That is the product regression
   the issue already flagged as a likely blocker, and the byte layout
   confirms it is unavoidable rather than merely inconvenient.
3. If Hipparcos is adopted later, it enters as a **separate, optional
   faint-star layer plus a per-star enrichment** (parallax, distance,
   proper motion), keyed HR -> HD -> HIP. YBS keeps ownership of
   designations, labels, and catalog identity.
4. If that layer is built, the source is the **1997 ESA release, CDS/VizieR
   I/239 `hip_main.dat`**, not the van Leeuwen revised reduction — see
   "Which distribution" below, which reverses the issue's expectation.
5. Adopting the layer requires a **build-time transform to a compact binary**
   and therefore an explicit, separate decision to break the byte-for-byte
   bundling property. This ADR does not grant that.

## Context

The issue proposed evaluating Hipparcos against the bundled Yale Bright
Star catalog on precision, star count, parallax, and proper motion. The
evaluation was run against the real files; every number below is measured,
not quoted, and is reproducible via `tools/hipparcos/`.

The framing that drove the outcome: this app is an azimuthal-equidistant
atlas whose scale is expressed in **degrees per logical point**. At the
widest charts measured here, one point is 0.2°; at the narrow end, 0.01°,
or 36 arcseconds. YBS positions are quoted to 0.1s of RA and 1" of
declination. Hipparcos's ~0.7–0.9 mas astrometry is therefore roughly four
orders of magnitude finer than a single rendered pixel at the *narrowest*
supported chart. **Positional precision is not a user-visible improvement
for this product.** The genuine wins are parallax (which YBS lacks
entirely) and star count.

## Findings

### Which distribution

| | I/239 `hip_main.dat` | I/311 `hip2.dat` |
|---|---|---|
| Release | ESA 1997, SP-1200 | van Leeuwen 2007 |
| Records | 118,218 | 117,955 |
| Line format | 450 bytes + **CRLF** | 276 bytes + LF |
| Johnson V | yes | **no** (Hp only) |
| Spectral type | yes | **no** |
| HD / BD / CoD / CPD | yes | **no** |
| Parallax, proper motion | yes | yes, improved |

The issue expected the revised reduction to be the obvious target. It is
not. I/311 is astrometry only: it carries no photometric V, no spectral
type, and **no cross-identifications whatsoever**. It cannot drive the
O/B/A/F/G/K/M colour mapping, cannot be magnitude-filtered on V, and
cannot be joined to `starnames.dat` on its own. Using it means shipping
both files and joining them on HIP — double the bundle for an astrometric
improvement that, per the reasoning above, is invisible at this app's
scale.

The record counts also differ, contrary to the issue's "same star count":
I/311 omits the 263 entries that have no astrometric solution. Every I/311
entry is present in I/239.

Two format details worth recording because they are not obvious from the
published tables: `hip_main.dat` is **CRLF-terminated** while `hip2.dat`
is not, and the ReadMe's byte ranges are one-based inclusive. The existing
`RecordSplitter` already strips a trailing CR, so neither needed a change.

### Parsing compatibility

The prototype parses `hip_main.dat` through the existing
`FixedWidthRecord` and `RecordSplitter` **unchanged**. The documented rule
in `ASTRONOMY_DATA.md` — byte offsets, never Swift `String.Index` — holds
for Hipparcos exactly as for YBS.

One deliberate divergence: the prototype does **not** use
`FixedWidthRecord.doubleValue`. That method reimplements C `atof` digit by
digit to stay bug-compatible with the legacy reader, and it is not
correctly rounded; it disagrees with `strtod` by up to one ULP on
Hipparcos's eight-decimal degree fields. There is no legacy Hipparcos
behaviour to reproduce, so the prototype uses the correctly rounded
conversion. This is worth knowing independently of Hipparcos: the legacy
`atof` port is a compatibility shim, not a general-purpose parser.

### Epoch handling

Hipparcos positions are ICRS at epoch J1991.25. The ICRS is aligned with
the J2000 frame far below catalogue precision, so normalizing to the app's
common equinox is **proper-motion propagation only** — no precession
rotation, unlike RNGC (1975.0) and QSO (B1950). The prototype propagates
with unit vectors rather than adding `pmRA / cos(δ)` to right ascension, so
it stays correct at the poles. Radial velocity is not in the catalogue, so
this is the standard no-radial-velocity approximation.

This is a *new* concept for the pipeline, not the natural fit the issue
assumed: the existing machinery precesses between equinoxes and has no
notion of propagating an object through time.

### Field population (118,218 records)

| Field | Missing |
|---|---:|
| position and parallax | 263 |
| Johnson V | 1 |
| HD cross-identification | **19,338** |
| spectral type | 3,034 |

Missing values are blank, never a sentinel, so the "unknown magnitude is
`nil`, never `99.99`" rule maps cleanly.

The 19,338 records with no HD are the load-bearing number for the hybrid:
**16% of Hipparcos cannot be joined to YBS by HD at all.** Those stars can
only ever be labelled "HIP n".

### Spectral class

`SpType` is present and its first character feeds the legacy `StarColor`
mapping directly. 190 records begin with a character outside
W/O/B/A/F/G/K/M/C/N/S — mostly `R` (89, carbon stars), lowercase `s` (69),
and `D` (27, white dwarfs) — plus 3,034 with no type. Together 3,224
records (2.7%) render neutral and produce a diagnostic. That is a
manageable diagnostic count, and `R` in particular should be grouped with
M alongside the existing C/N/S grouping if this ever ships.

### Magnitude semantics

Use **Johnson V** (`Vmag`), not `Hp`. V is what the existing limiting-
magnitude settings and the `StarSizing` relation are calibrated against;
`Hp` is a different photometric system and would silently shift every
magnitude filter. Exactly one record lacks V.

### Bundle size

| Candidate | Records | Raw | gzip -9 |
|---|---:|---:|---:|
| `hip_main.dat` verbatim | 118,218 | 53.4 MB | 14.8 MB |
| rows with V ≤ 9 | 83,392 | 37.7 MB | 10.4 MB |
| compact binary, 36 B/record | 118,218 | 4.3 MB | — |
| compact binary, V ≤ 9 | 83,392 | 3.0 MB | — |

`ybs.dat` is 1.2 MB. Bundling `hip_main.dat` verbatim is a 45× increase in
catalog payload to carry fields the app never reads — the record is 450
bytes of which roughly 40 are useful here. Row subsetting does not help
much because the waste is per-record, not per-row-count.

Only the compact-binary path is viable, and it **breaks the byte-for-byte
copy property** that `ASTRONOMY_DATA.md` and `LEGACY_RESOURCES.md` treat as
deliberate. That tradeoff is real and is not settled by this ADR: it needs
its own decision, because it changes provenance from "these are the legacy
files" to "these are files we generated", with the verification burden that
implies.

### Cross-match to `starnames.dat`

All 301 HR-keyed names resolve to a HIP entry: 295 by exact HD, and 6
through a documented fallback.

The 6 are a single systematic failure mode, not a scatter of edge cases.
YBS lists the components of a close visual double as separate HR records
with consecutive HD numbers; Hipparcos publishes one combined astrometric
solution carrying only one component's HD. The fallback looks at HD ± 1
and ± 2 for an entry Hipparcos itself marks as a double or multiple (a
CCDM identifier, a component identifier `m_HIP`, or `Ncomp ≥ 2`), and it is
unambiguous for all six: Alrisha, Regor, Tegmen, Alula Australis, Izar,
Arrakis.

**This is a merge, not a rename.** The named secondary and its primary
resolve to the *same* HIP entry, so under full replacement those pairs
would collapse into one chart object and one of the two names would have
nowhere to go. Under the hybrid, YBS keeps both records and the merge is
harmless.

Across the whole bright-star layer, 8,998 of the 9,096 positioned YBS
records have an exact HD match (98.9%); the 98 that do not are the same
merged-double case plus a few genuine absences. **De-duplication by HD is
tractable** — which is the main reason the hybrid is recommended over
"keep YBS and do nothing".

### Bayer and Flamsteed designations

`hip_main.dat` has no Bayer or Flamsteed field. The preferred label order
in `ASTRONOMY_DATA.md` is Bayer, Flamsteed, HD/HDE, BD, then HR; Hipparcos
supplies only HD and BD from that list. Recovering Bayer/Flamsteed after a
full replacement would mean retaining a YBS-derived designation table —
i.e. keeping YBS anyway, in a degraded form, purely as a label source.

This alone decides against full replacement.

### Performance

Measured on the host in release configuration, over the real 118k-record
catalogue, running the exact `ChartSceneBuilder` inner loop (coarse
candidates → magnitude filter → exact viewport intersection). The test is
`fullCatalogueParseAndIndexCost`, skipped unless `tools/hipparcos/fetch.sh`
has been run.

| Chart | Limit | Hipparcos | YBS |
|---|---:|---|---|
| wide (0.2°/pt) | 6.5 | 91,408 cand → 5,357 drawn, 2.1 ms | 6,916 → 5,065, 0.44 ms |
| wide | 9.0 | 91,408 → 50,698, 7.1 ms | 6,916 → 5,487, 0.45 ms |
| medium (0.05°/pt) | 6.5 | 6,539 → 642, 0.23 ms | 697 → 611, 0.05 ms |
| medium | 9.0 | 6,539 → 4,824 , 0.44 ms | 697 → 672, 0.05 ms |
| pole-containing | 6.5 | 96,606 → 5,377, 1.7 ms | 7,611 → 5,140, 0.47 ms |
| pole | 9.0 | 96,606 → 49,765, 6.9 ms | 7,611 → 5,585, 0.50 ms |

Parsing and propagating all 118,218 records takes 0.34 s; building the
spatial index takes 2 ms.

The two-stage visibility strategy stays **correct** — the coarse filter
never excludes a visible object — but it degrades badly at scale. The
one-degree declination-band index plus a conservative RA test returns
77–82% of the entire catalogue for a wide chart, so the per-frame cost is
driven by the candidate scan, not by what is drawn. That is a 5–15×
increase over YBS.

Extrapolating to the iPad 7th generation (A10 Fusion, roughly 4–6× slower
single-core than this host): ~8–13 ms per frame at limiting magnitude 6.5,
which fits; ~30–40 ms at limiting magnitude 9, which does not. Drawing
50,000 stars is separately a rendering problem, not only a compute one.

**This extrapolation is not a device measurement and is explicitly
deferred** — see below. But it is enough to say that adopting Hipparcos
requires index work (magnitude-stratified or hierarchical candidates), not
just a bigger array.

### Licensing and attribution

Facts only. Per binding decision 10 in `design/README.md`, the legal
conclusion is a human's to make and is **deferred**.

- I/239 is credited to ESA 1997, published as ESA SP-1200, catalogue
  reference `1997HIP...C......0E`, primary paper Perryman et al.
  (1997A&A...323L..49P). It is distributed publicly by the Centre de
  Données astronomiques de Strasbourg.
- I/311 is credited to Floor van Leeuwen (Institute of Astronomy,
  Cambridge), *Hipparcos, the New Reduction of the Raw Data*,
  Astrophysics & Space Science Library #350, 2007.
- Neither ReadMe states an explicit redistribution licence. CDS's general
  practice is citation-based attribution rather than a formal licence
  grant, which is not the same thing as a confirmed right to redistribute
  inside a shipped application.

Nothing from either distribution is committed to this repository except
16 sample records used as a test fixture. No entry has been added to
`Resources/Notices/ACKNOWLEDGEMENTS` or `NOTICES.txt`, because
nothing is bundled.

## Consequences

### Answered, and settled by this ADR

- **Source format** — I/239 `hip_main.dat`, fixed 450-byte CRLF records,
  compatible with the existing byte-offset parser. I/311 rejected for
  lacking V, spectral type, and all cross-identifications.
- **Replacement vs supplement** — supplement. Full replacement rejected on
  Bayer/Flamsteed loss, on 16% of entries having no HD bridge, and on the
  six named doubles that would collapse into their primaries.
- **Common-name mapping** — HD bridge, 295/301 exact, 301/301 with the
  documented merged-double fallback. `starnames.dat` stays keyed by HR and
  stays byte-for-byte legacy.
- **Bayer/Flamsteed** — unavailable from Hipparcos; YBS retains ownership.
- **Spectral class** — present, compatible, 2.7% neutral-with-diagnostic.
  `R` should join the C/N/S grouping.
- **Magnitude semantics** — Johnson V, blank means `nil`.
- **File size** — measured; only a compact binary is viable, and that
  requires a separate decision about the byte-for-byte property.
- **Identity and stability** — a Hipparcos layer would use
  `CatalogID("HIP")` with `catalogRecordID` = the HIP number itself rather
  than a parse-order index, since HIP numbers are stable across both
  distributions. Because YBS is untouched, **no persisted user state is
  invalidated.** This is a direct benefit of the hybrid over replacement,
  which would have orphaned every saved workspace keyed to a YBS record
  index.
- **Search coverage** — unchanged. HR, Bayer, Flamsteed, and common names
  continue to work against YBS. If the layer ships, HIP joins as an
  additional searchable identifier; HR is never removed.

### Deferred, with reasons

- **Performance on the iPad 7th generation.** Host measurements and a
  scaling estimate only. A device run is required before any adoption, and
  the estimate already indicates the spatial index needs work at limiting
  magnitudes above ~7. Deferred because it gates implementation, not the
  decision to keep YBS.
- **Redistribution rights.** Requires human legal review per binding
  decision 10. Deferred rather than dropped; it blocks bundling, not this
  ADR.
- **Breaking the byte-for-byte bundling property.** Named here, not
  decided. It becomes live only if the supplementary layer is actually
  proposed.

### Not addressed

None. Every checklist item in issue #30 appears above as answered or
explicitly deferred.

## What this ADR does not authorize

No change to `Resources/LegacyCatalogs`, the catalog loader, the object
model, search, or rendering. `HipparcosParser` is a spike: it is not
registered with `CatalogRepository`, does not produce `CatalogObject`, and
is unreachable from the app. A later PR proposing the supplementary layer
must reference this ADR and must resolve the three deferred items first.
