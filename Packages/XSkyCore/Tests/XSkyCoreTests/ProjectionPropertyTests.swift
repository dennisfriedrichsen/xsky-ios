import Foundation
import Testing

@testable import XSkyCore

/// A tiny deterministic RNG (SplitMix64) so property tests are repeatable.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

@Suite("Projection round-trip properties")
struct ProjectionPropertyTests {

    private func makeViewports(_ rng: inout SeededRandom) -> [ChartViewport] {
        var viewports: [ChartViewport] = []
        // random centers, plus deliberate pole and RA-wrap centers
        var centers: [(Double, Double)] = [
            (0.001, 89.5 / Angles.degreesPerRadian),
            (3.0, -89.5 / Angles.degreesPerRadian),
            (6.28, -0.1),
            (0.01, 0.1),
        ]
        for _ in 0..<12 {
            centers.append(
                (
                    rng.double(in: 0...(2 * .pi - 0.0001)),
                    rng.double(in: -1.55...1.55)
                ))
        }
        for (ra, dec) in centers {
            for scale in [0.001, 0.05, 0.3] {
                for orientation in [ChartOrientation.normal, .downunder] {
                    viewports.append(
                        ChartViewport(
                            center: EquatorialCoordinate(
                                rightAscension: Radians(ra),
                                declination: Radians(dec)),
                            degreesPerPoint: scale,
                            sizeInPoints: Size2D(width: 1024, height: 768),
                            orientation: orientation))
                }
            }
        }
        return viewports
    }

    /// unproject(project(p)) must land back on p for points well inside
    /// the projection's domain, to far below one display point.
    @Test func inverseThenForwardRoundTrip() {
        var rng = SeededRandom(seed: 0xC0FFEE)
        let viewports = makeViewports(&rng)

        for viewport in viewports {
            let w = viewport.sizeInPoints.width
            let h = viewport.sizeInPoints.height
            var probes: [Point2D] = [
                Point2D(x: w / 2, y: h / 2),
                Point2D(x: 0.5, y: 0.5),
                Point2D(x: w - 0.5, y: 0.5),
                Point2D(x: 0.5, y: h - 0.5),
                Point2D(x: w - 0.5, y: h - 0.5),
            ]
            for _ in 0..<8 {
                probes.append(
                    Point2D(
                        x: rng.double(in: 0...w), y: rng.double(in: 0...h)))
            }
            for probe in probes {
                // the azimuthal equidistant projection is invertible only
                // within 180 degrees of the center; keep a safety margin
                let dxc = probe.x - w / 2
                let dyc = probe.y - h / 2
                let angularRadius =
                    (dxc * dxc + dyc * dyc).squareRoot()
                    * viewport.degreesPerPoint
                guard angularRadius < 170 else { continue }
                let coordinate = ChartProjection.unproject(probe, in: viewport)
                #expect(coordinate.rightAscension.value.isFinite)
                #expect(coordinate.declination.value.isFinite)
                let back = ChartProjection.project(coordinate, in: viewport)
                let dx = back.x - probe.x
                let dy = back.y - probe.y
                #expect(
                    (dx * dx + dy * dy).squareRoot() < 0.01,
                    "viewport \(viewport.center) \(viewport.orientation) probe \(probe) -> \(back)"
                )
            }
        }
    }

    /// project(unproject(x)) for random sky positions that fall inside the
    /// viewport must also round-trip in the angular domain.
    @Test func forwardThenInverseRoundTrip() {
        var rng = SeededRandom(seed: 0xBADA55)
        let viewports = makeViewports(&rng)

        for viewport in viewports {
            for _ in 0..<10 {
                let ra = rng.double(in: 0...(2 * .pi - 1e-9))
                let dec = rng.double(in: -1.57...1.57)
                let p = ChartProjection.project(
                    rightAscension: ra, declination: dec, in: viewport)
                #expect(p.x.isFinite && p.y.isFinite)
                guard p.x >= 0, p.x < viewport.sizeInPoints.width,
                    p.y >= 0, p.y < viewport.sizeInPoints.height
                else { continue }
                let c = ChartProjection.unproject(p, in: viewport)
                let separation = ChartProjection.angularSeparation(
                    c,
                    EquatorialCoordinate(
                        rightAscension: Radians(ra), declination: Radians(dec))
                )
                // well below both a display point and catalog precision
                let pointInRadians =
                    viewport.degreesPerPoint / Angles.degreesPerRadian
                #expect(
                    separation.value < pointInRadians * 0.01,
                    "\(viewport.center) \(viewport.orientation): (\(ra), \(dec)) separation \(separation.value)"
                )
            }
        }
    }

    /// Conservative bounds may include extra sky but must never exclude a
    /// position that projects inside the viewport.
    @Test func boundsNeverExcludeVisiblePositions() {
        var rng = SeededRandom(seed: 0x5EED)
        let viewports = makeViewports(&rng)

        for viewport in viewports {
            // the legacy quick filter (matched bit-for-bit by the golden
            // withinLimits fixtures) only guarantees inclusion when the
            // chart's half-diagonal is under 90 degrees; beyond-the-pole
            // fields drop far-side sky in the legacy app as well
            let w = viewport.sizeInPoints.width
            let h = viewport.sizeInPoints.height
            let halfDiagonalDegrees =
                (w * w + h * h).squareRoot() / 2 * viewport.degreesPerPoint
            guard halfDiagonalDegrees < 90 else { continue }
            let bounds = ViewportBounds(for: viewport)
            for _ in 0..<40 {
                let ra = rng.double(in: 0...(2 * .pi - 1e-9))
                let dec = rng.double(in: -Double.pi / 2...Double.pi / 2)
                let p = ChartProjection.project(
                    rightAscension: ra, declination: dec, in: viewport)
                let visible =
                    p.x >= 0 && p.x < viewport.sizeInPoints.width && p.y >= 0
                    && p.y < viewport.sizeInPoints.height
                if visible {
                    #expect(
                        bounds.mayContain(rightAscension: ra, declination: dec),
                        "\(viewport.center) \(viewport.orientation): visible (\(ra), \(dec)) excluded by bounds"
                    )
                }
            }
        }
    }

    @Test func gridIntervalSelectionIsSane() {
        for viewport in makeViewportsForGrid() {
            let raInterval = GridIntervals.raLineInterval(for: viewport)
            let decInterval = GridIntervals.decLineInterval(for: viewport)
            #expect(GridIntervals.raIntervals.contains(raInterval))
            #expect(GridIntervals.decIntervals.contains(decInterval))
            // at least roughly three divisions across the chart vertically
            let heightHundredths =
                viewport.sizeInPoints.height * viewport.degreesPerPoint * 60
                * 60 * 100
            #expect(heightHundredths / Double(decInterval) >= 3.0)
        }
    }

    private func makeViewportsForGrid() -> [ChartViewport] {
        [0.001, 0.01, 0.05, 0.2, 0.5].flatMap { scale in
            [0.0, 1.0, 1.5].map { dec in
                ChartViewport(
                    center: EquatorialCoordinate(
                        rightAscension: Radians(1),
                        declination: Radians(dec)),
                    degreesPerPoint: scale,
                    sizeInPoints: Size2D(width: 1180, height: 820))
            }
        }
    }
}
