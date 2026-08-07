import Foundation

/// Parser for the optical QSO catalog (qso.dat), ported from qso_read.c /
/// qso.h. Positions are B1950 and are precessed to J2000 during loading.
/// Objects render as X marks and are designated `QSO hhmm-ddd` from the
/// catalog's positional designation.
public enum QSOParser {
    // qso.h byte offsets
    static let raStart = 0
    static let decStart = 9
    static let redshiftStart = 18
    static let magStart = 23
    static let typeStart = 28
    static let variableStart = 29
    static let catStart = 30
    static let otherNamesStart = 38

    public static let epoch = Equinox.b1950

    public static func parse(data: Data) -> LoadedCatalog {
        var diagnostics = CatalogDiagnostics()
        var objects: [CatalogObject] = []
        objects.reserveCapacity(1600)

        let precession = PrecessionTransform(from: epoch, to: .j2000)

        for rec in RecordSplitter.records(in: data) {
            diagnostics.sourceRecords += 1
            let r = rec.record

            let desigRA = r.intValue(at: catStart, length: 4)
            let desigDec = r.intValue(at: catStart + 5, length: 3)

            let ra = SexagesimalRA(
                hours: r.intValue(at: raStart, length: 2),
                minutes: r.intValue(at: raStart + 2, length: 2),
                seconds: r.intValue(at: raStart + 4, length: 2),
                thousandths: r.intValue(at: raStart + 7, length: 3) * 10)

            let dec = SexagesimalDec(
                sign: r.byte(at: decStart) == UInt8(ascii: "-") ? -1 : 1,
                degrees: r.intValue(at: decStart + 1, length: 2),
                minutes: r.intValue(at: decStart + 3, length: 2),
                seconds: r.intValue(at: decStart + 5, length: 2),
                hundredths: r.intValue(at: decStart + 8, length: 2))

            let (raRad, decRad) = precession.apply(
                rightAscension: ra.radians.value,
                declination: dec.radians.value)

            let mag: Double?
            if r.byte(at: magStart + 2) == UInt8(ascii: ".") {
                mag = r.doubleValue(at: magStart, length: 5)
            } else {
                mag = nil
                diagnostics.skipped["unknown magnitude (kept, mag=nil)", default: 0] += 1
            }

            objects.append(
                CatalogObject(
                    id: CatalogObjectID(catalog: .qso, record: objects.count),
                    raRadians: raRad,
                    decRadians: decRad,
                    magnitude: mag,
                    kind: .quasar,
                    spectralClass: nil,
                    identity: .qso(
                        raDesignation: desigRA, decDesignation: desigDec),
                    recordByteRange: rec.byteRange))
        }

        diagnostics.loadedObjects = objects.count
        return LoadedCatalog(
            id: .qso,
            displayName: "Optical Catalog of Quasi-Stellar Objects",
            shortName: "QSO",
            objects: objects,
            diagnostics: diagnostics,
            rawData: data)
    }
}
