import Foundation

/// A ranked search hit. Exact catalog identifiers rank first, then exact
/// common names, then prefix and token matches.
public struct SearchResult: Hashable, Sendable {
    public enum Target: Hashable, Sendable {
        case object(CatalogObjectID)
        case constellation(Int)
    }

    public enum Rank: Int, Comparable, Sendable {
        case exactDesignation = 0
        case exactName = 1
        case prefix = 2
        case token = 3

        public static func < (lhs: Rank, rhs: Rank) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let target: Target
    public let title: String
    public let subtitle: String
    public let raRadians: Double
    public let decRadians: Double
    public let rank: Rank
    public let catalogID: CatalogID?
}

/// Search over every loaded catalog, ported from the legacy find_*
/// routines and catalogs.doc: HR/YBS numbers, Bayer and Flamsteed
/// designations, common star names, NGC/RNGC/Messier numbers, NGC common
/// names, QSO positional designations, USER numbers and labels, and
/// constellation names. Case-insensitive and whitespace-tolerant; works
/// independently of catalog visibility.
public struct SearchEngine: Sendable {
    struct Suggestion: Sendable {
        let normalizedKey: String
        let result: SearchResult
    }

    private let suggestions: [Suggestion]
    private let catalogs: [CatalogID: LoadedCatalog]
    private let starNames: StarNameTable?
    private let ngcNames: NGCNameTable?
    private let centers: [CelestialPath.CelestialPoint]

    init(
        catalogs: [CatalogID: LoadedCatalog],
        starNames: StarNameTable?,
        ngcNames: NGCNameTable?,
        centers: [CelestialPath.CelestialPoint]
    ) {
        self.catalogs = catalogs
        self.starNames = starNames
        self.ngcNames = ngcNames
        self.centers = centers
        self.suggestions = Self.buildSuggestions(
            catalogs: catalogs, starNames: starNames, ngcNames: ngcNames,
            centers: centers)
    }

    /// Normalize a query: trim, collapse whitespace, lowercase.
    static func normalize(_ query: String) -> String {
        query.split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
            .lowercased()
    }

    /// Ranked, grouped suggestions for incremental search.
    public func suggestions(for query: String, limit: Int = 40) -> [SearchResult] {
        let q = Self.normalize(query)
        guard !q.isEmpty else { return [] }

        var seen = Set<SearchResult>()
        var results: [SearchResult] = []

        func add(_ r: SearchResult, rank: SearchResult.Rank) {
            let ranked = SearchResult(
                target: r.target, title: r.title, subtitle: r.subtitle,
                raRadians: r.raRadians, decRadians: r.decRadians, rank: rank,
                catalogID: r.catalogID)
            if seen.insert(ranked).inserted { results.append(ranked) }
        }

        // 1: exact designation forms
        for r in resolveDesignation(q) { add(r, rank: .exactDesignation) }

        // 2: exact names; 3: prefixes; 4: tokens
        for s in suggestions {
            if s.normalizedKey == q {
                add(s.result, rank: .exactName)
            }
        }
        for s in suggestions where results.count < limit * 4 {
            if s.normalizedKey.hasPrefix(q), s.normalizedKey != q {
                add(s.result, rank: .prefix)
            }
        }
        if q.count >= 3 {
            for s in suggestions where results.count < limit * 4 {
                if !s.normalizedKey.hasPrefix(q),
                    s.normalizedKey.contains(q)
                {
                    add(s.result, rank: .token)
                }
            }
        }

        results.sort {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            return $0.title.localizedStandardCompare($1.title)
                == .orderedAscending
        }
        return Array(results.prefix(limit))
    }

