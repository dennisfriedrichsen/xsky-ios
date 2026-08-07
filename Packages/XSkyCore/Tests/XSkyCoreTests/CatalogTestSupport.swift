import Foundation
import XSkyCore

/// Locates the canonical legacy catalog files at
/// Resources/LegacyCatalogs relative to this repository, via #filePath.
/// Works under both `swift test` and simulator-hosted xcodebuild runs
/// (the simulator shares the host filesystem).
enum CatalogTestSupport {
    static var legacyCatalogsURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // XSkyCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // XSkyCore
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("Resources/LegacyCatalogs")
    }

    static var locator: DirectoryResourceLocator {
        DirectoryResourceLocator(directory: legacyCatalogsURL)
    }

    static func data(_ name: String) throws -> Data {
        try locator.data(forResource: name)
    }

    /// One shared parsed store for the whole test run.
    static let store: CatalogStore = {
        do {
            return try CatalogRepository.loadStore(locator: locator)
        } catch {
            fatalError("catalog store failed to load: \(error) from \(legacyCatalogsURL.path)")
        }
    }()
}
