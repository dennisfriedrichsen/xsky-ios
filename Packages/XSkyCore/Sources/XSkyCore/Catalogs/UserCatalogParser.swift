import Foundation

/// Parser for the documented legacy user-catalog format (usercat.doc,
/// user.c): line 1 is the catalog title, line 2 the coordinate equinox,
/// and each remaining record is backslash-delimited:
/// `number\RA, Dec\label\description`. Coordinates are precessed from the
/// declared equinox to J2000. Malformed records produce diagnostics
/// without corrupting valid records.
public enum UserCatalogParser {

    public struct ParsedUserCatalog: Sendable {
        public let title: String
        public let equinox: Equinox
        public let catalog: LoadedCatalog
    }

    /// Per usercat.doc, automatic numbering for records with an empty
    /// number field begins at 1. (user.c itself numbered from the current
    /// array slot, i.e. 0; the documented behavior wins and the conflict
    /// is recorded in the diagnostics notes.)
    public static func parse(data: Data, catalogID: CatalogID) -> ParsedUserCatalog {
        var diagnostics = CatalogDiagnostics()
        var objects: [CatalogObject] = []

        let records = RecordSplitter.records(in: data)
        var title = "User Catalog"
        var equinox = Equinox.j2000

        if let first = records.first {
            let t = String(decoding: first.record.bytes, as: UTF8.self)
                .trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { title = String(t.prefix(80)) }
        } else {
            diagnostics.notes.append("empty user catalog file")
        }
        if records.count > 1 {
            let year = FixedWidthRecord.atof(Array(records[1].record.bytes))
            if year > 0 {
                equinox = Equinox(year: year)
            } else {
                diagnostics.notes.append(
                    "unreadable equinox line; assuming J2000")
            }
        }

        let precession: PrecessionTransform? =
            equinox.year == Equinox.j2000.year
            ? nil : PrecessionTransform(from: equinox, to: .j2000)

        var automaticNumber = 1

        for rec in records.dropFirst(2) {
            diagnostics.sourceRecords += 1
            let line = String(decoding: rec.record.bytes, as: UTF8.self)
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                diagnostics.skip("blank record")
                continue
            }

            // split on backslashes; the description may itself be absent
            let fields = line.split(
                separator: "\\", maxSplits: 3,
                omittingEmptySubsequences: false)
            guard fields.count >= 2 else {
                diagnostics.skip("missing position field")
                continue
            }

            let numberField = fields[0].trimmingCharacters(in: .whitespaces)
            let number: Int
            if numberField.isEmpty {
                number = automaticNumber
            } else {
                number = FixedWidthRecord.atoi(Array(numberField.utf8))
            }
            automaticNumber += 1

            let positionField = String(fields[1])
            let positionParts = positionField.split(
                separator: ",", maxSplits: 1)
            guard positionParts.count == 2,
                let ra = SexagesimalParser.parseRA(String(positionParts[0]))
            else {
                diagnostics.skip("malformed RA")
                diagnostics.notes.append(
                    "user object \(number) has malformed RA")
                continue
            }
            guard
                let dec = SexagesimalParser.parseDec(String(positionParts[1]))
            else {
                diagnostics.skip("malformed declination")
                diagnostics.notes.append(
                    "user object \(number) has malformed declination")
                continue
            }

            var label =
                fields.count >= 3
                ? fields[2].trimmingCharacters(in: .whitespaces) : ""
            if label.isEmpty { label = String(number) }
            label = String(label.prefix(20))

            var raRad = ra.radians.value
            var decRad = dec.radians.value
            if let precession {
                (raRad, decRad) = precession.apply(
                    rightAscension: raRad, declination: decRad)
            }

            objects.append(
                CatalogObject(
                    id: CatalogObjectID(
                        catalog: catalogID, record: objects.count),
                    raRadians: raRad,
                    decRadians: decRad,
                    magnitude: nil,
                    kind: .userObject,
                    spectralClass: nil,
                    identity: .user(number: number, label: label),
                    recordByteRange: rec.byteRange))
        }

        diagnostics.loadedObjects = objects.count
        diagnostics.notes.append(
            "automatic numbering starts at 1 per usercat.doc; legacy user.c numbered from 0"
        )

        return ParsedUserCatalog(
            title: title,
            equinox: equinox,
            catalog: LoadedCatalog(
                id: catalogID,
                displayName: title,
                shortName: "User",
                objects: objects,
                diagnostics: diagnostics,
                rawData: data))
    }

    /// The description field of a user object, formatted from the raw
    /// record (fourth backslash field).
    public static func description(
        of object: CatalogObject, in catalog: LoadedCatalog
    ) -> String? {
        guard let raw = catalog.rawRecord(for: object) else { return nil }
        let fields = raw.split(
            separator: "\\", maxSplits: 3, omittingEmptySubsequences: false)
        guard fields.count >= 4 else { return nil }
        let text = fields[3].trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : String(text.prefix(400))
    }
}
