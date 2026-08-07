import Foundation
import Testing

@testable import XSkyCore

@Suite("Catalog parsing")
struct CatalogParserTests {
    let store = CatalogTestSupport.store

    @Test func ybsCountsMatchLegacy() {
        let ybs = try! #require(store.catalogs[.ybs])
        #expect(ybs.diagnostics.sourceRecords == 9110)
        #expect(ybs.objects.count == 9096)
        #expect(ybs.diagnostics.skipped["no position given"] == 14)
    }

    @Test func rngcCountsMatchLegacy() {
        let rngc = try! #require(store.catalogs[.rngc])
        #expect(rngc.diagnostics.sourceRecords == 8163)
        #expect(rngc.objects.count == 8163)
    }

    @Test func qsoCountsMatchLegacy() {
        let qso = try! #require(store.catalogs[.qso])
        #expect(qso.diagnostics.sourceRecords == 1549)
        #expect(qso.objects.count == 1549)
    }

    @Test func constellationDataCountsMatchLegacy() {
        #expect(store.boundaries.count == 89)
        #expect(store.outlines.count > 0)
        #expect(store.constellationCenters.count == 89)
        let outlineVertices = store.outlines.reduce(0) { $0 + $1.points.count }
        let boundaryVertices = store.boundaries.reduce(0) { $0 + $1.points.count }
        // 13,047 source records = vertices plus one -1 separator per path
        #expect(boundaryVertices + store.boundaries.count == 13047)
        #expect(outlineVertices > 800)
    }

    @Test func nameTableCountsMatchLegacy() {
        #expect(store.starNames?.entries.count == 301)
        #expect(store.ngcNames?.entries.count == 83)
    }

    /// Sirius is HR 2491: position, magnitude -1.46, spectral class A0/A1.
    @Test func siriusParsesCorrectly() {
        let ybs = try! #require(store.catalogs[.ybs])
        let sirius = try! #require(
            ybs.objects.first {
                if case .ybs(let hr, _, _, _, _) = $0.identity {
                    return hr == 2491
                }
                return false
            })
        #expect(abs(sirius.magnitude! - (-1.46)) < 1e-9)
        // 6h45m08.9s -16°42'58" J2000
        let ra = SexagesimalRA(radians: Radians(sirius.raRadians))
        #expect(ra.hours == 6 && ra.minutes == 45)
        let dec = SexagesimalDec(radians: Radians(sirius.decRadians))
        #expect(dec.sign == -1 && dec.degrees == 16 && dec.minutes == 42)
        #expect(sirius.spectralClass == .a)
        #expect(store.starNames?.hrNumber(forName: "Sirius") == 2491)
    }

    /// M31 = NGC 224: galaxy near 0h42.7m +41°16' after precession to J2000.
    @Test func m31ParsesAndPrecessesCorrectly() {
        let rngc = try! #require(store.catalogs[.rngc])
        let m31 = try! #require(
            rngc.objects.first {
                if case .rngc(let n, let sub, _) = $0.identity {
                    return n == 224 && sub == nil
                }
                return false
            })
        #expect(m31.kind == .galaxy)
        if case .rngc(_, _, let messier) = m31.identity {
            #expect(messier == 31)
        }
        let ra = SexagesimalRA(radians: Radians(m31.raRadians))
        #expect(ra.hours == 0 && ra.minutes == 42)
        let dec = SexagesimalDec(radians: Radians(m31.decRadians))
        #expect(dec.sign == 1 && dec.degrees == 41 && dec.minutes == 16)
    }

    /// QSO 3C 273 is 1226+023 (B1950 12h26m33s +2°19'43").
    @Test func qso3C273ParsesCorrectly() {
        let qso = try! #require(store.catalogs[.qso])
        let q = qso.objects.first {
            if case .qso(let a, let b) = $0.identity {
                return a == 1226 && b == 23
            }
            return false
        }
        let object = try! #require(q)
        #expect(object.kind == .quasar)
        // J2000 position ~12h29m
        let ra = SexagesimalRA(radians: Radians(object.raRadians))
        #expect(ra.hours == 12 && ra.minutes == 29)
    }

    @Test func unknownMagnitudeBecomesNil() {
        let rngc = try! #require(store.catalogs[.rngc])
        let unknowns = rngc.objects.filter { $0.magnitude == nil }
        #expect(!unknowns.isEmpty)
        #expect(rngc.objects.allSatisfy { ($0.magnitude ?? 0) < 90 })
    }

    @Test func malformedRecordsFailSafely() {
        // truncated and garbage records must not crash any parser
        let junk = Data("garbage\n\n   \nshort".utf8)
        _ = YBSParser.parse(data: junk)
        _ = RNGCParser.parse(data: junk)
        _ = QSOParser.parse(data: junk)
        _ = CelestialPathParser.parsePaths(data: junk, closed: true)
        _ = StarNameTable(data: junk)
        _ = NGCNameTable(data: junk)
        let truncatedYBS = Data(
            String(repeating: " ", count: 40).utf8)
        let parsed = YBSParser.parse(data: truncatedYBS)
        #expect(parsed.objects.isEmpty)
    }

    @Test func rngcDescriptionExpands() {
        let expander = try! #require(store.descriptionExpander)
        // NGC 7293 (Helix nebula) style description
        let text = expander.expand(
            description: "VF,LG", rngcNumber: 7293, kind: .planetaryNebula)
        #expect(text.contains("very faint"))
        #expect(text.contains("large"))
    }
}

