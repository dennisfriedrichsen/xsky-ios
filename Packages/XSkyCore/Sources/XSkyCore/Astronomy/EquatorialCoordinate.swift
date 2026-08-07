import Foundation

/// A coordinate equinox (e.g. J2000, B1950), stored as a decimal year.
public struct Equinox: Hashable, Codable, Sendable {
    public var year: Double

    public init(year: Double) {
        self.year = year
    }

    /// The common equinox all catalog coordinates are normalized to during
    /// loading (legacy COMMON_EQUINOX).
    public static let j2000 = Equinox(year: 2000.0)
    public static let b1950 = Equinox(year: 1950.0)
    public static let b1875 = Equinox(year: 1875.0)
    public static let epoch1975 = Equinox(year: 1975.0)
}

/// An equatorial position. Invariants: RA is normalized to `[0, 2π)` and
/// declination is limited to `[-π/2, π/2]`; both are always finite.
public struct EquatorialCoordinate: Hashable, Codable, Sendable {
    public var rightAscension: Radians
    public var declination: Radians
    public var equinox: Equinox

    public init(
        rightAscension: Radians,
        declination: Radians,
        equinox: Equinox = .j2000
    ) {
        self.rightAscension = rightAscension.normalizedRightAscension
        var dec = declination.value
        if !dec.isFinite { dec = 0 }
        self.declination = Radians(min(.pi / 2, max(-.pi / 2, dec)))
        self.equinox = equinox
        if !self.rightAscension.value.isFinite {
            self.rightAscension = Radians(0)
        }
    }
}

/// A 2D point in logical chart points. A project-owned type so projection
/// code and tests do not depend on CoreGraphics.
public struct Point2D: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A 2D size in logical chart points.
public struct Size2D: Hashable, Codable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}
