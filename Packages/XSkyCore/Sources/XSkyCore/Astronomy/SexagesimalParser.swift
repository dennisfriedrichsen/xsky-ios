import Foundation

/// Tolerant sexagesimal input parsing, ported from `get_ra()` and
/// `get_dec()` in the legacy position.c. Accepts forms like
/// `5h 36m 12s.7`, `23h`, `-01d 12' 07"`, `90d`, with optional leading
/// zeros and a single fraction attached to the final unit.
public enum SexagesimalParser {

    /// Port of legacy `get_ra()`. Returns nil for invalid input.
    public static func parseRA(_ input: String) -> SexagesimalRA? {
        let bytes = Array(input.utf8)
        var i = 0
        var hours = 0
        var minutes = 0
        var seconds = 0
        var hourFrac = 0
        var minFrac = 0
        var secFrac = 0
        var lastUnit: UInt8 = 0

        func atEnd(_ j: Int) -> Bool {
            j >= bytes.count || bytes[j] == UInt8(ascii: "\n")
        }

        scan: while true {
            while !atEnd(i), bytes[i].isASCIIWhitespace { i += 1 }
            if atEnd(i) || bytes[i] == UInt8(ascii: ",") { break }
            if bytes[i] == UInt8(ascii: ".") { break }

            guard bytes[i].isASCIIDigit else { return nil }
            var val = 0
            while !atEnd(i), bytes[i].isASCIIDigit {
                val = val * 10 + Int(bytes[i] - UInt8(ascii: "0"))
                i += 1
            }
            let unit = atEnd(i) ? 0 : bytes[i].asciiUppercased
            switch unit {
            case UInt8(ascii: "H"):
                guard val < 24 else { return nil }
                hours = val
            case UInt8(ascii: "M"):
                guard val < 60 else { return nil }
                minutes = val
            case UInt8(ascii: "S"):
                guard val < 60 else { return nil }
                seconds = val
            default:
                return nil
            }
            lastUnit = unit
            i += 1
            if unit != UInt8(ascii: "H"), unit != UInt8(ascii: "M") {
                break scan
            }
        }

        if !atEnd(i), bytes[i] == UInt8(ascii: ".") {
            i += 1
            var digits: [UInt8] = []
            while !atEnd(i), bytes[i].isASCIIDigit, digits.count < 3 {
                digits.append(bytes[i])
                i += 1
            }
            // the fraction must end the input
            while !atEnd(i), bytes[i].isASCIIWhitespace { i += 1 }
            guard atEnd(i), !digits.isEmpty else { return nil }
            var fraction = digits.reduce(0) { $0 * 10 + Int($1 - UInt8(ascii: "0")) }
            if digits.count == 1 { fraction *= 100 }
            if digits.count == 2 { fraction *= 10 }
            switch lastUnit {
            case UInt8(ascii: "H"): hourFrac = fraction
            case UInt8(ascii: "M"): minFrac = fraction
            case UInt8(ascii: "S"): secFrac = fraction
            default: return nil
            }
        }

        var total = ((hours * 60 + minutes) * 60 + seconds) * 1000
        total += hourFrac * 60 * 60 + minFrac * 60 + secFrac

        let thousandths = total % 1000
        total /= 1000
        let s = total % 60
        total /= 60
        let m = total % 60
        let h = (total / 60) % 24
        return SexagesimalRA(hours: h, minutes: m, seconds: s, thousandths: thousandths)
    }

    /// Port of legacy `get_dec()`. Returns nil for invalid input.
    public static func parseDec(_ input: String) -> SexagesimalDec? {
        let bytes = Array(input.utf8)
        var i = 0
        var degrees = 0
        var minutes = 0
        var seconds = 0
        var degFrac = 0
        var minFrac = 0
        var secFrac = 0
        var sign = 1
        var extreme = false
        var lastUnit: UInt8 = 0

        func atEnd(_ j: Int) -> Bool {
            j >= bytes.count || bytes[j] == UInt8(ascii: "\n")
        }

        scan: while true {
            while !atEnd(i), bytes[i].isASCIIWhitespace { i += 1 }
            if atEnd(i) { break }
            if bytes[i] == UInt8(ascii: ".") { break }

            if bytes[i] == UInt8(ascii: "+") {
                sign = 1
                i += 1
                continue
            }
            if bytes[i] == UInt8(ascii: "-") {
                sign = -1
                i += 1
                continue
            }

            guard bytes[i].isASCIIDigit else { return nil }
            var val = 0
            while !atEnd(i), bytes[i].isASCIIDigit {
                val = val * 10 + Int(bytes[i] - UInt8(ascii: "0"))
                i += 1
            }
            let unit = atEnd(i) ? 0 : bytes[i].asciiUppercased
            switch unit {
            case UInt8(ascii: "D"):
                guard val <= 90 else { return nil }
                degrees = val
                if val == 90 { extreme = true }
            case UInt8(ascii: "'"):
                guard val < 60, !(extreme && val > 0) else { return nil }
                minutes = val
            case UInt8(ascii: "\""):
                guard val < 60, !(extreme && val > 0) else { return nil }
                seconds = val
            default:
                return nil
            }
            lastUnit = unit
            i += 1
            if unit != UInt8(ascii: "D"), unit != UInt8(ascii: "'") {
                break scan
            }
        }

        if !atEnd(i), bytes[i] == UInt8(ascii: ".") {
            i += 1
            var digits: [UInt8] = []
            while !atEnd(i), bytes[i].isASCIIDigit, digits.count < 3 {
                digits.append(bytes[i])
                i += 1
            }
            while !atEnd(i), bytes[i].isASCIIWhitespace { i += 1 }
            guard atEnd(i), !digits.isEmpty else { return nil }
            var fraction = digits.reduce(0) { $0 * 10 + Int($1 - UInt8(ascii: "0")) }
            if digits.count == 1 { fraction *= 10 }
            if extreme, fraction > 0 { return nil }
            switch lastUnit {
            case UInt8(ascii: "D"): degFrac = fraction
            case UInt8(ascii: "'"): minFrac = fraction
            case UInt8(ascii: "\""): secFrac = fraction
            default: return nil
            }
        }

        var total = ((degrees * 60 + minutes) * 60 + seconds) * 100
        total += degFrac * 60 * 60 + minFrac * 60 + secFrac

        let hundredths = total % 100
        total /= 100
        let s = total % 60
        total /= 60
        let m = total % 60
        let d = extreme ? 90 : (total / 60) % 90
        return SexagesimalDec(
            sign: sign, degrees: d, minutes: m, seconds: s,
            hundredths: hundredths)
    }

    /// Parse a combined `RA, Dec` position string (legacy
    /// `calculate_position()` splits on the comma).
    public static func parsePosition(_ input: String) -> EquatorialCoordinate? {
        let parts = input.split(separator: ",", maxSplits: 1)
        guard parts.count == 2,
            let ra = parseRA(String(parts[0])),
            let dec = parseDec(String(parts[1]))
        else { return nil }
        return EquatorialCoordinate(
            rightAscension: ra.radians, declination: dec.radians)
    }
}

extension UInt8 {
    var isASCIIDigit: Bool {
        self >= UInt8(ascii: "0") && self <= UInt8(ascii: "9")
    }

    var isASCIIWhitespace: Bool {
        self == UInt8(ascii: " ") || self == UInt8(ascii: "\t")
            || self == UInt8(ascii: "\r")
    }

    var asciiUppercased: UInt8 {
        (self >= UInt8(ascii: "a") && self <= UInt8(ascii: "z"))
            ? self - 32 : self
    }
}