@Suite("User catalog")
struct UserCatalogTests {

    private func parse(_ text: String) -> UserCatalogParser.ParsedUserCatalog {
        UserCatalogParser.parse(
            data: Data(text.utf8), catalogID: .user("test"))
    }

    @Test func exampleFileImports() throws {
        let data = try CatalogTestSupport.data("usercat.example")
        let parsed = UserCatalogParser.parse(
            data: data, catalogID: .user("example"))
        #expect(parsed.title == "Test Catalog")
        #expect(parsed.equinox.year == 2000.0)
        #expect(parsed.catalog.objects.count == 1)
        let object = try #require(parsed.catalog.objects.first)
        if case .user(let number, let label) = object.identity {
            #expect(number == 1)
            #expect(label == "Test Object")
        } else {
            Issue.record("expected user identity")
        }
        let description = UserCatalogParser.description(
            of: object, in: parsed.catalog)
        #expect(description?.contains("test object") == true)
    }

    @Test func alternateEquinoxPrecesses() {
        let parsed = parse(
            """
            B1950 Catalog
            1950.0
            1\\12h 26m 33s.3, +2d 19' 43"\\3C 273\\quasar
            """)
        #expect(parsed.equinox.year == 1950.0)
        let object = parsed.catalog.objects[0]
        // precessed to J2000 the RA moves to ~12h29m
        let ra = SexagesimalRA(radians: Radians(object.raRadians))
        #expect(ra.hours == 12 && ra.minutes == 29)
    }

    @Test func omittedNumbersAutoIncrementFromOne() {
        let parsed = parse(
            """
            Auto Numbers
            2000.0
            \\1h, +10d\\First\\
            \\2h, +20d\\Second\\
            """)
        let numbers = parsed.catalog.objects.map { object -> Int in
            if case .user(let n, _) = object.identity { return n }
            return -1
        }
        #expect(numbers == [1, 2])
    }

    @Test func malformedRecordsDoNotCorruptOthers() {
        let parsed = parse(
            """
            Mixed
            2000.0
            1\\nonsense, +10d\\Bad RA\\
            2\\2h, nonsense\\Bad Dec\\
            3\\3h 30m, -45d 30'\\Good\\fine
            """)
        #expect(parsed.catalog.objects.count == 1)
        #expect(parsed.catalog.diagnostics.skipped["malformed RA"] == 1)
        #expect(parsed.catalog.diagnostics.skipped["malformed declination"] == 1)
        if case .user(let n, let label) = parsed.catalog.objects[0].identity {
            #expect(n == 3 && label == "Good")
        }
    }

    @Test func longDescriptionsAreCapped() {
        let long = String(repeating: "x", count: 600)
        let parsed = parse(
            """
            Long
            2000.0
            1\\1h, +1d\\Label\\\(long)
            """)
        let desc = UserCatalogParser.description(
            of: parsed.catalog.objects[0], in: parsed.catalog)
        #expect(desc?.count == 400)
    }
}
