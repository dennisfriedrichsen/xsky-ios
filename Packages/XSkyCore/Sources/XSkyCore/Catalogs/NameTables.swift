import Foundation

/// Common star names keyed by HR number (starnames.dat), ported from
/// starnames.c. Each record is an HR number in the first five bytes and a
/// semicolon-separated name list terminated by a period; the first name is
/// primary (historically uppercased in the data).
public struct StarNameTable: Sendable {
    public struct Entry: Sendable, Hashable {
        public let hrNumber: Int
        /// All names, in file order; the primary name first.
        public let names: [String]
    }

    public let entries: [Entry]
    private let byHR: [Int: Int]

    public init(data: Data) {
        var entries: [Entry] = []
        for rec in RecordSplitter.records(in: data) {
            let r = rec.record
            let hr = r.intValue(at: 0, length: 5)
            guard hr > 0 else { continue }
            let listLength = max(0, rec.byteRange.count - 5)
            let list = r.field(at: 5, length: listLength)
            let names = list
                .split(whereSeparator: { $0 == ";" || $0 == "." })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !names.isEmpty else { continue }
            entries.append(Entry(hrNumber: hr, names: names))
        }
        self.entries = entries
        var byHR: [Int: Int] = [:]
        for (i, e) in entries.enumerated() where byHR[e.hrNumber] == nil {
            byHR[e.hrNumber] = i
        }
        self.byHR = byHR
    }

    public func names(forHR hr: Int) -> [String] {
        guard let i = byHR[hr] else { return [] }
        return entries[i].names
    }

    /// Case-insensitive name lookup returning the HR number, checking
    /// primary names before alternates (legacy find_star_by_name).
    public func hrNumber(forName name: String) -> Int? {
        let q = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }
        for e in entries where e.names[0].lowercased() == q {
            return e.hrNumber
        }
        for e in entries {
            for n in e.names.dropFirst() where n.lowercased() == q {
                return e.hrNumber
            }
        }
        return nil
    }
}

/// Common NGC/IC object names (ngc_names.dat), ported from ngc_names.c.
/// Records look like `NGC  224 Andromeda Galaxy` or `IC ...`.
public struct NGCNameTable: Sendable {
    public struct Entry: Sendable, Hashable {
        public let isIC: Bool
        public let number: Int
        public let name: String
    }

    public let entries: [Entry]

    public init(data: Data) {
        var entries: [Entry] = []
        for rec in RecordSplitter.records(in: data) {
            let r = rec.record
            let prefix = r.trimmedField(at: 0, length: 3)
            let isIC: Bool
            switch prefix {
            case "NGC": isIC = false
            case "IC": isIC = true
            default: continue
            }
            let number = r.intValue(at: 3, length: 5)
            guard number > 0 else { continue }
            let nameLength = max(0, rec.byteRange.count - 9)
            let name = r.trimmedField(at: 9, length: nameLength)
            guard !name.isEmpty else { continue }
            entries.append(Entry(isIC: isIC, number: number, name: name))
        }
        self.entries = entries
    }

    public func names(forNGC number: Int) -> [String] {
        entries.filter { !$0.isIC && $0.number == number }.map(\.name)
    }

    /// Unique case-insensitive prefix match returning the entry (legacy
    /// find_ngc_by_name declines ambiguous prefixes).
    public func entry(matchingName query: String) -> Entry? {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }
        var match: Entry?
        for e in entries where e.name.lowercased().hasPrefix(q) {
            if match != nil { return nil }
            match = e
        }
        return match
    }
}
