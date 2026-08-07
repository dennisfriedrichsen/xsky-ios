import Foundation

/// Chart symbols, preserving the legacy non-stellar symbol vocabulary.
public enum ChartSymbol: String, Hashable, Codable, Sendable {
    case star
    case ellipse
    case circle
    case crossedCircle
    case square
    case diamond
    case xMark

    public init(kind: ObjectKind) {
        switch kind {
        case .star: self = .star
        case .galaxy: self = .ellipse
        case .openCluster: self = .circle
        case .globularCluster: self = .crossedCircle
        case .diffuseNebula, .clusterWithNebulosity: self = .square
        case .planetaryNebula: self = .diamond
        case .quasar, .userObject, .lmcObject, .smcObject, .unverified,
            .nonexistent, .unknown:
            self = .xMark
        }
    }
}

/// Preferred display labels, ported from the legacy format_*_name
/// routines: Bayer, then Flamsteed, then HD/HDE, then BD, then HR for
/// stars; Messier then NGC for RNGC; positional designation for QSOs;
/// the user label for user objects.
public enum ObjectLabels {

    /// The short chart label for an object. YBS HD/BD fallbacks need the
    /// raw record, so the loaded catalog is passed for stars.
    public static func chartLabel(
        for object: CatalogObject, in catalog: LoadedCatalog
    ) -> String {
        switch object.identity {
        case .ybs(let hr, let bayer, let bayerSuper, let flamsteed, _):
            if let bayer, bayer >= 1, bayer <= GreekLetters.symbols.count {
                var label = GreekLetters.symbols[bayer - 1]
                if let bayerSuper { label += superscript(bayerSuper) }
                return label
            }
            if let flamsteed { return String(flamsteed) }
            return hdOrBDOrHRLabel(hr: hr, object: object, catalog: catalog)

        case .rngc(let number, _, let messier):
            if let messier { return "M \(messier)" }
            return "NGC \(number)"

        case .qso(let raDesig, let decDesig):
            return String(format: "QSO %04d-%03d", raDesig, decDesig)

        case .user(let number, let label):
            return label.isEmpty ? "USER \(number)" : label
        }
    }

    /// The full preferred name for the inspector and search results.
    public static func preferredName(
        for object: CatalogObject, in catalog: LoadedCatalog,
        starNames: StarNameTable?
    ) -> String {
        switch object.identity {
        case .ybs(let hr, let bayer, let bayerSuper, let flamsteed, let con):
            if let starNames, let common = starNames.names(forHR: hr).first {
                return titlecased(common)
            }
            let genitive = con.map { ConstellationTable.entries[$0].genitive }
            if let bayer, bayer >= 1, bayer <= GreekLetters.names.count {
                var name = GreekLetters.names[bayer - 1]
                if let bayerSuper { name += "-\(bayerSuper)" }
                if let genitive { name += " \(genitive)" }
                return name
            }
            if let flamsteed, let genitive {
                return "\(flamsteed) \(genitive)"
            }
            return hdOrBDOrHRLabel(hr: hr, object: object, catalog: catalog)

        case .rngc(let number, let subletter, let messier):
            var name: String
            if let messier {
                name = "M \(messier)"
            } else {
                name = "NGC \(number)"
                if let subletter { name += subletter }
            }
            return name

        case .qso, .user:
            return chartLabel(for: object, in: catalog)
        }
    }

    /// HD/HDE, then BD, then HR (legacy format_ybs_name fallback), read
    /// from the raw record bytes.
    private static func hdOrBDOrHRLabel(
        hr: Int, object: CatalogObject, catalog: LoadedCatalog
    ) -> String {
        if let range = object.recordByteRange, range.upperBound <= catalog.rawData.count {
            let bytes = [UInt8](catalog.rawData[range])
            let record = FixedWidthRecord(bytes: bytes[...])
            let hd = record.intValue(at: YBSParser.hdStart, length: 6)
            if hd != 0 {
                return hd >= 100_000 ? "HDE \(hd)" : "HD \(hd)"
            }
            if !record.isBlank(at: YBSParser.bdStart, length: 8) {
                var field = record.fieldBytes(at: YBSParser.bdStart, length: 8)
                if field[1] == UInt8(ascii: " ") { field[1] = UInt8(ascii: "0") }
                for i in 0..<5 where field[3 + i] == UInt8(ascii: " ") {
                    field[3 + i] = UInt8(ascii: "0")
                }
                let zone = String(decoding: field[0..<3], as: UTF8.self)
                let num = String(decoding: field[3..<8], as: UTF8.self)
                return "BD \(zone)d \(num)"
            }
        }
        return "HR \(hr)"
    }

    private static func superscript(_ n: Int) -> String {
        let digits: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        ]
        return String(String(n).compactMap { digits[$0] })
    }

    /// Star-name files store primary names in all caps; present them in
    /// title case.
    static func titlecased(_ name: String) -> String {
        guard name == name.uppercased() else { return name }
        return name.capitalized
    }
}

/// The legacy magnitude-to-diameter relation (draw.c starsize()),
/// expressed in points. `maxSizeMagnitude` is the magnitude drawn at the
/// maximum size (legacy mag2_limit, default Sirius at -1.46).
public enum StarSizing {
    public static let defaultMaxDiameter = 9.0
    public static let minimumDiameter = 1.0

    public static func diameter(
        magnitude: Double, maxDiameter: Double = defaultMaxDiameter,
        maxSizeMagnitude: Double = -1.46
    ) -> Double {
        let d = maxDiameter - (magnitude - maxSizeMagnitude).rounded(.down)
        return max(d, minimumDiameter)
    }
}
