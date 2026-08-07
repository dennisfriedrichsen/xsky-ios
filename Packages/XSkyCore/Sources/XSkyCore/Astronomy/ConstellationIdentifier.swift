import Foundation

/// Identifies the constellation containing a J2000 position using the
/// Herget precession to B1875 followed by Dr. Nancy G. Roman's boundary
/// table (1987, PASP, 99, 695), ported from `identify_constellation()` in
/// the legacy boundary.c. This is deliberately independent of the
/// decorative J2000 boundary drawing paths.
public struct ConstellationIdentifier: Sendable {
    private let herget = HergetPrecessionTransform(from: .j2000, to: .b1875)

    public init() {}

    /// Returns the constellation table index, or nil when the table search
    /// fails (which the legacy code treated as a mysterious failure).
    public func constellationIndex(of coordinate: EquatorialCoordinate) -> Int? {
        let (a0, d) = herget.apply(
            rightAscension: coordinate.rightAscension.value,
            declination: coordinate.declination.value)

        var a = a0
        if a < 0 { a += 2 * .pi }
        if a >= 2 * .pi { a -= 2 * .pi }

        let ra = a / (2 * .pi / 24)
        let dec = d / (2 * .pi / 360)

        let table = romanBoundaryTable
        var i = 0
        while i < table.count, table[i].declination > dec { i += 1 }

        while i < table.count {
            while i < table.count, table[i].raUpper <= ra { i += 1 }
            while i < table.count, table[i].raLower > ra { i += 1 }
            guard i < table.count else { return nil }

            if ra >= table[i].raLower, ra < table[i].raUpper,
                table[i].declination <= dec
            {
                return table[i].constellationIndex
            } else if table[i].raUpper < ra {
                continue
            } else {
                return nil
            }
        }
        return nil
    }

    public func constellation(of coordinate: EquatorialCoordinate)
        -> ConstellationTable.Entry?
    {
        guard let index = constellationIndex(of: coordinate),
            index < ConstellationTable.entries.count
        else { return nil }
        return ConstellationTable.entries[index]
    }
}

extension ConstellationTable {
    /// Case-insensitive lookup by full name, genitive, or abbreviation.
    /// Returns the table index.
    public static func index(matching query: String) -> Int? {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }
        return entries.firstIndex {
            $0.name.lowercased() == q || $0.genitive.lowercased() == q
                || $0.abbreviation.lowercased() == q
        }
    }
}
