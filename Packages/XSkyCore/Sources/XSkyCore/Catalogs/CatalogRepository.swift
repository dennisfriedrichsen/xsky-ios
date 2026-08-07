import Foundation

/// Locates bundled catalog resources. The app supplies a bundle-backed
/// implementation; tests supply a filesystem-backed one.
public protocol CatalogResourceLocator: Sendable {
    func data(forResource name: String) throws -> Data
}

/// A filesystem directory locator (used by tests and tools).
public struct DirectoryResourceLocator: CatalogResourceLocator {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func data(forResource name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }
}

/// Everything the chart needs from the loaded data, as one immutable
/// snapshot handed across actors.
public struct CatalogStore: Sendable {
    public var catalogs: [CatalogID: LoadedCatalog]
    public var spatialIndexes: [CatalogID: SpatialIndex]
    public var boundaries: [CelestialPath]
    public var outlines: [CelestialPath]
    public var constellationCenters: [CelestialPath.CelestialPoint]
    public var starNames: StarNameTable?
    public var ngcNames: NGCNameTable?
    public var descriptionExpander: RNGCDescriptionExpander?
    public var searchEngine: SearchEngine

    public func catalog(_ id: CatalogID) -> LoadedCatalog? { catalogs[id] }

    public func object(_ id: CatalogObjectID) -> CatalogObject? {
        guard let catalog = catalogs[id.catalog],
            id.record >= 0, id.record < catalog.objects.count
        else { return nil }
        return catalog.objects[id.record]
    }

    /// User catalogs in insertion order (stable by ID).
    public var userCatalogIDs: [CatalogID] {
        catalogs.keys.filter(\.isUserCatalog)
            .sorted { $0.rawValue < $1.rawValue }
    }
}

