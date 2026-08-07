import Foundation

/// Expands RNGC description abbreviation streams into English, ported
/// from rngc_desc.c: comma-delimited pieces are matched longest-first
/// against the abbreviation table (rngc_desc.tab), with the legacy NF and
/// S ambiguity resolutions driven by object type and the rngc_ambig.dat
/// list.
public struct RNGCDescriptionExpander: Sendable {
    private struct TableEntry {
        let key: [UInt8]
        let expansion: String
    }

    private let table: [TableEntry]
    private let nfIndex: Int?
    private let sIndex: Int?
    private let notFoundIndex: Int
    private let sulenticIndex: Int
    private let spiralIndex: Int
    private let southIndex: Int
    private let ambiguousNumbers: Set<Int>

    public init(descriptionTable: Data, ambiguityList: Data) {
        var table: [TableEntry] = []
        var nfIndex: Int?
        var sIndex: Int?
        for rec in RecordSplitter.records(in: descriptionTable) {
            let line = String(decoding: rec.record.bytes, as: UTF8.self)
            guard
                let split = line.firstIndex(where: { $0 == " " || $0 == "\t" })
            else { continue }
            let key = String(line[..<split])
            let expansion = String(line[split...])
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            if key == "NF" { nfIndex = table.count }
            if key == "S" { sIndex = table.count }
            table.append(TableEntry(key: Array(key.utf8), expansion: expansion))
        }
        // legacy alternate expansions appended after the file entries
        notFoundIndex = table.count
        table.append(TableEntry(key: Array("nf".utf8), expansion: "not found"))
        sulenticIndex = table.count
        table.append(TableEntry(key: Array("s".utf8), expansion: "- Sulentic"))
        spiralIndex = table.count
        table.append(TableEntry(key: Array("s".utf8), expansion: "spiral"))
        southIndex = table.count
        table.append(TableEntry(key: Array("s".utf8), expansion: "south"))

        self.table = table
        self.nfIndex = nfIndex
        self.sIndex = sIndex

        var ambiguous = Set<Int>()
        for rec in RecordSplitter.records(in: ambiguityList) {
            let n = rec.record.intValue(at: 0, length: rec.byteRange.count)
            if n > 0 { ambiguous.insert(n) }
        }
        self.ambiguousNumbers = ambiguous
    }

    public var tableCount: Int { table.count }

    /// Expand a raw description string for the given RNGC object.
    public func expand(
        description raw: String, rngcNumber: Int, kind: ObjectKind
    ) -> String {
        let record = Array(raw.trimmingCharacters(in: .whitespaces).utf8)
        var output = ""
        var lastPieceUnmatched = false

        var i = 0
        while i < record.count {
            while i < record.count, record[i] == UInt8(ascii: " ") { i += 1 }
            if i >= record.count { break }

            // one comma/space-delimited piece
            var piece: [UInt8] = []
            while i < record.count, record[i] != UInt8(ascii: ","),
                record[i] != UInt8(ascii: " ")
            {
                piece.append(record[i])
                i += 1
            }

            var j = 0
            while j < piece.count {
                var index = longestMatch(in: piece, from: &j)

                if let nf = nfIndex, index == nf,
                    kind == .nonexistent || ambiguousNumbers.contains(rngcNumber)
                {
                    index = notFoundIndex
                }
                if let s = sIndex, index == s {
                    if kind == .nonexistent
                        || ambiguousNumbers.contains(rngcNumber)
                    {
                        index = sulenticIndex
                    } else if i < record.count, record[i] == UInt8(ascii: ",") {
                        index = spiralIndex
                    } else if rngcNumber == 5960 || rngcNumber == 6327
                        || rngcNumber == 7260
                    {
                        index = spiralIndex
                    } else {
                        index = southIndex
                    }
                }

                let expansion: String
                let unmatched = index == nil
                if let index {
                    expansion = table[index].expansion
                } else {
                    // unrecognized byte passes through (legacy fallback)
                    expansion = String(UnicodeScalar(piece[j]))
                    j += 1
                }

                if unmatched && lastPieceUnmatched {
                    // consecutive unmatched bytes join without a space
                } else if expansion.hasPrefix("?") {
                    // no space in front of a question mark
                } else if !output.isEmpty {
                    output += " "
                }
                output += expansion
                lastPieceUnmatched = unmatched
            }

            // emit the delimiter unless it is a blank between matches
            if i < record.count {
                let delim = record[i]
                if delim == UInt8(ascii: " ") {
                    if lastPieceUnmatched { output += " " }
                } else {
                    output += String(UnicodeScalar(delim))
                }
                i += 1
            }
        }
        return output
    }

    /// Longest abbreviation match at piece[j...]; advances j on a match
    /// and returns nil (leaving j unchanged) when nothing matches.
    private func longestMatch(in piece: [UInt8], from j: inout Int) -> Int? {
        var bestLength = -1
        var bestIndex: Int?
        for (index, entry) in table.enumerated() {
            let k = entry.key
            guard k.count > bestLength, j + k.count <= piece.count else {
                continue
            }
            if Array(piece[j..<(j + k.count)]) == k {
                bestLength = k.count
                bestIndex = index
            }
        }
        if let bestIndex {
            j += bestLength
            return bestIndex
        }
        return nil
    }
}
