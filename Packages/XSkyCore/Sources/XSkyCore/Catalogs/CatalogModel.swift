import Foundation

/// Stable identifier for a catalog.
public struct CatalogID: Hashable, Codable, Sendable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let ybs = CatalogID(rawValue: "YBS")
    public static let rngc = CatalogID(rawValue: "RNGC")
    public static let qso = CatalogID(rawValue: "QSO")
    /// Imported legacy user catalogs get unique IDs, e.g. "USER-<uuid>".
    public static func user(_ token: String) -> CatalogID {
        CatalogID(rawValue: "USER-\(token)")
    }

    public var isUserCatalog: Bool { rawValue.hasPrefix("USER") }
}

/// Stable identity of an object: its catalog plus the record index within
/// the parsed catalog.
public struct CatalogObjectID: Hashable, Codable, Sendable {
    public var catalog: CatalogID
    public var record: Int

    public init(catalog: CatalogID, record: Int) {
        self.catalog = catalog
        self.record = record
    }
}

/// Non-stellar object kinds, mapped from the legacy RNGC type codes plus
/// star/quasar/user kinds. The kind determines the chart symbol.
public enum ObjectKind: String, Hashable, Codable, Sendable, CaseIterable {
    case star
    case openCluster
    case globularCluster
    case diffuseNebula
    case planetaryNebula
    case clusterWithNebulosity
    case galaxy
    case quasar
    case userObject
    case lmcObject
    case smcObject
    case unverified
    case nonexistent
    case unknown
}

/// Spectral color families for stars (legacy StarColor). W groups with O;
/// C/N/S-like cool classes group with M; unknown classes render neutral.
public enum SpectralColorClass: String, Hashable, Codable, Sendable, CaseIterable {
    case o, b, a, f, g, k, m
    case neutral

    /// Legacy mapping from the spectral-class byte in a YBS record.
    public init(spectrumByte: UInt8) {
        switch spectrumByte {
        case UInt8(ascii: "W"), UInt8(ascii: "O"): self = .o
        case UInt8(ascii: "B"): self = .b
        case UInt8(ascii: "A"): self = .a
        case UInt8(ascii: "F"): self = .f
        case UInt8(ascii: "G"): self = .g
        case UInt8(ascii: "K"): self = .k
        case UInt8(ascii: "M"), UInt8(ascii: "C"), UInt8(ascii: "N"),
            UInt8(ascii: "S"):
            self = .m
        default: self = .neutral
        }
    }
}

/// Catalog-specific identity fields used for labels and search.
public enum ObjectIdentity: Hashable, Codable, Sendable {
    case ybs(
        hr: Int, bayerIndex: Int?, bayerSuperscript: Int?, flamsteed: Int?,
        constellationIndex: Int?)
    case rngc(number: Int, subletter: String?, messier: Int?)
    case qso(raDesignation: Int, decDesignation: Int)
    case user(number: Int, label: String)
}

/// One normalized catalog object. Positions are J2000 radians stored as
/// raw doubles for hot projection loops; `coordinate` provides the typed
/// view. Unknown magnitude is nil, never the legacy 99.99 sentinel.
public struct CatalogObject: Hashable, Codable, Sendable, Identifiable {
    public let id: CatalogObjectID
    public let raRadians: Double
    public let decRadians: Double
    public let magnitude: Double?
    public let kind: ObjectKind
    public let spectralClass: SpectralColorClass?
    public let identity: ObjectIdentity
    /// Byte range of the source record in the catalog file, for detail
    /// display.
    public let recordByteRange: Range<Int>?

    public var coordinate: EquatorialCoordinate {
        EquatorialCoordinate(
            rightAscension: Radians(raRadians),
            declination: Radians(decRadians))
    }

    public var isStellar: Bool { kind == .star }

    /// Nonexistent or unverified per the source catalog.
    public var isNonexistentOrUnverified: Bool {
        kind == .nonexistent || kind == .unverified
    }

    public init(
        id: CatalogObjectID,
        raRadians: Double,
        decRadians: Double,
        magnitude: Double?,
        kind: ObjectKind,
        spectralClass: SpectralColorClass?,
        identity: ObjectIdentity,
        recordByteRange: Range<Int>?
    ) {
        self.id = id
        self.raRadians = raRadians
        self.decRadians = decRadians
        self.magnitude = magnitude
        self.kind = kind
        self.spectralClass = spectralClass
        self.identity = identity
        self.recordByteRange = recordByteRange
    }
}

/// Loading diagnostics: every skipped source record is counted by reason.
public struct CatalogDiagnostics: Hashable, Codable, Sendable {
    public var sourceRecords: Int
    public var loadedObjects: Int
    public var skipped: [String: Int]
    public var notes: [String]

    public init(
        sourceRecords: Int = 0, loadedObjects: Int = 0,
        skipped: [String: Int] = [:], notes: [String] = []
    ) {
        self.sourceRecords = sourceRecords
        self.loadedObjects = loadedObjects
        self.skipped = skipped
        self.notes = notes
    }

    public mutating func skip(_ reason: String) {
        skipped[reason, default: 0] += 1
    }
}

/// A fully parsed catalog: immutable objects plus the raw file bytes kept
/// for detail formatting.
public struct LoadedCatalog: Sendable {
    public let id: CatalogID
    public let displayName: String
    public let shortName: String
    public let objects: [CatalogObject]
    public let diagnostics: CatalogDiagnostics
    public let rawData: Data

    public init(
        id: CatalogID, displayName: String, shortName: String,
        objects: [CatalogObject], diagnostics: CatalogDiagnostics,
        rawData: Data
    ) {
        self.id = id
        self.displayName = displayName
        self.shortName = shortName
        self.objects = objects
        self.diagnostics = diagnostics
        self.rawData = rawData
    }

    /// The raw source record for an object, as trimmed ASCII text.
    public func rawRecord(for object: CatalogObject) -> String? {
        guard let range = object.recordByteRange,
            range.upperBound <= rawData.count
        else { return nil }
        return String(decoding: rawData[range], as: UTF8.self)
            .trimmingCharacters(in: .newlines)
    }
}

/// Errors surfaced by catalog parsing. Field-level tolerance is preferred;
/// these are for structurally unusable inputs.
public struct CatalogParseError: Error, Sendable, CustomStringConvertible {
    public let catalog: CatalogID
    public let recordNumber: Int?
    public let message: String
    public let excerpt: String?

    public init(
        catalog: CatalogID, recordNumber: Int? = nil, message: String,
        excerpt: String? = nil
    ) {
        self.catalog = catalog
        self.recordNumber = recordNumber
        self.message = message
        self.excerpt = excerpt.map { String($0.prefix(60)) }
    }

    public var description: String {
        var s = "\(catalog.rawValue): \(message)"
        if let n = recordNumber { s += " (record \(n))" }
        if let e = excerpt { s += " near \"\(e)\"" }
        return s
    }
}
