import Foundation
import Testing

@testable import XSkyCore

/// Golden tests for the Hipparcos parser prototype (ADR 0001). The fixture
/// records are byte-for-byte copies of I/239 `hip_main.dat` lines; the
/// expected values come from `tools/hipparcos/make_fixture.py`, which
/// implements the CDS byte-by-byte layout independently of this code.
///
/// These tests exercise the spike only. No Hipparcos data is bundled with
/// the app and no runtime code path reaches `HipparcosParser`.
@Suite("Hipparcos parser prototype")
struct HipparcosPrototypeTests {
    struct Expected: Decodable {
        let hip: Int
        let note: String
        let vmag: Double?
        let raDegrees: Double?
        let decDegrees: Double?
        let parallaxMas: Double?
        let pmRAMasPerYear: Double?
        let pmDecMasPerYear: Double?
        let hd: Int?
        let spectralType: String?
        let spectralClass: String
        let ccdm: String?
        let componentCount: Int?
        let componentIdentifiers: String?
        let j2000RARadians: Double?
        let j2000DecRadians: Double?
    }

    struct Fixture: Decodable {
        let source: String
        let sourceSHA256: String
        let recordEpoch: String
        let propagatedEpoch: String
        let records: [Expected]
    }

    static let fixture: Fixture = {
        guard
            let url = Bundle.module.url(
                forResource: "hip_main_expected", withExtension: "json",
                subdirectory: "Fixtures/hipparcos")
        else {
            fatalError("hip_main_expected.json missing from test bundle")
        }
        do {
            return try JSONDecoder().decode(
                Fixture.self, from: try Data(contentsOf: url))
        } catch {
            fatalError("hip_main_expected.json failed to decode: \(error)")
        }
    }()

    static let sampleData: Data = {
        guard
            let url = Bundle.module.url(
                forResource: "hip_main_sample", withExtension: "dat",
                subdirectory: "Fixtures/hipparcos")
        else {
            fatalError("hip_main_sample.dat missing from test bundle")
        }
        return try! Data(contentsOf: url)
    }()

    static let parsed = HipparcosParser.parse(data: sampleData)

