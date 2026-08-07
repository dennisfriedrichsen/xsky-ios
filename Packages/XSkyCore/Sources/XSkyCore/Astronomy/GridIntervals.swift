import Foundation

/// The legacy "nice interval" tables and selection rules for coordinate
/// grid spacing, ported from grid.c. RA intervals are in thousandths of a
/// second of time; declination intervals are in hundredths of a second of
/// arc.
public enum GridIntervals {

    /// Even divisors of one hour of time, up to the two-hour maximum.
    public static let raIntervals: [Int] = [
        1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500,
        1000, 2000, 2500, 5000, 7500, 10000, 15000, 20000, 30000,
        60000, 120000, 150000, 300000, 450000, 600000, 900000, 1200000,
        1800000, 3600000, 7200000,
    ]

    /// Even divisors of ten degrees of arc, up to the 15-degree maximum.
    public static let decIntervals: [Int] = [
        1, 2, 5, 10, 20, 25, 50,
        100, 200, 250, 500, 750, 1000, 1500, 2000, 3000,
        6000, 12000, 15000, 30000, 45000, 60000, 90000, 120000, 180000,
        360000, 720000, 900000, 1800000, 3600000, 5400000,
    ]

    /// The reference chart size the legacy density rule was tuned against
    /// (the initial 400x400 window).
    public static let referenceExtent = 400.0

    /// Select the RA grid-line interval for a viewport: the largest
    /// interval that divides the chart into at least ~3 columns, with
    /// RA-line density increasing toward the poles via cos(centerDec).
    public static func raLineInterval(for viewport: ChartViewport) -> Int {
        let displayWidth =
            viewport.sizeInPoints.width * viewport.degreesPerPoint
            / Angles.degreesPerHour * 60 * 60 * 1000
        let minimumDivisions = max(
            3.0, 3.0 * viewport.sizeInPoints.width / referenceExtent)
        let cosDec = cos(viewport.center.declination.value)

        var chosen = raIntervals[0]
        for interval in raIntervals.reversed() {
            if (displayWidth / Double(interval)) / cosDec >= minimumDivisions {
                chosen = interval
                break
            }
        }
        return chosen
    }

    /// Select the declination grid-line interval: the largest interval
    /// that divides the chart into at least ~3 rows.
    public static func decLineInterval(for viewport: ChartViewport) -> Int {
        let displayHeight =
            viewport.sizeInPoints.height * viewport.degreesPerPoint * 60 * 60 * 100
        let minimumDivisions = max(
            3.0, 3.0 * viewport.sizeInPoints.height / referenceExtent)

        var chosen = decIntervals[0]
        for interval in decIntervals.reversed() {
            if displayHeight / Double(interval) >= minimumDivisions {
                chosen = interval
                break
            }
        }
        return chosen
    }

    /// All divisors of an interval, ascending (legacy
    /// `build_dot_intervals()`); used to pick sampling steps along grid
    /// lines that evenly divide the crossing interval.
    public static func divisors(of interval: Int) -> [Int] {
        guard interval > 0 else { return [] }
        var result: [Int] = []
        var d = 1
        while d * d <= interval {
            if interval % d == 0 {
                result.append(d)
                if d != interval / d { result.append(interval / d) }
            }
            d += 1
        }
        return result.sorted()
    }

    /// The largest divisor of `interval` that yields at least
    /// `dotsPerInterval` samples (legacy rule with 40 dots per interval).
    public static func samplingStep(
        dividing interval: Int, dotsPerInterval: Int = 40
    ) -> Int {
        let divs = divisors(of: interval)
        var chosen = divs.first ?? 1
        for d in divs.reversed() where interval / d >= dotsPerInterval {
            chosen = d
            break
        }
        return chosen
    }

    public static func raRadians(fromThousandths value: Int) -> Double {
        (Double(value) / (1000 * 60 * 60) * 15) / Angles.degreesPerRadian
    }

    public static func decRadians(fromHundredths value: Int) -> Double {
        (Double(value) / (100 * 60 * 60)) / Angles.degreesPerRadian
    }

    public static func raThousandths(fromRadians value: Double) -> Int {
        Int(value * Angles.degreesPerRadian * (60.0 / 15 * 60 * 1000) + 0.5)
    }

    public static func decHundredths(fromRadians value: Double) -> Int {
        // legacy (int)(x + 0.5): truncation after the offset, preserved for
        // exact grid-line placement parity at negative declinations
        Int(value * Angles.degreesPerRadian * 60 * 60 * 100 + 0.5)
    }
}
