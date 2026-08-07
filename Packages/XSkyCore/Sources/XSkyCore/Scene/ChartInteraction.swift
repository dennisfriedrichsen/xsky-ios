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

        var best: EquatorialCoordinate = viewport.center
        var bestError = Double.infinity
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
            if error < bestError {
                bestError = error
                best = center
            }
        }
        return best
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
