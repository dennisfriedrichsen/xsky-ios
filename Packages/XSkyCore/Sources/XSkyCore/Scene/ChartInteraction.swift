import Foundation

/// Interaction geometry: hit testing, sky-anchored panning, anchored
/// zooming, and region zoom. All spherical; no flat RA/Dec pan
/// approximations (stable at the poles and across 0h RA).
public enum ChartInteraction {

    /// Nearest eligible visible object to a screen point within the hit
    /// radius. Non-stellar objects win over coincident stars, matching
    /// the legacy find_object() catalog ordering.
    public static func hitTest(
        at point: Point2D, snapshot: RenderSnapshot, radius: Double = 14
    ) -> CatalogObjectID? {
        let r2 = radius * radius

        func nearest<T>(
            _ items: [T], position: (T) -> Point2D, id: (T) -> CatalogObjectID
        ) -> (CatalogObjectID, Double)? {
            var best: (CatalogObjectID, Double)?
            for item in items {
                let p = position(item)
                let dx = p.x - point.x
                let dy = p.y - point.y
                let d2 = dx * dx + dy * dy
                if d2 <= r2, d2 < (best?.1 ?? .infinity) {
                    best = (id(item), d2)
                }
            }
            return best
        }

        if let hit = nearest(
            snapshot.objects, position: \.position, id: \.objectID)
        {
            return hit.0
        }
        return nearest(snapshot.stars, position: \.position, id: \.objectID)?.0
    }

    /// The viewport center that keeps `anchor` (a sky position captured at
    /// gesture start) under the screen point `target`. Solved in closed
    /// form by inverting the legacy inverse-projection equations: the
    /// screen point fixes the polar coordinates (r, theta) of the anchor
    /// relative to the unknown center, giving
    /// `sin(decA) = sin(decC)sin(rAngle) - cos(decC)cos(rAngle)cos(theta)`
    /// which is solvable for the center declination; the hour angle then
    /// fixes the center RA. Stable at the poles and across 0h RA.
    public static func centerKeeping(
        anchor: EquatorialCoordinate,
        under target: Point2D,
        in viewport: ChartViewport
    ) -> EquatorialCoordinate {
        var xx: Double
        var yy: Double
        switch viewport.orientation {
        case .normal:
            xx = target.x - viewport.sizeInPoints.width / 2
            yy = -(target.y - viewport.sizeInPoints.height / 2)
        case .downunder:
            xx = -(target.x - viewport.sizeInPoints.width / 2)
            yy = target.y - viewport.sizeInPoints.height / 2
        }

        if xx == 0, yy == 0 { return anchor }

        let r = (xx * xx + yy * yy).squareRoot()
        var theta = acos(Angles.clampUnit(yy / r))
        if xx < 0 { theta = -theta }
        theta = .pi - theta

        let rAngle =
            .pi / 2 - (r * viewport.degreesPerPoint) / Angles.degreesPerRadian

        let decA = anchor.declination.value
        let m = (
            sin(rAngle) * sin(rAngle)
                + cos(rAngle) * cos(theta) * cos(rAngle) * cos(theta)
        ).squareRoot()
        guard m > 1e-15 else { return anchor }
        let phi = atan2(-cos(rAngle) * cos(theta), sin(rAngle))
        let x = Angles.clampUnit(sin(decA) / m)

        // Near a pole both candidates can be exact: one keeps the center
        // on its side of the pole, the other carries it across, which on
        // a north-up chart redraws everything rotated 180 degrees. Measure
        // how far each candidate turns the chart (the screen direction
        // between two sky points now on the vertical through the center)
        // and reject large turns, preferring the smaller turn among
        // equally good fits. A drag with no unturned solution then clamps
        // at the pole instead of flipping. A flip turns ~180 degrees; a
        // genuine large step near a pole can legitimately turn the chart
        // well past 45
        let maxTurn = 3 * Double.pi / 4
        let exactTolerance = 0.25  // squared points
        var best: EquatorialCoordinate = viewport.center
        var bestError = Double.infinity
        var bestTurn = Double.infinity
        for candidate in [asin(x) - phi, .pi - asin(x) - phi] {
            var decC = candidate
            // fold into the valid declination range; infeasible drags
            // (pulling a polar anchor past the pole) clamp to the pole,
            // giving graceful best-effort sliding
            if decC > .pi { decC -= 2 * .pi }
            if decC < -.pi { decC += 2 * .pi }
            decC = min(max(decC, -.pi / 2), .pi / 2)

            let h = atan2(
                sin(theta),
                cos(theta) * sin(decC) + tan(rAngle) * cos(decC))
            let center = EquatorialCoordinate(
                rightAscension: Radians(anchor.rightAscension.value + h),
                declination: Radians(decC),
                equinox: anchor.equinox)

            var vp = viewport
            vp.center = center
            let p = ChartProjection.project(anchor, in: vp)
            let dx = p.x - target.x
            let dy = p.y - target.y
            let error = dx * dx + dy * dy
            let turned = turn(from: viewport, to: vp)
            if turned > maxTurn { continue }
            let bothExact =
                error <= exactTolerance && bestError <= exactTolerance
            if bothExact ? turned < bestTurn : error < bestError {
                bestError = error
                bestTurn = turned
                best = center
            }
        }
        return best
    }

