import Foundation
import XSkyCore

/// Locates the bundled legacy catalog files. They are byte-for-byte
/// copies from Resources/LegacyCatalogs, added to the bundle by the
/// project's synchronized folder reference.
struct BundleResourceLocator: CatalogResourceLocator {
    func data(forResource name: String) throws -> Data {
        let parts = name.split(separator: ".", maxSplits: 1)
        let base = String(parts[0])
        let ext = parts.count > 1 ? String(parts[1]) : nil
        guard let url = Bundle.main.url(forResource: base, withExtension: ext)
        else {
            throw CatalogParseError(
                catalog: CatalogID(rawValue: "bundle"),
                message: "missing bundled resource \(name)")
        }
        return try Data(contentsOf: url)
    }
}
