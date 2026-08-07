import Foundation

/// Parser for the Revised New General Catalog (rngc.dat), ported from
/// rngc_read.c / rngc.h. Positions are epoch 1975.0 and are precessed to
/// J2000 during loading. All 8,163 source records load; unknown magnitude
/// (no '.' at the third magnitude byte) becomes nil rather than the legacy
/// 99.99 sentinel.
public enum RNGCParser {
    // rngc.h byte offsets
    static let catStart = 0
    static let subletterStart = 5
    static let typeStart = 6
    static let raStart = 8
    static let decStart = 14
    static let magStart = 19
    static let descStart = 23

    public static let epoch = Equinox.epoch1975

    /// Legacy RNGC type codes.
    public static func kind(forTypeCode code: Int) -> ObjectKind {
        var major = code
        if major >= 10 { major /= 10 }
        switch major {
        case 0: return .unverified
        case 1: return .openCluster
        case 2: return .globularCluster
        case 3: return .diffuseNebula
        case 4: return .planetaryNebula
        case 5: return .galaxy
        case 6: return .clusterWithNebulosity
        case 7: return .nonexistent
        case 8: return .lmcObject
        case 9: return .smcObject
        default: return .unknown
        }
    }

    public static func parse(data: Data) -> LoadedCatalog {
        var diagnostics = CatalogDiagnostics()
        var objects: [CatalogObject] = []
        objects.reserveCapacity(8200)

        let precession = PrecessionTransform(from: epoch, to: .j2000)

        // NGC number -> Messier number for preferred labels
        var messierByNGC: [Int: Int] = [:]
        for (i, ngc) in MessierTable.ngcNumbers.enumerated() where ngc != 0 {
            messierByNGC[ngc] = i + 1
        }

        for rec in RecordSplitter.records(in: data) {
            diagnostics.sourceRecords += 1
            let r = rec.record

            let number = r.intValue(at: catStart, length: 5)
            let subletterByte = r.byte(at: subletterStart)
            let subletter =
                subletterByte == UInt8(ascii: " ")
                ? nil : String(UnicodeScalar(subletterByte))
            let typeCode = r.intValue(at: typeStart, length: 2)

            // RA is HHMM.T (tenths of minutes as 6-second steps)
            let ra = SexagesimalRA(
                hours: r.intValue(at: raStart, length: 2),
                minutes: r.intValue(at: raStart + 2, length: 2),
                seconds: r.intValue(at: raStart + 5, length: 1) * 6,
                thousandths: 0)

            let dec = SexagesimalDec(
                sign: r.byte(at: decStart) == UInt8(ascii: "-") ? -1 : 1,
                degrees: r.intValue(at: decStart + 1, length: 2),
                minutes: r.intValue(at: decStart + 3, length: 2),
                seconds: 0,
                hundredths: 0)

            let (raRad, decRad) = precession.apply(
                rightAscension: ra.radians.value,
                declination: dec.radians.value)

            // magnitude is valid only when the field has its decimal point
            let mag: Double?
            if r.byte(at: magStart + 2) == UInt8(ascii: ".") {
                mag = r.doubleValue(at: magStart, length: 4)
            } else {
                mag = nil
                diagnostics.skipped["unknown magnitude (kept, mag=nil)", default: 0] += 1
            }

            objects.append(
                CatalogObject(
                    id: CatalogObjectID(catalog: .rngc, record: objects.count),
                    raRadians: raRad,
                    decRadians: decRad,
                    magnitude: mag,
                    kind: kind(forTypeCode: typeCode),
                    spectralClass: nil,
                    identity: .rngc(
                        number: number,
                        subletter: subletter,
                        messier: messierByNGC[number]),
                    recordByteRange: rec.byteRange))
        }

        diagnostics.loadedObjects = objects.count
        return LoadedCatalog(
            id: .rngc,
            displayName: "Revised New General Catalog of Non-Stellar Objects",
            shortName: "RNGC",
            objects: objects,
            diagnostics: diagnostics,
            rawData: data)
    }
}
