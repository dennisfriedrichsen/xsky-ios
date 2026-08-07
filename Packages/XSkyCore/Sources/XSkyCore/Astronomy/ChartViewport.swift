import Foundation

/// Chart orientation. Normal charts have north up with right ascension
/// increasing toward the left; downunder rotates the chart 180 degrees.
public enum ChartOrientation: String, Hashable, Codable, Sendable {
    case normal
    case downunder
}

/// The visible chart: center, scale, logical size, and orientation.
/// Scale is degrees of sky per logical point (legacy `display->scale`,
/// which was degrees per pixel).
public struct ChartViewport: Hashable, Codable, Sendable {
    public var center: EquatorialCoordinate
    public var degreesPerPoint: Double
    public var sizeInPoints: Size2D
    public var orientation: ChartOrientation

    /// Documented scale limits: from 2 arcseconds per point (extreme
    /// close-up) to a full-sky 0.5 degrees per point.
    public static let minimumDegreesPerPoint = 2.0 / 3600.0
    public static let maximumDegreesPerPoint = 0.5

    public init(
        center: EquatorialCoordinate,
        degreesPerPoint: Double,
        sizeInPoints: Size2D,
        orientation: ChartOrientation = .normal
    ) {
        self.center = center
        var scale = degreesPerPoint
        if !scale.isFinite || scale <= 0 {
            scale = ChartViewport.maximumDegreesPerPoint
        }
        self.degreesPerPoint = min(
            max(scale, ChartViewport.minimumDegreesPerPoint),
            ChartViewport.maximumDegreesPerPoint)
        self.sizeInPoints = sizeInPoints
        self.orientation = orientation
    }

    /// The initial chart from the legacy defaults: centered near the Orion
    /// nebula at 15 degrees per 300 points.
    public static func initialViewport(size: Size2D) -> ChartViewport {
        ChartViewport(
            center: EquatorialCoordinate(
                rightAscension: SexagesimalRA(
                    hours: 5, minutes: 36, seconds: 12, thousandths: 700
                ).radians,
                declination: SexagesimalDec(
                    sign: -1, degrees: 1, minutes: 12, seconds: 7, hundredths: 0
                ).radians),
            degreesPerPoint: 15.0 / 300.0,
            sizeInPoints: size)
    }
}
