import Foundation

/// Deterministic declination-band index over a catalog's objects. The
/// coarse query returns every object whose declination band intersects
/// the viewport's conservative bounds; it may include extras but never
/// excludes a visible object (RA wrap and poles are handled by the bounds
/// test itself, which is exact in declination and conservative in RA).
public struct SpatialIndex: Sendable {
    /// One-degree declination bands from -90 to +90.
    private static let bandCount = 180
    private let bands: [[Int32]]
    private let objects: [CatalogObject]

    public init(objects: [CatalogObject]) {
        self.objects = objects
        var bands = [[Int32]](repeating: [], count: Self.bandCount)
        for (i, object) in objects.enumerated() {
            bands[Self.band(forDeclination: object.decRadians)]
                .append(Int32(i))
        }
        self.bands = bands
    }

    private static func band(forDeclination dec: Double) -> Int {
        let degrees = dec * Angles.degreesPerRadian
        let raw = Int((degrees + 90).rounded(.down))
        return min(max(raw, 0), bandCount - 1)
    }

    /// Object indexes whose declination band intersects [bottom, top]
    /// radians, in ascending object order.
    public func candidates(
        bottomDec: Double, topDec: Double
    ) -> [Int] {
        let lo = Self.band(forDeclination: bottomDec)
        let hi = Self.band(forDeclination: topDec)
        guard lo <= hi else { return [] }
        var result: [Int] = []
        for band in lo...hi {
            for i in bands[band] {
                result.append(Int(i))
            }
        }
        return result
    }

    /// Candidates that also pass the conservative RA/Dec bounds test.
    public func candidates(in bounds: ViewportBounds) -> [Int] {
        candidates(bottomDec: bounds.bottomDec, topDec: bounds.topDec)
            .filter { i in
                bounds.mayContain(
                    rightAscension: objects[i].raRadians,
                    declination: objects[i].decRadians)
            }
    }
}
