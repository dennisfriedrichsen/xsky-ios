import Foundation
import Testing
import XSkyCore

@testable import XSky

/// App-hosted unit tests. Core astronomy/catalog logic is tested in the
/// XSkyCore package; these tests cover app-layer wiring.
@MainActor
@Suite("App wiring")
struct XSkyAppTests {

    /// WorkspaceModel restores persisted state, and the app container is
    /// shared with UI test runs; start each test from defaults.
    init() {
        if let url = try? WorkspacePersistence.defaultFileURL() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func workspaceModelStartsWithLegacyDefaultView() {
        let workspace = WorkspaceModel()
        let ra = SexagesimalRA(radians: workspace.viewport.center.rightAscension)
        let dec = SexagesimalDec(radians: workspace.viewport.center.declination)
        #expect(ra.hours == 5 && ra.minutes == 36)
        #expect(dec.sign == -1 && dec.degrees == 1 && dec.minutes == 12)
        #expect(abs(workspace.viewport.degreesPerPoint - 0.05) < 1e-12)
    }

    @Test func constellationLabelsAreOffUntilGenerated() {
        let workspace = WorkspaceModel()
        #expect(!workspace.settings.showConstellationLabels)
        #expect(!workspace.hasConstellationLabels)

        workspace.labels = [
            ChartLabel(anchor: .sky(raRadians: 0, decRadians: 0), text: "Note")
        ]
        #expect(!workspace.hasConstellationLabels)

        workspace.labels.append(
            ChartLabel(anchor: .constellation(0), text: "Andromeda"))
        #expect(workspace.hasConstellationLabels)
    }

    @Test func legacyCatalogResourcesAreBundled() {
        for name in ["ybs.dat", "rngc.dat", "qso.dat", "boundaries.dat"] {
            let parts = name.split(separator: ".")
            let url = Bundle(for: BundleToken.self).url(
                forResource: String(parts[0]), withExtension: String(parts[1]))
                ?? Bundle.main.url(
                    forResource: String(parts[0]),
                    withExtension: String(parts[1]))
            #expect(url != nil, "\(name) missing from app bundle")
        }
    }
}

private final class BundleToken {}