    /// Every fixture line is exactly the published record width, which is
    /// what makes the byte-offset field table usable at all.
    @Test func sampleRecordsHaveThePublishedWidth() {
        for split in RecordSplitter.records(in: Self.sampleData) {
            #expect(
                split.byteRange.count == HipparcosParser.recordWidth,
                "line \(split.lineNumber) is \(split.byteRange.count) bytes")
        }
    }

    @Test func parsesEveryFixtureRecord() {
        #expect(Self.parsed.records.count == Self.fixture.records.count)
        #expect(
            Self.parsed.diagnostics.sourceRecords
                == Self.fixture.records.count)
    }

    @Test(arguments: fixture.records)
    func matchesGoldenFields(_ expected: Expected) throws {
        let record = try #require(
            Self.parsed.records.first { $0.hip == expected.hip },
            "HIP \(expected.hip) not parsed (\(expected.note))")

        #expect(record.visualMagnitude == expected.vmag)
        #expect(record.raDegrees == expected.raDegrees)
        #expect(record.decDegrees == expected.decDegrees)
        #expect(record.parallaxMas == expected.parallaxMas)
        #expect(record.pmRAMasPerYear == expected.pmRAMasPerYear)
        #expect(record.pmDecMasPerYear == expected.pmDecMasPerYear)
        #expect(record.hd == expected.hd)
        #expect(record.spectralType == expected.spectralType)
        #expect(record.spectralClass.rawValue == expected.spectralClass)
        #expect(record.ccdm == expected.ccdm)
        #expect(record.componentCount == expected.componentCount)
        #expect(record.componentIdentifiers == expected.componentIdentifiers)
    }

    /// Propagation from J1991.25 to J2000 is compared against the Python
    /// reference at 1e-12 radians, roughly 2e-7 arcseconds -- five orders
    /// of magnitude below the catalogue's own 0.7-0.9 mas errors, so the
    /// tolerance covers floating-point ordering only, not method drift.
    @Test(arguments: fixture.records)
    func propagatesToJ2000(_ expected: Expected) throws {
        let record = try #require(
            Self.parsed.records.first { $0.hip == expected.hip })

        guard let expectedRA = expected.j2000RARadians,
            let expectedDec = expected.j2000DecRadians
        else {
            #expect(
                record.j2000 == nil,
                "HIP \(expected.hip) has no solution but produced a coordinate")
            return
        }

        let coordinate = try #require(record.j2000)
        #expect(
            abs(coordinate.rightAscension.value - expectedRA) < 1e-12,
            "HIP \(expected.hip) RA")
        #expect(
            abs(coordinate.declination.value - expectedDec) < 1e-12,
            "HIP \(expected.hip) Dec")
        #expect(coordinate.rightAscension.value >= 0)
        #expect(coordinate.rightAscension.value < 2 * .pi)
    }

    /// The record with no astrometric solution must be reported, not
    /// silently turned into a position at (0, 0).
    @Test func missingAstrometryIsDiagnosedNotFabricated() throws {
        let record = try #require(
            Self.parsed.records.first { $0.hip == 421 })
        #expect(record.j2000 == nil)
        #expect(record.raDegrees == nil)
        #expect(record.parallaxMas == nil)
        // HIP 421 and HIP 120412 both lack an astrometric solution.
        #expect(Self.parsed.diagnostics.skipped["no astrometric solution"] == 2)
    }

    /// Blank numeric fields must read as nil rather than the C `atof`
    /// zero that YBS magnitudes still suffer from.
    @Test func blankMagnitudeIsNilNotZero() throws {
        let record = try #require(
            Self.parsed.records.first { $0.hip == 120412 })
        #expect(record.visualMagnitude == nil)
    }

    /// Spectral types outside the legacy W/O/B/A/F/G/K/M/C/N/S mapping
    /// fall back to the neutral colour and raise a diagnostic instead of
    /// crashing, matching the YBS rule.
    @Test func unmappedSpectralTypesAreNeutralAndDiagnosed() throws {
        for hip in [168, 3213, 3829, 65423] {
            let record = try #require(
                Self.parsed.records.first { $0.hip == hip })
            #expect(record.spectralClass == .neutral, "HIP \(hip)")
            #expect(
                Self.parsed.diagnostics.notes.contains {
                    $0.hasPrefix("HIP \(hip): unmapped spectral type")
                }, "HIP \(hip) missing diagnostic")
        }
    }

    /// The double-star entries the `starnames.dat` cross-match has to
    /// reach through an HD neighbour: Hipparcos carries only the primary's
    /// HD and marks the entry as a known double.
    @Test func mergedDoublesCarryOnlyThePrimaryHD() throws {
        let alrisha = try #require(
            Self.parsed.records.first { $0.hip == 9487 })
        #expect(alrisha.hd == 12446)  // starnames.dat keys HR 596 to HD 12447
        #expect(alrisha.componentIdentifiers == "AB")
        #expect(alrisha.ccdm != nil)

        let tegmen = try #require(
            Self.parsed.records.first { $0.hip == 40167 })
        #expect(tegmen.hd == 68255)  // starnames.dat keys HR 3208 to HD 68257
        #expect(tegmen.componentCount == 3)
    }

    /// Full-catalogue measurement backing the performance section of ADR
    /// 0001. Skipped unless `tools/hipparcos/fetch.sh` has been run, since
    /// the 53 MB source is deliberately not committed.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: fullCatalogPath)))
    func fullCatalogueParseAndIndexCost() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: Self.fullCatalogPath))

        let parseStart = ContinuousClock.now
        let result = HipparcosParser.parse(data: data)
        let parseElapsed = ContinuousClock.now - parseStart
        #expect(result.records.count == 118_218)

        let objects = result.records.enumerated().compactMap {
            index, record -> CatalogObject? in
            guard let j2000 = record.j2000 else { return nil }
            return CatalogObject(
                id: CatalogObjectID(catalog: .ybs, record: index),
                raRadians: j2000.rightAscension.value,
                decRadians: j2000.declination.value,
                magnitude: record.visualMagnitude,
                kind: .star,
                spectralClass: record.spectralClass,
                identity: .ybs(
                    hr: record.hip, bayerIndex: nil, bayerSuperscript: nil,
                    flamsteed: nil, constellationIndex: nil),
                recordByteRange: nil)
        }
        #expect(objects.count == 117_955)

        let indexStart = ContinuousClock.now
        let index = SpatialIndex(objects: objects)
        let indexElapsed = ContinuousClock.now - indexStart

        // A wide chart, a medium one, and a pole-containing one.
        let viewports = [
            ChartViewport(
                center: EquatorialCoordinate(
                    rightAscension: Radians(1.47), declination: Radians(-0.02)),
                degreesPerPoint: 0.2,
                sizeInPoints: Size2D(width: 1080, height: 810)),
            ChartViewport(
                center: EquatorialCoordinate(
                    rightAscension: Radians(1.47), declination: Radians(-0.02)),
                degreesPerPoint: 0.05,
                sizeInPoints: Size2D(width: 1080, height: 810)),
            ChartViewport(
                center: EquatorialCoordinate(
                    rightAscension: Radians(0), declination: Radians(degrees: 89)),
                degreesPerPoint: 0.2,
                sizeInPoints: Size2D(width: 1080, height: 810)),
        ]

        // One frame of the ChartSceneBuilder inner loop: coarse candidates,
        // magnitude filter, exact viewport intersection.
        func frame(
            _ viewport: ChartViewport, limit: Double
        ) -> (candidates: Int, drawn: Int, duration: Duration) {
            let tester = VisibilityTester(viewport: viewport)
            let start = ContinuousClock.now
            var candidates = 0
            var drawn = 0
            for i in index.candidates(in: tester.bounds) {
                candidates += 1
                let object = objects[i]
                guard let magnitude = object.magnitude, magnitude <= limit
                else { continue }
                guard
                    tester.visiblePosition(
                        rightAscension: object.raRadians,
                        declination: object.decRadians) != nil
                else { continue }
                drawn += 1
            }
            return (candidates, drawn, ContinuousClock.now - start)
        }

        // Same loop over the bundled YBS catalogue, as the baseline the
        // frame budget is known to hold today.
        let ybs = CatalogTestSupport.store
        let ybsObjects = ybs.catalogs[.ybs]!.objects
        let ybsIndex = ybs.spatialIndexes[.ybs]!
        func ybsFrame(
            _ viewport: ChartViewport, limit: Double
        ) -> (candidates: Int, drawn: Int, duration: Duration) {
            let tester = VisibilityTester(viewport: viewport)
            let start = ContinuousClock.now
            var candidates = 0
            var drawn = 0
            for i in ybsIndex.candidates(in: tester.bounds) {
                candidates += 1
                let object = ybsObjects[i]
                guard let magnitude = object.magnitude, magnitude <= limit
                else { continue }
                guard
                    tester.visiblePosition(
                        rightAscension: object.raRadians,
                        declination: object.decRadians) != nil
                else { continue }
                drawn += 1
            }
            return (candidates, drawn, ContinuousClock.now - start)
        }

        var report = ""
        for (name, viewport) in zip(["wide", "medium", "pole"], viewports) {
            for limit in [6.5, 9.0] {
                _ = frame(viewport, limit: limit)  // warm
                let f = frame(viewport, limit: limit)
                _ = ybsFrame(viewport, limit: limit)
                let y = ybsFrame(viewport, limit: limit)
                report += """
                      \(name) chart, limit \(limit): \
                    HIP \(f.candidates) cand -> \(f.drawn) drawn in \
                    \(f.duration); \
                    YBS \(y.candidates) cand -> \(y.drawn) drawn in \
                    \(y.duration)

                    """
            }
        }

        print("""
            Hipparcos full-catalogue cost (host, release):
              parse+propagate 118,218 records: \(parseElapsed)
              build spatial index (117,955):   \(indexElapsed)
            \(report)
            """)
    }

    static let fullCatalogPath: String =
        URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // XSkyCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // XSkyCore
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("tools/hipparcos/build/hip_main.dat")
        .path

    /// Parallax is the field YBS cannot provide at all; a usable distance
    /// requires a positive parallax.
    @Test func parallaxYieldsDistanceOnlyWhenPositive() throws {
        let sirius = try #require(
            Self.parsed.records.first { $0.hip == 32349 })
        let distance = try #require(sirius.distanceParsecs)
        #expect(abs(distance - 2.637) < 0.01, "Sirius distance \(distance) pc")

        let unsolved = try #require(
            Self.parsed.records.first { $0.hip == 421 })
        #expect(unsolved.distanceParsecs == nil)
    }
}
