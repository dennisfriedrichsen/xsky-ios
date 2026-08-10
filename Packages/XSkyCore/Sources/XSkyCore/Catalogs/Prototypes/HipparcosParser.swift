import Foundation

/// Parser prototype for the Hipparcos main catalogue, CDS/VizieR I/239
/// `hip_main.dat` (ESA 1997, SP-1200).
///
/// This is an evaluation spike for the decision recorded in
/// `design/adr/0001-hipparcos-star-catalog.md`. Nothing in the runtime
/// catalog pipeline calls it: it does not produce `CatalogObject`, it is
/// not registered with `CatalogRepository`, and no Hipparcos file is
/// bundled in `Resources/LegacyCatalogs`. It exists so the ADR's claims
/// about byte layout, field population, and epoch handling are executable
/// and testable rather than asserted.
///
/// It deliberately reuses `FixedWidthRecord` and `RecordSplitter`
/// unchanged, which is itself part of the finding: the existing
/// byte-offset parsing rule handles Hipparcos without modification.
public enum HipparcosParser {
    /// Byte offsets, zero-based, converted from the one-based inclusive
    /// ranges printed in the CDS `ReadMe` byte-by-byte table. The comment
    /// on each line is the ReadMe's own range and field label.
    public enum Field {
        public static let hip = (start: 8, length: 6)  // 9-14   HIP
        public static let vmag = (start: 41, length: 5)  // 42-46  Vmag
        public static let raDegrees = (start: 51, length: 12)  // 52-63  RAdeg
        public static let decDegrees = (start: 64, length: 12)  // 65-76  DEdeg
        public static let parallax = (start: 79, length: 7)  // 80-86  Plx
        public static let pmRA = (start: 87, length: 8)  // 88-95  pmRA
        public static let pmDec = (start: 96, length: 8)  // 97-104 pmDE
        public static let ccdm = (start: 327, length: 10)  // 328-337 CCDM
        public static let componentCount = (start: 343, length: 2)  // 344-345 Ncomp
        public static let componentIDs = (start: 352, length: 2)  // 353-354 m_HIP
        public static let hd = (start: 390, length: 6)  // 391-396 HD
        public static let spectralType = (start: 435, length: 12)  // 436-447 SpType
    }

    /// Every `hip_main.dat` record is exactly this wide before its line
    /// terminator. Note that I/239 is CRLF-terminated (450 + CR + LF =
    /// 452 bytes per line) while I/311 `hip2.dat` is LF-only;
    /// `RecordSplitter` already strips a trailing CR, so neither needs
    /// special handling.
    public static let recordWidth = 450

    /// Hipparcos positions are on the ICRS at epoch J1991.25. The ICRS is
    /// aligned with the J2000 frame far below catalogue precision, so
    /// reaching the app's common equinox is proper-motion propagation
    /// only -- unlike RNGC (1975.0) and QSO (B1950), no precession
    /// rotation is involved.
    public static let epochOffsetYears = 2000.0 - 1991.25

    private static let masToRadians = Double.pi / (180.0 * 3600.0 * 1000.0)

    /// One parsed Hipparcos record. Missing fields are `nil`; the
    /// catalogue leaves them blank rather than using a sentinel, so no
    /// equivalent of the YBS `99.99` problem arises.
    public struct Record: Hashable, Sendable {
        public let hip: Int
        public let visualMagnitude: Double?
        /// Catalogue position at J1991.25, in degrees.
        public let raDegrees: Double?
        public let decDegrees: Double?
        public let parallaxMas: Double?
        /// mu_alpha * cos(delta), already an angular rate on the sky.
        public let pmRAMasPerYear: Double?
        public let pmDecMasPerYear: Double?
        public let ccdm: String?
        public let componentCount: Int?
        public let componentIdentifiers: String?
        public let hd: Int?
        public let spectralType: String?
        public let spectralClass: SpectralColorClass
        /// Position propagated to J2000, or nil when the record has no
        /// astrometric solution.
        public let j2000: EquatorialCoordinate?

        /// Distance implied by the parallax. Negative and zero parallaxes
        /// occur in the catalogue for distant stars whose measurement
        /// noise crosses zero; they carry no usable distance.
        public var distanceParsecs: Double? {
            guard let parallaxMas, parallaxMas > 0 else { return nil }
            return 1000.0 / parallaxMas
        }
    }

    public struct Result: Sendable {
        public let records: [Record]
        public let diagnostics: CatalogDiagnostics
    }