    /// One frame of a drag from `start` to `end`: the sky point under
    /// `start` follows the finger. Solved frame to frame rather than from
    /// a point fixed at gesture start, so a drag that hits a pole can stop
    /// there without the original grab point dragging the chart around.
    ///
    /// Once the center sits on a pole it cannot go further: a north-up
    /// chart there can only turn about the pole. Horizontal motion turns
    /// it, as if grabbing the sky beside the pole; vertical motion either
    /// pulls the pole away from the center or is ignored. A step that
    /// would swing the chart around a pole the center only just misses
    /// lands on the pole instead.
    public static func panned(
        _ viewport: ChartViewport, from start: Point2D, to end: Point2D
    ) -> ChartViewport {
        if isOnPole(viewport.center) {
            let turned = turnedAboutPole(viewport, from: start, to: end)
            let dy = end.y - start.y
            guard dy != 0 else { return turned }
            var away = turned
            away.center = centerKeeping(
                anchor: ChartProjection.unproject(start, in: turned),
                under: Point2D(x: start.x, y: end.y), in: turned)
            // pulling the pole away moves it with the finger; anything
            // else would only spin the chart about it
            let pole = ChartProjection.project(
                EquatorialCoordinate(
                    rightAscension: Radians(0),
                    declination: viewport.center.declination),
                in: away)
            let poleShift = hypot(
                pole.x - viewport.sizeInPoints.width / 2,
                pole.y - viewport.sizeInPoints.height / 2)
            return poleShift >= abs(dy) / 2 ? away : turned
        }

        var vp = viewport
        vp.center = centerKeeping(
            anchor: ChartProjection.unproject(start, in: viewport),
            under: end, in: viewport)
        guard
            isOnPole(vp.center)
                || turn(from: viewport, to: vp) > maxPanStepTurn
        else { return vp }
        vp.center = EquatorialCoordinate(
            rightAscension: viewport.center.rightAscension,
            declination: Radians(
                vp.center.declination.value > 0 ? .pi / 2 : -.pi / 2),
            equinox: viewport.center.equinox)
        return turnedAboutPole(vp, from: start, to: end)
    }

    private static func isOnPole(_ center: EquatorialCoordinate) -> Bool {
        abs(center.declination.value) >= .pi / 2 - 1e-9
    }

    /// Turn a pole-centered chart by the horizontal part of a drag:
    /// the sky at the finger's height moves with it, but never so near
    /// the pole that a small drag spins the chart.
    private static func turnedAboutPole(
        _ viewport: ChartViewport, from start: Point2D, to end: Point2D
    ) -> ChartViewport {
        let halfWidth = viewport.sizeInPoints.width / 2
        let halfHeight = viewport.sizeInPoints.height / 2
        let height = start.y - halfHeight
        let radius = max(abs(height), min(halfWidth, halfHeight) / 2, 1)
        let side: Double = height >= 0 ? 1 : -1
        let angle = (end.x - start.x) * side / radius
        let north = viewport.center.declination.value > 0
        var vp = viewport
        vp.center = EquatorialCoordinate(
            rightAscension: Radians(
                viewport.center.rightAscension.value
                    + (north ? angle : -angle)),
            declination: viewport.center.declination,
            equinox: viewport.center.equinox)
        return vp
    }

    /// The largest turn one pan step may make before it counts as
    /// swinging around a pole.
    static let maxPanStepTurn = 30 * Double.pi / 180

    /// How far the chart turns between two viewports: the screen
    /// direction, in `to`, between two sky points that lay on the
    /// vertical through the center in `from`.
    static func turn(from: ChartViewport, to: ChartViewport) -> Double {
        let halfWidth = from.sizeInPoints.width / 2
        let halfHeight = from.sizeInPoints.height / 2
        let referenceOffset = max(min(halfWidth, halfHeight) / 2, 1)
        let referenceA = ChartProjection.unproject(
            Point2D(x: halfWidth, y: halfHeight), in: from)
        let referenceB = ChartProjection.unproject(
            Point2D(x: halfWidth, y: halfHeight - referenceOffset),
            in: from)
        let a = ChartProjection.project(referenceA, in: to)
        let b = ChartProjection.project(referenceB, in: to)
        return abs(atan2(b.x - a.x, a.y - b.y))
    }

