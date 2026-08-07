import Foundation

/// Parser for the Yale Bright Star catalog (ybs.dat), ported from
/// ybs_read.c / ybs.h. Field offsets are the legacy byte offsets. Records
/// with a blank 15-byte position field are skipped (the legacy behavior),
/// which yields 9,096 positioned objects from the bundled 9,110 records.
public enum YBSParser {
    // ybs.h byte offsets
    static let catStart = 0
    static let flamsteedStart = 4
    static let nameStart = 5
    static let bayerStart = 7
    static let bayerSuperStart = 9
    static let constellationStart = 11
    static let bdStart = 14
    static let hdStart = 22
    static let infraredStart = 28
    static let doubleStart = 29
    static let adsStart = 30
    static let multipleStart = 35
    static let variableStart = 37
    static let posStart = 46
    static let raStart = 46
    static let decStart = 54
    static let magStart = 61
    static let spectrumStart = 81

    public static let epoch = Equinox.j2000

    public static func parse(data: Data) -> LoadedCatalog {
        var diagnostics = CatalogDiagnostics()
        var objects: [CatalogObject] = []
        objects.reserveCapacity(9200)

        // constellation abbreviation -> table index; the data file stores
        // abbreviations uppercased ("ORI"), so match case-insensitively
        var constellationIndex: [String: Int] = [:]
        for (i, entry) in ConstellationTable.entries.enumerated() {
            constellationIndex[entry.abbreviation.uppercased()] = i
        }

        for rec in RecordSplitter.records(in: data) {
            diagnostics.sourceRecords += 1
            let r = rec.record

            if r.isBlank(at: posStart, length: 15) {
                diagnostics.skip("no position given")
                continue
            }

            let hr = r.intValue(at: catStart, length: 4)
            let flamsteed = r.intValue(at: flamsteedStart, length: 3)
            let bayer = r.intValue(at: bayerStart, length: 2)
            let bayerSuper = r.intValue(at: bayerSuperStart, length: 2)

            var conIndex: Int?
            let conAbbrev = r.trimmedField(at: constellationStart, length: 3)
                .uppercased()
            if !conAbbrev.isEmpty {
                conIndex = constellationIndex[conAbbrev]
                if conIndex == nil {
                    diagnostics.notes.append(
                        "HR \(hr): unknown constellation abbreviation \(conAbbrev)"
                    )
                }
            }

            // RA: HHMMSS.T packed at the position field
            let ra = SexagesimalRA(
                hours: r.intValue(at: raStart, length: 2),
                minutes: r.intValue(at: raStart + 2, length: 2),
                seconds: r.intValue(at: raStart + 4, length: 2),
                thousandths: r.intValue(at: raStart + 7, length: 1) * 100)

            let dec = SexagesimalDec(
                sign: r.byte(at: decStart) == UInt8(ascii: "-") ? -1 : 1,
                degrees: r.intValue(at: decStart + 1, length: 2),
                minutes: r.intValue(at: decStart + 3, length: 2),
                seconds: r.intValue(at: decStart + 5, length: 2),
                hundredths: 0)

            // catalog epoch is already the common equinox; no precession
            let raRad = ra.radians.value
            let decRad = dec.radians.value

            // legacy atof: a blank magnitude field reads as 0.0 and the
            // record still displays; preserve that but count it
            let magBlank = r.isBlank(at: magStart, length: 5)
            if magBlank {
                diagnostics.notes.append("HR \(hr): blank magnitude read as 0.0")
            }
            let mag = r.doubleValue(at: magStart, length: 5)

            let spectral = SpectralColorClass(
                spectrumByte: r.byte(at: spectrumStart + 2))

            objects.append(
                CatalogObject(
                    id: CatalogObjectID(catalog: .ybs, record: objects.count),
                    raRadians: raRad,
                    decRadians: decRad,
                    magnitude: mag,
                    kind: .star,
                    spectralClass: spectral,
                    identity: .ybs(
                        hr: hr,
                        bayerIndex: bayer > 0 ? bayer : nil,
                        bayerSuperscript: bayerSuper > 0 ? bayerSuper : nil,
                        flamsteed: flamsteed > 0 ? flamsteed : nil,
                        constellationIndex: conIndex),
                    recordByteRange: rec.byteRange))
        }

        diagnostics.loadedObjects = objects.count
        return LoadedCatalog(
            id: .ybs,
            displayName: "Yale Catalog of Bright Stars",
            shortName: "YBS",
            objects: objects,
            diagnostics: diagnostics,
            rawData: data)
    }
}
