import Foundation

/// Sexagesimal right ascension: hours, minutes, seconds, and thousandths of
/// a second of time (legacy `struct ra_pos`).
public struct SexagesimalRA: Hashable, Codable, Sendable {
    public var hours: Int
    public var minutes: Int
    public var seconds: Int
    public var thousandths: Int

    public init(hours: Int, minutes: Int, seconds: Int, thousandths: Int) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.thousandths = thousandths
    }

    /// Port of legacy `ra_to_rad()`.
    public var radians: Radians {
        let seconds = (Double(thousandths) / 1000.0 + Double(self.seconds)) / 60
        let minutes = (seconds + Double(self.minutes)) / 60
        let hours = minutes + Double(self.hours)
        return Radians(hours * Angles.degreesPerHour / Angles.degreesPerRadian)
    }

    /// Port of legacy `rad_to_ra()`: truncating field extraction with
    /// rounding applied only to the thousandths.
    public init(radians: Radians) {
        var degrees = radians.value * Angles.degreesPerRadian

        degrees -= Double(Int(degrees / 360)) * 360
        if degrees < 0 { degrees += 360 }

        let degreesPerHour = 360.0 / 24
        let degreesPerMinute = degreesPerHour / 60
        let degreesPerSecond = degreesPerMinute / 60

        var h = Int(degrees / degreesPerHour)
        degrees -= Double(h) * degreesPerHour
        var m = Int(degrees / degreesPerMinute)
        degrees -= Double(m) * degreesPerMinute
        var s = Int(degrees / degreesPerSecond)
        degrees -= Double(s) * degreesPerSecond
        var t = Int(degrees / degreesPerSecond * 1000 + 0.5)

        if t >= 1000 {
            s += 1
            t -= 1000
        }
        if s >= 60 {
            m += 1
            s -= 60
        }
        if m >= 60 {
            h += 1
            m -= 60
        }
        if h >= 24 { h -= 24 }

        self.init(hours: h, minutes: m, seconds: s, thousandths: t)
    }

    /// Display format matching the legacy center readout, e.g.
    /// `05h 36m 12s.700`.
    public var displayString: String {
        String(
            format: "%02dh %02dm %02ds.%03d", hours, minutes, seconds,
            thousandths)
    }
}

/// Sexagesimal declination: sign, degrees, minutes, seconds, and hundredths
/// of a second of arc (legacy `struct dec_pos`).
public struct SexagesimalDec: Hashable, Codable, Sendable {
    public var sign: Int
    public var degrees: Int
    public var minutes: Int
    public var seconds: Int
    public var hundredths: Int

    public init(sign: Int, degrees: Int, minutes: Int, seconds: Int, hundredths: Int) {
        self.sign = sign >= 0 ? 1 : -1
        self.degrees = degrees
        self.minutes = minutes
        self.seconds = seconds
        self.hundredths = hundredths
    }

    /// Port of legacy `dec_to_rad()`.
    public var radians: Radians {
        let seconds = (Double(hundredths) / 100.0 + Double(self.seconds)) / 60
        let minutes = (seconds + Double(self.minutes)) / 60
        let value = Double(sign) * (minutes + Double(degrees))
        return Radians(value / Angles.degreesPerRadian)
    }

    /// Port of legacy `rad_to_dec()`, including its quirks: truncating
    /// extraction, symmetry folding past 180 degrees, and the historical
    /// `* 100 + 0.5` hundredths expression (which multiplies by 100.5 and
    /// truncates - preserved because the golden fixtures pin it down).
    public init(radians: Radians) {
        var sign = radians.value < 0 ? -1 : 1
        var degrees = abs(radians.value) * Angles.degreesPerRadian

        degrees -= Double(Int(degrees / 360)) * 360
        if degrees > 180 {
            degrees -= 180
            sign = -sign
        }

        var d = Int(degrees)
        degrees -= Double(d)
        degrees *= 60
        var m = Int(degrees)
        degrees -= Double(m)
        degrees *= 60
        var s = Int(degrees)
        degrees -= Double(s)
        degrees *= 100 + 0.5
        var hh = Int(degrees)

        if hh >= 100 {
            s += 1
            hh -= 100
        }
        if s >= 60 {
            m += 1
            s -= 60
        }
        if m >= 60 {
            d += 1
            m -= 60
        }
        if d > 90 { d = 90 - (d - 90) }

        self.init(sign: sign, degrees: d, minutes: m, seconds: s, hundredths: hh)
    }

    /// Display format matching the legacy center readout, e.g.
    /// `-01d 12' 07".00`.
    public var displayString: String {
        String(
            format: "%@%02dd %02d' %02d\".%02d", sign < 0 ? "-" : "+",
            degrees, minutes, seconds, hundredths)
    }
}