    /// Zoom by a scale factor anchored at a screen point: the sky position
    /// under the anchor stays under it after the scale change.
    public static func zoomedViewport(
        _ viewport: ChartViewport, scaleFactor: Double, anchor: Point2D
    ) -> ChartViewport {
        let sky = ChartProjection.unproject(anchor, in: viewport)
        var vp = viewport
        vp.degreesPerPoint = min(
            max(
                viewport.degreesPerPoint * scaleFactor,
                ChartViewport.minimumDegreesPerPoint),
            ChartViewport.maximumDegreesPerPoint)
        vp.center = centerKeeping(anchor: sky, under: anchor, in: vp)
        return vp
    }

    /// Region zoom (legacy change_scale): center on the marquee center and
    /// expand so the selected region fills the viewport, preserving the
    /// viewport aspect ratio.
    public static func regionZoomedViewport(
        _ viewport: ChartViewport, regionOrigin: Point2D, regionSize: Size2D
    ) -> ChartViewport {
        guard regionSize.width > 4, regionSize.height > 4 else {
            return viewport
        }
        let regionCenter = Point2D(
            x: regionOrigin.x + regionSize.width / 2,
            y: regionOrigin.y + regionSize.height / 2)
        let sky = ChartProjection.unproject(regionCenter, in: viewport)
        let expansion = min(
            viewport.sizeInPoints.width / regionSize.width,
            viewport.sizeInPoints.height / regionSize.height)
        var vp = viewport
        vp.degreesPerPoint = min(
            max(
                viewport.degreesPerPoint / expansion,
                ChartViewport.minimumDegreesPerPoint),
            ChartViewport.maximumDegreesPerPoint)
        vp.center = sky
        return vp
    }

    /// The legacy zoom-step factors: one step changes scale by 20%.
    public static let zoomInStepFactor = 0.8
    public static let zoomOutStepFactor = 1.25

    // MARK: sphere rotation

    /// Rotate `coordinate` by the rotation taking `from` to `to` along
    /// their great circle (Rodrigues' formula).
    private static func rotate(
        _ coordinate: EquatorialCoordinate,
        from: EquatorialCoordinate,
        to: EquatorialCoordinate
    ) -> EquatorialCoordinate {
        let a = unitVector(from)
        let b = unitVector(to)
        let axis = cross(a, b)
        let axisLength = length(axis)
        let angle = atan2(axisLength, dot(a, b))
        guard axisLength > 1e-15 else { return coordinate }
        let k = (
            axis.0 / axisLength, axis.1 / axisLength, axis.2 / axisLength
        )
        let v = unitVector(coordinate)
        let cosA = cos(angle)
        let sinA = sin(angle)
        let kxv = cross(k, v)
        let kdv = dot(k, v)
        let rotated = (
            v.0 * cosA + kxv.0 * sinA + k.0 * kdv * (1 - cosA),
            v.1 * cosA + kxv.1 * sinA + k.1 * kdv * (1 - cosA),
            v.2 * cosA + kxv.2 * sinA + k.2 * kdv * (1 - cosA)
        )
        var ra = atan2(rotated.1, rotated.0)
        if ra < 0 { ra += 2 * .pi }
        let dec = asin(Angles.clampUnit(rotated.2))
        return EquatorialCoordinate(
            rightAscension: Radians(ra), declination: Radians(dec),
            equinox: coordinate.equinox)
    }

    private static func unitVector(
        _ c: EquatorialCoordinate
    ) -> (Double, Double, Double) {
        let cosDec = cos(c.declination.value)
        return (
            cosDec * cos(c.rightAscension.value),
            cosDec * sin(c.rightAscension.value),
            sin(c.declination.value)
        )
    }

    private static func cross(
        _ a: (Double, Double, Double), _ b: (Double, Double, Double)
    ) -> (Double, Double, Double) {
        (
            a.1 * b.2 - a.2 * b.1,
            a.2 * b.0 - a.0 * b.2,
            a.0 * b.1 - a.1 * b.0
        )
    }

    private static func dot(
        _ a: (Double, Double, Double), _ b: (Double, Double, Double)
    ) -> Double {
        a.0 * b.0 + a.1 * b.1 + a.2 * b.2
    }

    private static func length(_ a: (Double, Double, Double)) -> Double {
        (a.0 * a.0 + a.1 * a.1 + a.2 * a.2).squareRoot()
    }
}
