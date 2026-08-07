import Foundation

/// IAU 1976 precession between mean equinoxes, ported from
/// `init_precess()` / `precess()` in the legacy position.c (constants from
/// PRECESS.BAS by PC Leyland). The rotation matrix belongs to the
/// transform instance rather than to a global, so transforms for different
/// epoch pairs can coexist.
public struct PrecessionTransform: Sendable {
    private let rotation: [[Double]]
    public let source: Equinox
    public let destination: Equinox

    public init(from source: Equinox, to destination: Equinox) {
        self.source = source
        self.destination = destination

        let t0 = (source.year - 1900.0) / 100
        let newT = (destination.year - 1900.0) / 100
        let dt = newT - t0

        let c1 = 2306.2181, c2 = 1.39656, c3 = -0.000139
        let c4 = 0.30188, c5 = -0.000345, c6 = 0.017998
        let c7 = 0.7928, c8 = 0.000411, c9 = 0.000205
        let c10 = 2004.3109, c11 = -0.8533, c12 = -0.000217
        let c13 = -0.42665, c14 = -0.000217, c15 = -0.041833

        var zeta = ((c1 + (c2 + c3 * t0) * t0) + ((c4 + c5 * t0) + c6 * dt) * dt) * dt
        var z = zeta + ((c7 + c8 * t0) + c9 * dt) * dt * dt
        var theta = ((c10 + (c11 + c12 * t0) * t0) + ((c13 + c14 * t0) + c15 * dt) * dt) * dt

        zeta = Angles.arcsecondsToRadians(zeta)
        z = Angles.arcsecondsToRadians(z)
        theta = Angles.arcsecondsToRadians(theta)

        let cs1 = cos(z), cs2 = cos(theta), cs3 = cos(zeta)
        let sn1 = sin(z), sn2 = sin(theta), sn3 = sin(zeta)

        rotation = [
            [
                -sn1 * sn3 + cs1 * cs2 * cs3,
                -sn1 * cs3 - cs1 * cs2 * sn3,
                -cs1 * sn2,
            ],
            [
                cs1 * sn3 + sn1 * cs2 * cs3,
                cs1 * cs3 - sn1 * cs2 * sn3,
                -sn1 * sn2,
            ],
            [
                sn2 * cs3,
                -sn2 * sn3,
                cs2,
            ],
        ]
    }

    /// Precess a position; the result carries the destination equinox.
    public func apply(to coordinate: EquatorialCoordinate) -> EquatorialCoordinate {
        let (ra, dec) = apply(
            rightAscension: coordinate.rightAscension.value,
            declination: coordinate.declination.value)
        return EquatorialCoordinate(
            rightAscension: Radians(ra),
            declination: Radians(dec),
            equinox: destination)
    }

    /// Raw radian variant used by parsers on hot loading paths.
    public func apply(rightAscension alpha: Double, declination delta: Double)
        -> (rightAscension: Double, declination: Double)
    {
        let d0 = [
            cos(delta) * cos(alpha),
            cos(delta) * sin(alpha),
            sin(delta),
        ]
        var d1 = [0.0, 0.0, 0.0]
        for i in 0..<3 {
            for j in 0..<3 {
                d1[i] += rotation[i][j] * d0[j]
            }
        }
        let newDelta = asin(Angles.clampUnit(d1[2]))
        var newAlpha = atan2(d1[1], d1[0])
        if newAlpha < 0 { newAlpha += 2 * .pi }
        return (newAlpha, newDelta)
    }
}

/// Herget precession (Publ. Cincinnati Obs. no. 24), ported from the
/// routines in the legacy boundary.c. Used exclusively to bring J2000
/// positions to B1875 for Roman-table constellation identification; it is
/// deliberately distinct from the IAU 1976 transform.
public struct HergetPrecessionTransform: Sendable {
    private let rotation: [[Double]]

    public init(from epoch1: Equinox = .j2000, to epoch2: Equinox = .b1875) {
        let csr = (2 * Double.pi / 360) / 3600
        let t = 0.001 * (epoch2.year - epoch1.year)
        let st = 0.001 * (epoch1.year - 1900)
        let a = csr * t * (23042.53 + st * (139.75 + 0.06 * st) + t * (30.23 - 0.27 * st + 18.0 * t))
        let b = csr * t * t * (79.27 + 0.66 * st + 0.32 * t) + a
        let c = csr * t * (20046.85 - st * (85.33 + 0.37 * st) + t * (-42.67 - 0.37 * st - 41.8 * t))

        let sina = sin(a), sinb = sin(b), sinc = sin(c)
        let cosa = cos(a), cosb = cos(b), cosc = cos(c)

        rotation = [
            [
                cosa * cosb * cosc - sina * sinb,
                -cosa * sinb - sina * cosb * cosc,
                -cosb * sinc,
            ],
            [
                sina * cosb + cosa * sinb * cosc,
                cosa * cosb - sina * sinb * cosc,
                -sinb * sinc,
            ],
            [
                cosa * sinc,
                -sina * sinc,
                cosc,
            ],
        ]
    }

    public func apply(rightAscension ra1: Double, declination dec1: Double)
        -> (rightAscension: Double, declination: Double)
    {
        let a = cos(dec1)
        let x1 = [a * cos(ra1), a * sin(ra1), sin(dec1)]
        var x2 = [0.0, 0.0, 0.0]
        for i in 0..<3 {
            for j in 0..<3 {
                x2[i] += rotation[i][j] * x1[j]
            }
        }
        var ra2 = atan2(x2[1], x2[0])
        if ra2 < 0 { ra2 += 2 * .pi }
        return (ra2, asin(Angles.clampUnit(x2[2])))
    }
}
