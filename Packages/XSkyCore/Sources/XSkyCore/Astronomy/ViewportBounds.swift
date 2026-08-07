import Foundation

/// Conservative RA/Dec bounds of a viewport, ported from
/// `calculate_limits()` and `within_limits()` in the legacy position.c
/// (originally by Brian Wing). The bounds may include extra sky but never
/// exclude a visible position; exact visibility still requires projecting
/// the candidate.
public struct ViewportBounds: Hashable, Sendable {
    /// Westernmost RA (larger value; RA increases eastward through west
    /// edge of chart). `leftRA >= rightRA` unless 0h crosses the view.
    public var leftRA: Double
    public var rightRA: Double
    public var topDec: Double
    public var bottomDec: Double

    public init(for viewport: ChartViewport) {
        let width = Int(viewport.sizeInPoints.width)
        let height = Int(viewport.sizeInPoints.height)

        // legacy probes deliberately use one-past-the-edge pixel indexes
        let h1: Int
        let h2: Int
        let w1: Int
        let w2: Int
        if viewport.orientation == .downunder {
            h1 = height
            h2 = -1
            w1 = width
            w2 = -1
        } else {
            h1 = -1
            h2 = height
            w1 = -1
            w2 = width
        }

        func floorProject(_ ra: Double, _ dec: Double) -> (x: Int, y: Int) {
            let p = ChartProjection.project(
                rightAscension: ra, declination: dec, in: viewport)
            return (Int(p.x.rounded(.down)), Int(p.y.rounded(.down)))
        }

        func unproject(_ x: Int, _ y: Int) -> EquatorialCoordinate {
            ChartProjection.unproject(
                Point2D(x: Double(x) + 0.5, y: Double(y) + 0.5), in: viewport)
        }

        let northPolePoint = floorProject(0, .pi / 2)
        let northPole =
            northPolePoint.x >= 0 && northPolePoint.x < width
            && northPolePoint.y >= 0 && northPolePoint.y < height

        let southPolePoint = floorProject(0, -.pi / 2)
        let southPole =
            southPolePoint.x >= 0 && southPolePoint.x < width
            && southPolePoint.y >= 0 && southPolePoint.y < height

        if northPole && southPole {
            leftRA = 2 * .pi
            rightRA = 0
            topDec = .pi / 2
            bottomDec = -.pi / 2
        } else if northPole {
            leftRA = 2 * .pi
            rightRA = 0
            topDec = .pi / 2
            let centerBottom = unproject(width / 2, h2).declination.value
            let sideBottom = unproject(0, h2).declination.value
            bottomDec = min(centerBottom + .pi / 2, sideBottom + .pi / 2) - .pi / 2
        } else if southPole {
            leftRA = 2 * .pi
            rightRA = 0
            let centerTop = unproject(width / 2, h1).declination.value
            let sideTop = unproject(0, h1).declination.value
            topDec = max(centerTop + .pi / 2, sideTop + .pi / 2) - .pi / 2
            bottomDec = -.pi / 2
        } else {
            let centerDec = viewport.center.declination.value
            if centerDec > 0 {
                leftRA = unproject(w1, h1).rightAscension.value
                rightRA = unproject(w2, h1).rightAscension.value
            } else {
                leftRA = unproject(w1, h2).rightAscension.value
                rightRA = unproject(w2, h2).rightAscension.value
            }

            let centerTop = unproject(width / 2, h1).declination.value
            let centerBottom = unproject(width / 2, h2).declination.value
            let sideTop = unproject(0, h1).declination.value
            let sideBottom = unproject(0, h2).declination.value

            topDec = max(centerTop + .pi / 2, sideTop + .pi / 2) - .pi / 2
            bottomDec = min(centerBottom + .pi / 2, sideBottom + .pi / 2) - .pi / 2
        }
    }

    /// Quick containment test (legacy `within_limits()`); a true result
    /// still requires an exact projected check.
    public func mayContain(rightAscension ra: Double, declination dec: Double) -> Bool {
        if dec < bottomDec { return false }
        if dec > topDec { return false }

        if leftRA > rightRA {
            // 0h RA not included within the view
            return leftRA >= ra && ra >= rightRA
        } else {
            // 0h RA crosses the view; skip the discontinuity
            return (leftRA >= ra && ra >= 0) || (2 * .pi >= ra && ra >= rightRA)
        }
    }
}

/// Exact visibility: quick bounds test, then projection and viewport
/// containment (legacy `within_display()`).
public struct VisibilityTester: Sendable {
    public let viewport: ChartViewport
    public let bounds: ViewportBounds

    public init(viewport: ChartViewport) {
        self.viewport = viewport
        self.bounds = ViewportBounds(for: viewport)
    }

    /// Returns the projected position when visible, nil when not.
    public func visiblePosition(
        rightAscension ra: Double, declination dec: Double
    ) -> Point2D? {
        guard bounds.mayContain(rightAscension: ra, declination: dec) else {
            return nil
        }
        let p = ChartProjection.project(
            rightAscension: ra, declination: dec, in: viewport)
        guard p.x >= 0, p.x < viewport.sizeInPoints.width,
            p.y >= 0, p.y < viewport.sizeInPoints.height
        else { return nil }
        return p
    }
}
