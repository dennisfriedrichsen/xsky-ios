import Foundation

/// User-controlled chart content settings consumed by the scene builder.
/// Display styling (color/night mode) stays in the app's renderer style.
public struct ChartSettings: Hashable, Codable, Sendable {
    /// Catalog visibility; absent means the catalog default.
    public var catalogVisibility: [String: Bool]

    public var showGrid: Bool
    public var showBoundaries: Bool
    public var showOutlines: Bool
    public var showObjectLabels: Bool
    public var showStarLabels: Bool
    public var showConstellationLabels: Bool

    /// Stellar limiting magnitude (legacy mag1_limit, default 8.0).
    public var stellarLimitingMagnitude: Double
    /// Non-stellar limiting magnitude (legacy mag3_limit, default 12.0).
    public var nonstellarLimitingMagnitude: Double
    /// Magnitude mapped to the maximum star size (legacy mag2_limit,
    /// default Sirius at -1.46).
    public var maximumSizeMagnitude: Double
    /// Show objects whose magnitude is unknown.
    public var showUnknownMagnitude: Bool
    /// Show catalog-marked nonexistent/unverified objects.
    public var showNonexistentObjects: Bool

    /// Maximum star diameter in points (legacy DEFAULT_MAXSTARSIZE,
    /// scaled up slightly for Retina legibility without changing the
    /// relative ordering).
    public var maximumStarDiameter: Double
    /// Non-stellar symbol size in points (legacy DEFAULT_OBJSIZE).
    public var objectSymbolSize: Double

    public init(
        catalogVisibility: [String: Bool] = [
            CatalogID.ybs.rawValue: true,
            CatalogID.rngc.rawValue: true,
            CatalogID.qso.rawValue: false,
        ],
        showGrid: Bool = true,
        showBoundaries: Bool = false,
        showOutlines: Bool = false,
        showObjectLabels: Bool = true,
        showStarLabels: Bool = true,
        showConstellationLabels: Bool = true,
        stellarLimitingMagnitude: Double = 8.0,
        nonstellarLimitingMagnitude: Double = 12.0,
        maximumSizeMagnitude: Double = -1.46,
        showUnknownMagnitude: Bool = true,
        showNonexistentObjects: Bool = true,
        maximumStarDiameter: Double = 10,
        objectSymbolSize: Double = 7
    ) {
        self.catalogVisibility = catalogVisibility
        self.showGrid = showGrid
        self.showBoundaries = showBoundaries
        self.showOutlines = showOutlines
        self.showObjectLabels = showObjectLabels
        self.showStarLabels = showStarLabels
        self.showConstellationLabels = showConstellationLabels
        self.stellarLimitingMagnitude = stellarLimitingMagnitude
        self.nonstellarLimitingMagnitude = nonstellarLimitingMagnitude
        self.maximumSizeMagnitude = maximumSizeMagnitude
        self.showUnknownMagnitude = showUnknownMagnitude
        self.showNonexistentObjects = showNonexistentObjects
        self.maximumStarDiameter = maximumStarDiameter
        self.objectSymbolSize = objectSymbolSize
    }

    public func isVisible(catalog id: CatalogID) -> Bool {
        catalogVisibility[id.rawValue] ?? id.isUserCatalog
    }

    public mutating func setVisible(_ visible: Bool, catalog id: CatalogID) {
        catalogVisibility[id.rawValue] = visible
    }

    /// Ported magnitude/flags filter (legacy check_mag_limit variants).
    public func passesFilters(_ object: CatalogObject) -> Bool {
        if object.isNonexistentOrUnverified, !showNonexistentObjects {
            return false
        }
        switch object.kind {
        case .star:
            guard let mag = object.magnitude else {
                return showUnknownMagnitude
            }
            return mag <= stellarLimitingMagnitude
        case .userObject:
            return true
        default:
            guard let mag = object.magnitude else {
                return showUnknownMagnitude
            }
            return mag <= nonstellarLimitingMagnitude
        }
    }
}