    /// Resolve documented designation forms exactly (legacy find_object
    /// chain). Returns every match across catalogs.
    public func resolveDesignation(_ normalizedQuery: String) -> [SearchResult] {
        let q = normalizedQuery
        var results: [SearchResult] = []

        // HR 1999 / YBS 1999
        if let rest = strip(q, prefixes: ["hr", "ybs"]),
            let number = wholeNumber(rest)
        {
            results += matchObjects { identity in
                if case .ybs(let hr, _, _, _, _) = identity { return hr == number }
                return false
            }
        }

        // NGC 7293 / RNGC 4565 (optional subletter)
        if let rest = strip(q, prefixes: ["ngc", "rngc"]) {
            let (number, letter) = numberAndLetter(rest)
            if let number {
                results += matchObjects { identity in
                    if case .rngc(let n, let sub, _) = identity {
                        if n != number { return false }
                        if let letter {
                            return sub?.lowercased() == String(letter)
                        }
                        return sub == nil
                    }
                    return false
                }
            }
        }

        // M 31
        if let rest = strip(q, prefixes: ["m"]), let number = wholeNumber(rest),
            number >= 1, number <= MessierTable.ngcNumbers.count,
            MessierTable.ngcNumbers[number - 1] != 0
        {
            let ngc = MessierTable.ngcNumbers[number - 1]
            results += matchObjects { identity in
                if case .rngc(let n, let sub, _) = identity {
                    return n == ngc && sub == nil
                }
                return false
            }
        }

        // QSO 1317-277
        if let rest = strip(q, prefixes: ["qso"]) {
            let parts = rest.split(separator: "-")
            if parts.count == 2, let raD = wholeNumber(String(parts[0])),
                let decD = wholeNumber(String(parts[1]))
            {
                results += matchObjects { identity in
                    if case .qso(let a, let b) = identity {
                        return a == raD && b == decD
                    }
                    return false
                }
            }
        }

        // USER 3
        if let rest = strip(q, prefixes: ["user"]),
            let number = wholeNumber(rest)
        {
            results += matchObjects { identity in
                if case .user(let n, _) = identity { return n == number }
                return false
            }
        }

        // Bayer (alpha Ori) and Flamsteed (61 Cygni) designations
        results += resolveBayerOrFlamsteed(q)

        return results
    }

    private func resolveBayerOrFlamsteed(_ q: String) -> [SearchResult] {
        let tokens = q.split(separator: " ")
        guard tokens.count >= 2 else { return [] }
        let constellationText = tokens.dropFirst().joined(separator: " ")
        guard let con = ConstellationTable.index(matching: constellationText)
        else { return [] }

        let first = String(tokens[0])
        if let greek = GreekLetters.names.firstIndex(of: first) {
            let bayer = greek + 1
            return matchObjects { identity in
                if case .ybs(_, let b, _, _, let c) = identity {
                    return b == bayer && c == con
                }
                return false
            }
        }
        if let flamsteed = wholeNumber(first) {
            return matchObjects { identity in
                if case .ybs(_, _, _, let f, let c) = identity {
                    return f == flamsteed && c == con
                }
                return false
            }
        }
        return []
    }

    private func matchObjects(
        _ predicate: (ObjectIdentity) -> Bool
    ) -> [SearchResult] {
        var results: [SearchResult] = []
        for catalog in catalogs.values {
            for object in catalog.objects where predicate(object.identity) {
                results.append(result(for: object, in: catalog))
            }
        }
        return results
    }

    private func result(
        for object: CatalogObject, in catalog: LoadedCatalog
    ) -> SearchResult {
        SearchResult(
            target: .object(object.id),
            title: ObjectLabels.preferredName(
                for: object, in: catalog, starNames: starNames),
            subtitle: catalog.shortName,
            raRadians: object.raRadians,
            decRadians: object.decRadians,
            rank: .exactDesignation,
            catalogID: catalog.id)
    }

    // MARK: suggestion corpus

