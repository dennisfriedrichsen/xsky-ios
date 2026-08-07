import Foundation

/// Semantic detail rows for the inspector, replacing the legacy
/// fixed-80-column detail strings while preserving their meaning
/// (ybs_disp.c, rngc_disp.c, qso_disp.c, user.c).
public struct ObjectDetails: Sendable, Hashable {
    public struct Row: Sendable, Hashable, Identifiable {
        public let id = UUID()
        public let label: String
        public let value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }

        public static func == (lhs: Row, rhs: Row) -> Bool {
            lhs.label == rhs.label && lhs.value == rhs.value
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(label)
            hasher.combine(value)
        }
    }

    public let preferredName: String
    public let catalogName: String
    public let designations: [String]
    public let rows: [Row]

    public static func build(
        for object: CatalogObject, store: CatalogStore
    ) -> ObjectDetails? {
        guard let catalog = store.catalogs[object.id.catalog] else {
            return nil
        }
        let name = ObjectLabels.preferredName(
            for: object, in: catalog, starNames: store.starNames)
        var rows: [Row] = []
        var designations: [String] = []

        // J2000 position rows are common to every catalog
        func appendPosition() {
            let ra = SexagesimalRA(radians: Radians(object.raRadians))
            let dec = SexagesimalDec(radians: Radians(object.decRadians))
            rows.append(Row(label: "RA (J2000)", value: ra.displayString))
            rows.append(Row(label: "Dec (J2000)", value: dec.displayString))
        }

        let record = catalog.rawRecord(for: object).map {
            FixedWidthRecord(bytes: Array($0.utf8)[...])
        }

        switch object.identity {
        case .ybs:
            buildYBS(
                object: object, catalog: catalog, record: record,
                store: store, rows: &rows, designations: &designations)
            appendPosition()
            appendYBSPhysical(record: record, rows: &rows)

        case .rngc(let number, let subletter, let messier):
            designations.append("NGC \(number)\(subletter ?? "")")
            if let messier { designations.append("M \(messier)") }
            if let names = store.ngcNames?.names(forNGC: number), !names.isEmpty {
                rows.append(
                    Row(label: "Common names", value: names.joined(separator: ", ")))
            }
            rows.append(Row(label: "Type", value: rngcTypeText(record: record)))
            appendPosition()
            if let mag = object.magnitude {
                rows.append(Row(label: "Magnitude", value: String(format: "%.1f", mag)))
            } else {
                rows.append(Row(label: "Magnitude", value: "unknown"))
            }
            if let record, let expander = store.descriptionExpander {
                let raw = record.trimmedField(
                    at: RNGCParser.descStart,
                    length: max(0, record.bytes.count - RNGCParser.descStart))
                if !raw.isEmpty {
                    rows.append(Row(label: "RNGC description", value: raw))
                    rows.append(
                        Row(
                            label: "Description",
                            value: expander.expand(
                                description: raw, rngcNumber: number,
                                kind: object.kind)))
                }
            }

        case .qso(let raDesig, let decDesig):
            designations.append(
                String(format: "QSO %04d-%03d", raDesig, decDesig))
            if let record {
                if record.byte(at: QSOParser.typeStart) == UInt8(ascii: "*") {
                    rows.append(Row(label: "Type", value: "BL Lacertae object"))
                }
                appendPosition()
                var magValue =
                    object.magnitude.map { String(format: "%.2f", $0) }
                    ?? "unknown"
                if record.byte(at: QSOParser.variableStart) == UInt8(ascii: "*") {
                    magValue += " (variable)"
                }
                rows.append(Row(label: "Magnitude", value: magValue))
                let redshift = record.trimmedField(
                    at: QSOParser.redshiftStart, length: 5)
                if !redshift.isEmpty {
                    rows.append(Row(label: "Redshift", value: redshift))
                }
                let others = record.trimmedField(
                    at: QSOParser.otherNamesStart,
                    length: max(0, record.bytes.count - QSOParser.otherNamesStart))
                if !others.isEmpty {
                    rows.append(
                        Row(
                            label: "Other names",
                            value: others.split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .joined(separator: ", ")))
                }
            } else {
                appendPosition()
            }

        case .user(let number, let label):
            designations.append("USER \(number)")
            if !label.isEmpty { designations.append(label) }
            appendPosition()
            if let text = UserCatalogParser.description(of: object, in: catalog) {
                rows.append(Row(label: "Description", value: text))
            }
        }

        return ObjectDetails(
            preferredName: name,
            catalogName: catalog.displayName,
            designations: designations,
            rows: rows)
    }

    // MARK: YBS

    private static func buildYBS(
        object: CatalogObject, catalog: LoadedCatalog,
        record: FixedWidthRecord?, store: CatalogStore,
        rows: inout [Row], designations: inout [String]
    ) {
        guard case .ybs(let hr, let bayer, let bayerSuper, let flamsteed, let con) =
            object.identity
        else { return }

        designations.append("HR \(hr)")
        let genitive = con.map { ConstellationTable.entries[$0].genitive }
        if let bayer, bayer >= 1, bayer <= GreekLetters.names.count,
            let genitive
        {
            var d = GreekLetters.names[bayer - 1]
            if let bayerSuper { d += "-\(bayerSuper)" }
            designations.append("\(d) \(genitive)")
        }
        if let flamsteed, let genitive {
            designations.append("\(flamsteed) \(genitive)")
        }
        if let record {
            let hd = record.intValue(at: YBSParser.hdStart, length: 6)
            if hd != 0 {
                designations.append(hd >= 100_000 ? "HDE \(hd)" : "HD \(hd)")
            }
            if !record.isBlank(at: YBSParser.bdStart, length: 8) {
                let bd = record.trimmedField(at: YBSParser.bdStart, length: 8)
                designations.append("BD \(bd)")
            }
        }
        if let names = store.starNames?.names(forHR: hr), !names.isEmpty {
            rows.append(
                Row(
                    label: "Common names",
                    value: names.map(ObjectLabels.titlecased)
                        .joined(separator: ", ")))
        }
        if let record {
            if record.byte(at: YBSParser.infraredStart) == UInt8(ascii: "I") {
                rows.append(Row(label: "Infrared", value: "Infrared source"))
            }
            let doubleCode = record.byte(at: YBSParser.doubleStart)
            switch doubleCode {
            case UInt8(ascii: "D"):
                rows.append(Row(label: "Multiplicity", value: "Occultation binary"))
            case UInt8(ascii: "S"):
                rows.append(Row(label: "Multiplicity", value: "Speckle binary"))
            case UInt8(ascii: "A"):
                rows.append(Row(label: "Multiplicity", value: "Astrometric binary"))
            default:
                break
            }
            let ads = record.trimmedField(at: YBSParser.adsStart, length: 4)
            if !ads.isEmpty {
                rows.append(Row(label: "ADS", value: "ADS \(ads)"))
            }
            let components = record.trimmedField(
                at: YBSParser.multipleStart, length: 2)
            if !components.isEmpty {
                rows.append(Row(label: "Components", value: components))
            }
            let variable = record.trimmedField(
                at: YBSParser.variableStart, length: 9)
            if !variable.isEmpty {
                rows.append(Row(label: "Variable", value: variable))
            }
        }
    }

    private static func appendYBSPhysical(
        record: FixedWidthRecord?, rows: inout [Row]
    ) {
        guard let record else { return }
        if let mag = record.isBlank(at: YBSParser.magStart, length: 5)
            ? nil : record.trimmedField(at: YBSParser.magStart, length: 5)
        {
            rows.append(Row(label: "Magnitude", value: mag))
        }
        let bv = record.trimmedField(at: 66, length: 5)
        let ub = record.trimmedField(at: 71, length: 5)
        let ri = record.trimmedField(at: 76, length: 5)
        var indices: [String] = []
        if !bv.isEmpty { indices.append("B-V \(bv)") }
        if !ub.isEmpty { indices.append("U-B \(ub)") }
        if !ri.isEmpty { indices.append("R-I \(ri)") }
        if !indices.isEmpty {
            rows.append(
                Row(label: "Color indices", value: indices.joined(separator: "   ")))
        }
        let spectrum = record.trimmedField(at: YBSParser.spectrumStart, length: 20)
        if !spectrum.isEmpty {
            rows.append(Row(label: "Spectral class", value: spectrum))
        }
        let pmRA = record.trimmedField(at: 101, length: 6)
        let pmDec = record.trimmedField(at: 107, length: 6)
        if !pmRA.isEmpty || !pmDec.isEmpty {
            rows.append(
                Row(
                    label: "Proper motion",
                    value: "RA \(pmRA)\"  Dec \(pmDec)\""))
        }
    }

    private static func rngcTypeText(record: FixedWidthRecord?) -> String {
        let table = [
            "unverified", "open cluster", "globular cluster",
            "diffuse nebula", "planetary nebula", "galaxy",
            "associated with nebulosity", "nonexistent",
            "in Large Magellanic Cloud", "in Small Magellanic Cloud",
        ]
        guard let record else { return "unknown" }
        let b0 = record.byte(at: RNGCParser.typeStart)
        let b1 = record.byte(at: RNGCParser.typeStart + 1)
        // legacy displays the lower code first when two digits are present
        let codes = [min(b0, b1), max(b0, b1)]
        var parts: [String] = []
        for code in codes where code >= UInt8(ascii: "0") && code <= UInt8(ascii: "9") {
            parts.append(table[Int(code - UInt8(ascii: "0"))])
        }
        return parts.isEmpty ? "unknown" : parts.joined(separator: ", ")
    }
}
