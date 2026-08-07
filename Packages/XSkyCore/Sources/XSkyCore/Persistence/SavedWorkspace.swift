import Foundation

/// Versioned persisted workspace state, written atomically to
/// Application Support. Decoding is defensive: a corrupt file falls back
/// to defaults (the caller preserves the corrupt file for diagnosis).
public struct SavedWorkspaceV1: Codable, Sendable {
    public var schemaVersion: Int
    public var centerRARadians: Double
    public var centerDecRadians: Double
    public var degreesPerPoint: Double
    public var orientation: ChartOrientation
    public var settings: ChartSettings
    public var displaySettings: DisplaySettings
    public var labels: [ChartLabel]
    public var sidebarVisible: Bool
    public var inspectorVisible: Bool

    public static let currentSchemaVersion = 1

    public init(
        centerRARadians: Double,
        centerDecRadians: Double,
        degreesPerPoint: Double,
        orientation: ChartOrientation,
        settings: ChartSettings,
        displaySettings: DisplaySettings,
        labels: [ChartLabel],
        sidebarVisible: Bool,
        inspectorVisible: Bool
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.centerRARadians = centerRARadians
        self.centerDecRadians = centerDecRadians
        self.degreesPerPoint = degreesPerPoint
        self.orientation = orientation
        self.settings = settings
        self.displaySettings = displaySettings
        self.labels = labels
        self.sidebarVisible = sidebarVisible
        self.inspectorVisible = inspectorVisible
    }
}

/// Display styling preferences (renderer-facing).
public struct DisplaySettings: Codable, Hashable, Sendable {
    public var colorMode: Bool
    public var nightMode: Bool
    public var chartLabelScale: Double

    public init(
        colorMode: Bool = true, nightMode: Bool = false,
        chartLabelScale: Double = 1.0
    ) {
        self.colorMode = colorMode
        self.nightMode = nightMode
        self.chartLabelScale = max(0.7, chartLabelScale)
    }
}

/// Loads and saves the workspace document.
public enum WorkspacePersistence {
    public static func defaultFileURL() throws -> URL {
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("XSky", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("workspace.json")
    }

    public static func load(from url: URL) -> SavedWorkspaceV1? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let decoded = try JSONDecoder().decode(
                SavedWorkspaceV1.self, from: data)
            guard decoded.schemaVersion == SavedWorkspaceV1.currentSchemaVersion,
                decoded.degreesPerPoint.isFinite,
                decoded.centerRARadians.isFinite,
                decoded.centerDecRadians.isFinite
            else { return nil }
            return decoded
        } catch {
            // preserve the corrupt file for diagnosis
            let corrupt = url.deletingPathExtension()
                .appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: corrupt)
            try? FileManager.default.copyItem(at: url, to: corrupt)
            return nil
        }
    }

    public static func save(_ workspace: SavedWorkspaceV1, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(workspace)
        try data.write(to: url, options: .atomic)
    }
}