    private static func buildSuggestions(
        catalogs: [CatalogID: LoadedCatalog],
        starNames: StarNameTable?,
        ngcNames: NGCNameTable?,
        centers: [CelestialPath.CelestialPoint]
    ) -> [Suggestion] {
        var suggestions: [Suggestion] = []

        func add(_ key: String, _ result: SearchResult) {
            let k = normalize(key)
            guard !k.isEmpty else { return }
            suggestions.append(Suggestion(normalizedKey: k, result: result))
        }

        // constellations by name and abbreviation
        for (i, entry) in ConstellationTable.entries.enumerated()
        where i < centers.count {
            let r = SearchResult(
                target: .constellation(i),
                title: entry.name,
                subtitle: "Constellation",
                raRadians: centers[i].raRadians,
                decRadians: centers[i].decRadians,
                rank: .exactName,
                catalogID: nil)
            add(entry.name, r)
            add(entry.abbreviation, r)
            add(entry.genitive, r)
        }

        var ngcObjects: [Int: (CatalogObject, LoadedCatalog)] = [:]

        for catalog in catalogs.values {
            for object in catalog.objects {
                let base = SearchResult(
                    target: .object(object.id),
                    title: ObjectLabels.preferredName(
                        for: object, in: catalog, starNames: starNames),
                    subtitle: catalog.shortName,
                    raRadians: object.raRadians,
                    decRadians: object.decRadians,
                    rank: .exactName,
                    catalogID: catalog.id)

                switch object.identity {
                case .ybs(let hr, let bayer, _, let flamsteed, let con):
                    add("HR \(hr)", base)
                    if let bayer, let con,
                        bayer >= 1, bayer <= GreekLetters.names.count
                    {
                        let genitive = ConstellationTable.entries[con].genitive
                        let abbrev =
                            ConstellationTable.entries[con].abbreviation
                        add("\(GreekLetters.names[bayer - 1]) \(genitive)", base)
                        add("\(GreekLetters.names[bayer - 1]) \(abbrev)", base)
                    }
                    if let flamsteed, let con {
                        let genitive = ConstellationTable.entries[con].genitive
                        add("\(flamsteed) \(genitive)", base)
                    }
                    if let starNames {
                        for name in starNames.names(forHR: hr) {
                            add(ObjectLabels.titlecased(name), base)
                        }
                    }

                case .rngc(let number, let subletter, let messier):
                    add("NGC \(number)\(subletter ?? "")", base)
                    if let messier { add("M \(messier)", base) }
                    if subletter == nil {
                        ngcObjects[number] = (object, catalog)
                    }

                case .qso(let raDesig, let decDesig):
                    add(
                        String(format: "QSO %04d-%03d", raDesig, decDesig),
                        base)

                case .user(let number, let label):
                    add("USER \(number)", base)
                    add(label, base)
                }
            }
        }

        // NGC common names attach to their RNGC objects
        if let ngcNames {
            for entry in ngcNames.entries where !entry.isIC {
                if let (object, catalog) = ngcObjects[entry.number] {
                    let r = SearchResult(
                        target: .object(object.id),
                        title: entry.name,
                        subtitle: "\(catalog.shortName) · NGC \(entry.number)",
                        raRadians: object.raRadians,
                        decRadians: object.decRadians,
                        rank: .exactName,
                        catalogID: catalog.id)
                    add(entry.name, r)
                }
            }
        }

        return suggestions
    }

    // MARK: helpers

    private func strip(_ q: String, prefixes: [String]) -> String? {
        for p in prefixes {
            if q.hasPrefix(p) {
                let rest = String(q.dropFirst(p.count))
                    .trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { return rest }
            }
        }
        return nil
    }

    private func wholeNumber(_ s: String) -> Int? {
        guard !s.isEmpty, s.allSatisfy(\.isNumber) else { return nil }
        return Int(s)
    }

    private func numberAndLetter(_ s: String) -> (Int?, Character?) {
        var digits = ""
        var rest = Substring(s)
        while let c = rest.first, c.isNumber {
            digits.append(c)
            rest = rest.dropFirst()
        }
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        guard let number = Int(digits) else { return (nil, nil) }
        if trimmed.count == 1, let letter = trimmed.first, letter.isLetter {
            return (number, letter)
        }
        if trimmed.isEmpty { return (number, nil) }
        return (nil, nil)
    }
}
