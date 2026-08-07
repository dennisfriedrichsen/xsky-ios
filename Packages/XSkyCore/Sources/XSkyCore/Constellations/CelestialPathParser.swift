import Foundation

/// One celestial polyline: a sequence of J2000 positions. `closed` paths
/// (constellation boundaries) implicitly connect the last point back to
/// the first; outlines do not (legacy boundary.c closes, outline.c does
/// not).
public struct CelestialPath: Hashable, Codable, Sendable {
    public var points: [CelestialPoint]
    public var closed: Bool

    public struct CelestialPoint: Hashable, Codable, Sendable {
        public var raRadians: Double
        public var decRadians: Double

        public init(raRadians: Double, decRadians: Double) {
            self.raRadians = raRadians
            self.decRadians = decRadians
        }
    }

    public init(points: [CelestialPoint], closed: Bool) {
        self.points = points
        self.closed = closed
    }
}

/// Parser for the boundary/outline/center data files: one `RA Dec` pair
/// per line (decimal hours at byte 0, signed decimal degrees at byte 11),
/// with `-1` RA records separating paths in the boundary and outline
/// files (legacy fill_bound_entry / fill_outline_entry /
/// fill_center_entry).
public enum CelestialPathParser {
    static let raOffset = 0
    static let decOffset = 11

    public struct Result: Sendable {
        public let paths: [CelestialPath]
        public let vertexCount: Int
        public let sourceRecords: Int
    }

    public static func parsePaths(data: Data, closed: Bool) -> Result {
        var paths: [CelestialPath] = []
        var current: [CelestialPath.CelestialPoint] = []
        var vertexCount = 0
        var sourceRecords = 0

        for rec in RecordSplitter.records(in: data) {
            sourceRecords += 1
            let r = rec.record
            let raValue = r.doubleValue(at: raOffset, length: 10)
            if raValue == -1.0 {
                if !current.isEmpty {
                    paths.append(CelestialPath(points: current, closed: closed))
                    current = []
                }
                continue
            }
            let decValue = r.doubleValue(at: decOffset, length: 11)
            current.append(
                CelestialPath.CelestialPoint(
                    raRadians: Radians(hours: raValue).value,
                    decRadians: Radians(degrees: decValue).value))
            vertexCount += 1
        }
        if !current.isEmpty {
            paths.append(CelestialPath(points: current, closed: closed))
        }
        return Result(
            paths: paths, vertexCount: vertexCount,
            sourceRecords: sourceRecords)
    }

    /// Constellation label/search centers (concenters.dat): 89 positions
    /// in the same order as ConstellationTable.entries.
    public static func parseCenters(data: Data) -> [CelestialPath.CelestialPoint] {
        var centers: [CelestialPath.CelestialPoint] = []
        for rec in RecordSplitter.records(in: data) {
            let r = rec.record
            let raValue = r.doubleValue(at: raOffset, length: 10)
            let decValue = r.doubleValue(at: decOffset, length: 11)
            centers.append(
                CelestialPath.CelestialPoint(
                    raRadians: Radians(hours: raValue).value,
                    decRadians: Radians(degrees: decValue).value))
        }
        return centers
    }
}