/// Loads, parses, and indexes catalogs off the main actor, and manages
/// imported user catalogs in Application Support.
public actor CatalogRepository {
    private let locator: any CatalogResourceLocator
    private let userCatalogDirectory: URL?
    private var store: CatalogStore?

    public init(
        locator: any CatalogResourceLocator,
        userCatalogDirectory: URL? = nil
    ) {
        self.locator = locator
        self.userCatalogDirectory = userCatalogDirectory
    }

    /// Load every bundled catalog and support table, plus previously
    /// imported user catalogs. Idempotent; returns the shared store.
    public func loadAll() throws -> CatalogStore {
        if let store { return store }
        let built = try Self.loadStore(
            locator: locator,
            userCatalogURLs: storedUserCatalogURLs())
        store = built
        return built
    }

    /// Synchronous store construction; callable from any context (the
    /// actor serializes access, tests call it directly).
    public static func loadStore(
        locator: any CatalogResourceLocator,
        userCatalogURLs: [URL] = []
    ) throws -> CatalogStore {
        var catalogs: [CatalogID: LoadedCatalog] = [:]
        catalogs[.ybs] = YBSParser.parse(
            data: try locator.data(forResource: "ybs.dat"))
        catalogs[.rngc] = RNGCParser.parse(
            data: try locator.data(forResource: "rngc.dat"))
        catalogs[.qso] = QSOParser.parse(
            data: try locator.data(forResource: "qso.dat"))

        let boundaries = CelestialPathParser.parsePaths(
            data: try locator.data(forResource: "boundaries.dat"),
            closed: true)
        let outlines = CelestialPathParser.parsePaths(
            data: try locator.data(forResource: "outlines.dat"),
            closed: false)
        let centers = CelestialPathParser.parseCenters(
            data: try locator.data(forResource: "concenters.dat"))

        let starNames = StarNameTable(
            data: try locator.data(forResource: "starnames.dat"))
        let ngcNames = NGCNameTable(
            data: try locator.data(forResource: "ngc_names.dat"))
        let expander = RNGCDescriptionExpander(
            descriptionTable: try locator.data(forResource: "rngc_desc.tab"),
            ambiguityList: try locator.data(forResource: "rngc_ambig.dat"))

        // previously imported user catalogs
        for url in userCatalogURLs {
            if let data = try? Data(contentsOf: url) {
                let id = CatalogID.user(url.deletingPathExtension().lastPathComponent)
                catalogs[id] = UserCatalogParser.parse(
                    data: data, catalogID: id
                ).catalog
            }
        }

        return buildStore(
            catalogs: catalogs, boundaries: boundaries.paths,
            outlines: outlines.paths, centers: centers,
            starNames: starNames, ngcNames: ngcNames, expander: expander)
    }

    private static func buildStore(
        catalogs: [CatalogID: LoadedCatalog],
        boundaries: [CelestialPath],
        outlines: [CelestialPath],
        centers: [CelestialPath.CelestialPoint],
        starNames: StarNameTable?,
        ngcNames: NGCNameTable?,
        expander: RNGCDescriptionExpander?
    ) -> CatalogStore {
        var indexes: [CatalogID: SpatialIndex] = [:]
        for (id, catalog) in catalogs {
            indexes[id] = SpatialIndex(objects: catalog.objects)
        }
        return CatalogStore(
            catalogs: catalogs,
            spatialIndexes: indexes,
            boundaries: boundaries,
            outlines: outlines,
            constellationCenters: centers,
            starNames: starNames,
            ngcNames: ngcNames,
            descriptionExpander: expander,
            searchEngine: SearchEngine(
                catalogs: catalogs, starNames: starNames, ngcNames: ngcNames,
                centers: centers))
    }

    // MARK: user catalog import

    /// Import a legacy user catalog from raw file data. The repository
    /// stores an app-owned copy in Application Support; the user's
    /// original file is never modified. Returns the updated store.
    public func importUserCatalog(
        data: Data, suggestedName: String
    ) throws -> (store: CatalogStore, id: CatalogID, diagnostics: CatalogDiagnostics) {
        guard var current = store else {
            throw CatalogParseError(
                catalog: CatalogID(rawValue: "USER"),
                message: "catalogs not loaded yet")
        }

        let token = UUID().uuidString
        let id = CatalogID.user(token)
        let parsed = UserCatalogParser.parse(data: data, catalogID: id)

        if let dir = userCatalogDirectory {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent("\(token).usercat")
            try data.write(to: fileURL, options: .atomic)
            let provenance = dir.appendingPathComponent("\(token).provenance.txt")
            let info = """
                source: \(suggestedName)
                imported: \(ISO8601DateFormatter().string(from: Date()))
                title: \(parsed.title)
                equinox: \(parsed.equinox.year)
                objects: \(parsed.catalog.objects.count)
                """
            try? info.data(using: .utf8)?.write(to: provenance)
        }

        current.catalogs[id] = parsed.catalog
        current = Self.rebuild(from: current)
        store = current
        return (current, id, parsed.catalog.diagnostics)
    }

    /// Remove an imported user catalog and its app-owned copy.
    public func removeUserCatalog(id: CatalogID) -> CatalogStore? {
        guard var current = store, id.isUserCatalog else { return store }
        current.catalogs[id] = nil
        if let dir = userCatalogDirectory {
            let token = String(id.rawValue.dropFirst("USER-".count))
            try? FileManager.default.removeItem(
                at: dir.appendingPathComponent("\(token).usercat"))
            try? FileManager.default.removeItem(
                at: dir.appendingPathComponent("\(token).provenance.txt"))
        }
        let rebuilt = Self.rebuild(from: current)
        store = rebuilt
        return rebuilt
    }

    private static func rebuild(from current: CatalogStore) -> CatalogStore {
        buildStore(
            catalogs: current.catalogs,
            boundaries: current.boundaries,
            outlines: current.outlines,
            centers: current.constellationCenters,
            starNames: current.starNames,
            ngcNames: current.ngcNames,
            expander: current.descriptionExpander)
    }

    private func storedUserCatalogURLs() -> [URL] {
        guard let dir = userCatalogDirectory,
            let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return contents.filter { $0.pathExtension == "usercat" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