    public static func parse(data: Data) -> Result {
        var diagnostics = CatalogDiagnostics()
        var records: [Record] = []
        records.reserveCapacity(118_500)

        for split in RecordSplitter.records(in: data) {
            diagnostics.sourceRecords += 1
            let r = split.record

            let hip = r.intValue(at: Field.hip.start, length: Field.hip.length)
            guard hip > 0 else {
                diagnostics.skip("no HIP number")
                continue
            }

            let raDegrees = optionalDouble(r, Field.raDegrees)
            let decDegrees = optionalDouble(r, Field.decDegrees)
            let pmRA = optionalDouble(r, Field.pmRA)
            let pmDec = optionalDouble(r, Field.pmDec)

            if raDegrees == nil || decDegrees == nil {
                diagnostics.skip("no astrometric solution")
            }

            let spectralType = optionalString(r, Field.spectralType)
            let spectralClass = spectralType.map {
                SpectralColorClass(spectrumByte: Array($0.utf8)[0])
            } ?? .neutral
            if let spectralType, spectralClass == .neutral {
                diagnostics.notes.append(
                    "HIP \(hip): unmapped spectral type \(spectralType)")
            }

            var j2000: EquatorialCoordinate?
            if let raDegrees, let decDegrees {
                j2000 = propagateToJ2000(
                    raDegrees: raDegrees, decDegrees: decDegrees,
                    pmRAMasPerYear: pmRA ?? 0, pmDecMasPerYear: pmDec ?? 0)
            }

            records.append(
                Record(
                    hip: hip,
                    visualMagnitude: optionalDouble(r, Field.vmag),
                    raDegrees: raDegrees,
                    decDegrees: decDegrees,
                    parallaxMas: optionalDouble(r, Field.parallax),
                    pmRAMasPerYear: pmRA,
                    pmDecMasPerYear: pmDec,
                    ccdm: optionalString(r, Field.ccdm),
                    componentCount: optionalInt(r, Field.componentCount),
                    componentIdentifiers: optionalString(r, Field.componentIDs),
                    hd: optionalInt(r, Field.hd),
                    spectralType: spectralType,
                    spectralClass: spectralClass,
                    j2000: j2000))
        }

        diagnostics.loadedObjects = records.count
        return Result(records: records, diagnostics: diagnostics)
    }

    /// Unit-vector propagation, which stays correct at the poles where
    /// adding `pmRA / cos(delta)` to right ascension does not. Radial
    /// velocity is absent from the catalogue, so this is the standard
    /// no-radial-velocity approximation.
    public static func propagateToJ2000(
        raDegrees: Double, decDegrees: Double,
        pmRAMasPerYear: Double, pmDecMasPerYear: Double
    ) -> EquatorialCoordinate {
        let ra = raDegrees * .pi / 180
        let dec = decDegrees * .pi / 180
        let (sinRA, cosRA) = (sin(ra), cos(ra))
        let (sinDec, cosDec) = (sin(dec), cos(dec))

        let position = (cosDec * cosRA, cosDec * sinRA, sinDec)
        let raHat = (-sinRA, cosRA, 0.0)
        let decHat = (-sinDec * cosRA, -sinDec * sinRA, cosDec)

        let muRA = pmRAMasPerYear * masToRadians
        let muDec = pmDecMasPerYear * masToRadians
        let dt = epochOffsetYears

        var x = position.0 + (muRA * raHat.0 + muDec * decHat.0) * dt
        var y = position.1 + (muRA * raHat.1 + muDec * decHat.1) * dt
        var z = position.2 + (muRA * raHat.2 + muDec * decHat.2) * dt
        let norm = (x * x + y * y + z * z).squareRoot()
        x /= norm
        y /= norm
        z /= norm

        var newRA = atan2(y, x)
        if newRA < 0 { newRA += 2 * .pi }
        let newDec = asin(min(max(z, -1), 1))
        return EquatorialCoordinate(
            rightAscension: Radians(newRA), declination: Radians(newDec))
    }

    private static func optionalString(
        _ r: FixedWidthRecord, _ field: (start: Int, length: Int)
    ) -> String? {
        let value = r.trimmedField(at: field.start, length: field.length)
        return value.isEmpty ? nil : value
    }

    /// Field slicing reuses `FixedWidthRecord` unchanged, but the numeric
    /// conversion deliberately does not use its `doubleValue`. That method
    /// reimplements C `atof` digit by digit to stay bug-compatible with the
    /// legacy reader, and it is not correctly rounded -- it disagrees with
    /// `strtod` by up to one ULP on Hipparcos's eight-decimal degrees.
    /// There is no legacy Hipparcos behaviour to reproduce, so the
    /// prototype takes the correctly rounded conversion instead.
    private static func optionalDouble(
        _ r: FixedWidthRecord, _ field: (start: Int, length: Int)
    ) -> Double? {
        guard let text = optionalString(r, field) else { return nil }
        return Double(text)
    }

    private static func optionalInt(
        _ r: FixedWidthRecord, _ field: (start: Int, length: Int)
    ) -> Int? {
        guard !r.isBlank(at: field.start, length: field.length) else {
            return nil
        }
        return r.intValue(at: field.start, length: field.length)
    }
}
