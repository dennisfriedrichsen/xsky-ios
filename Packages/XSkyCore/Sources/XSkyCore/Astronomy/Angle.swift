import Foundation

/// An angle in radians. The core stores every internal angle as radians in
/// a `Double`; this wrapper keeps radians from being confused with degrees,
/// hours, or screen points at API boundaries.
public struct Radians: Hashable, Codable, Sendable, Comparable {
    public var value: Double

    public init(_ value: Double) {
        self.value = value
    }

    public init(degrees: Double) {
        self.value = degrees / Angles.degreesPerRadian
    }

    public init(hours: Double) {
        self.value = hours * Angles.degreesPerHour / Angles.degreesPerRadian
    }

    public var degrees: Double { value * Angles.degreesPerRadian }
    public var hours: Double { degrees / Angles.degreesPerHour }

    public var isFinite: Bool { value.isFinite }

    /// This angle normalized to `[0, 2π)`, the invariant for right
    /// ascension after any operation that can wrap.
    public var normalizedRightAscension: Radians {
        var v = value.truncatingRemainder(dividingBy: 2 * .pi)
        if v < 0 { v += 2 * .pi }
        if v >= 2 * .pi { v = 0 }
        return Radians(v)
    }

    public static func < (lhs: Radians, rhs: Radians) -> Bool {
        lhs.value < rhs.value
    }

    public static func + (lhs: Radians, rhs: Radians) -> Radians {
        Radians(lhs.value + rhs.value)
    }

    public static func - (lhs: Radians, rhs: Radians) -> Radians {
        Radians(lhs.value - rhs.value)
    }

    public static prefix func - (operand: Radians) -> Radians {
        Radians(-operand.value)
    }
}

/// Shared angle conversion constants, mirroring the legacy pos.h macros.
public enum Angles {
    public static let degreesPerRadian = 360.0 / (2 * Double.pi)
    public static let degreesPerHour = 15.0

    public static func arcsecondsToRadians(_ arcseconds: Double) -> Double {
        (arcseconds / 60 / 60) / degreesPerRadian
    }

    /// Clamp an inverse-trigonometric input to `[-1, 1]`. The legacy code
    /// clamped only on SPARC; the port clamps universally.
    public static func clampUnit(_ value: Double) -> Double {
        min(1.0, max(-1.0, value))
    }
}
