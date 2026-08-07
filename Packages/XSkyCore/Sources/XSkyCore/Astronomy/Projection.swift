import Foundation

/// The active chart projection: an azimuthal equidistant projection ported
/// from the `MEEUS` branch of `pos_rad_to_X_double()` / `X_to_pos_rad()`
/// in the legacy position.c (equations 12.5/12.6 and p. 89 of Meeus,
/// Astronomical Algorithms). The chart center plays the role of the
/// zenith: radial screen distance is proportional to angular separation
/// from the center.
public enum ChartProjection {

    /// Forward projection of an equatorial position to chart points.
    /// Coordinates stay `Double`; the legacy pixel flooring is left to
    /// raster-specific boundaries that actually need it.
    public static func project(
        rightAscension raRad: Double,
        declination decRad: Double,
        in viewport: ChartViewport
    ) -> Point2D {
        let centerRA = viewport.center.rightAscension.value
        let centerDec = viewport.center.declination.value

        let sinH =
            sin(centerDec) * sin(decRad)
            + cos(centerDec) * cos(decRad) * cos(centerRA - raRad)

        let z = Double.pi / 2 - asin(Angles.clampUnit(sinH))

        let numerator = sin(centerRA - raRad)
        let denominator =
            cos(centerRA - raRad) * sin(centerDec)
            - tan(decRad) * cos(centerDec)

        var xDist = 0.0
        var yDist = 0.0
        if numerator != 0 || denominator != 0 {
            let a = atan2(numerator, denominator)
            xDist = (z * sin(a)) * Angles.degreesPerRadian / viewport.degreesPerPoint
            yDist = (z * cos(a)) * Angles.degreesPerRadian / viewport.degreesPerPoint
        }

        let halfWidth = viewport.sizeInPoints.width / 2
        let halfHeight = viewport.sizeInPoints.height / 2
        switch viewport.orientation {
        case .normal:
            return Point2D(x: halfWidth + xDist, y: halfHeight + yDist)
        case .downunder:
            return Point2D(x: halfWidth - xDist, y: halfHeight - yDist)
        }
    }

    public static func project(
        _ coordinate: EquatorialCoordinate, in viewport: ChartViewport
    ) -> Point2D {
        project(
            rightAscension: coordinate.rightAscension.value,
            declination: coordinate.declination.value,
            in: viewport)
    }

    /// Inverse projection of a chart point back to RA/Dec. The legacy
    /// routine took integer pixels and sampled their centers (`x + 0.5`);
    /// this port takes the exact point, so the legacy pixel (x, y)
    /// corresponds to `Point2D(x + 0.5, y + 0.5)`.
    public static func unproject(
        _ point: Point2D, in viewport: ChartViewport
    ) -> EquatorialCoordinate {
        let centerRA = viewport.center.rightAscension.value
        let centerDec = viewport.center.declination.value

        var xx: Double
        var yy: Double
        switch viewport.orientation {
        case .normal:
            xx = point.x - viewport.sizeInPoints.width / 2
            yy = -(point.y - viewport.sizeInPoints.height / 2)
        case .downunder:
            xx = -(point.x - viewport.sizeInPoints.width / 2)
            yy = point.y - viewport.sizeInPoints.height / 2
        }

        if xx == 0, yy == 0 {
            return viewport.center
        }

        let r = (xx * xx + yy * yy).squareRoot()
        var theta = acos(Angles.clampUnit(yy / r))

        var rAngle = (r * viewport.degreesPerPoint) / Angles.degreesPerRadian

        if xx < 0 { theta = -theta }
        theta = .pi - theta

        rAngle = .pi / 2 - rAngle

        let h = atan2(
            sin(theta),
            cos(theta) * sin(centerDec) + tan(rAngle) * cos(centerDec))

        let sinDec =
            sin(centerDec) * sin(rAngle)
            - cos(centerDec) * cos(rAngle) * cos(theta)
        let dec = asin(Angles.clampUnit(sinDec))

        var ra = centerRA - h
        if ra < 0 { ra += 2 * .pi }
        if ra >= 2 * .pi { ra -= 2 * .pi }

        return EquatorialCoordinate(
            rightAscension: Radians(ra), declination: Radians(dec),
            equinox: viewport.center.equinox)
    }

    /// Angular separation between two positions in radians (spherical law
    /// of cosines, as used throughout the legacy code).
    public static func angularSeparation(
        _ a: EquatorialCoordinate, _ b: EquatorialCoordinate
    ) -> Radians {
        let cosd =
            sin(a.declination.value) * sin(b.declination.value)
            + cos(a.declination.value) * cos(b.declination.value)
                * cos(a.rightAscension.value - b.rightAscension.value)
        return Radians(acos(Angles.clampUnit(cosd)))
    }
}
