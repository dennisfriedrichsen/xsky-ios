import Foundation
import Testing

@testable import XSkyCore

@Suite("Search")
struct SearchEngineTests {
    let store = CatalogTestSupport.store

    private func firstResult(_ query: String) -> SearchResult? {
        store.searchEngine.suggestions(for: query).first
    }

    private func expectObject(
        _ query: String, catalog: CatalogID,
        file: StaticString = #filePath
    ) -> CatalogObject? {
        guard let result = firstResult(query),
            case .object(let id) = result.target
        else {
            Issue.record("no object result for \(query)")
            return nil
        }
        #expect(id.catalog == catalog, "\(query) resolved in \(id.catalog)")
        return store.object(id)
    }

    @Test func hrNumberForms() {
        for q in ["HR 1999", "hr1999", "YBS 1999"] {
            let object = expectObject(q, catalog: .ybs)
            if case .ybs(let hr, _, _, _, _) = object?.identity {
                #expect(hr == 1999, "\(q)")
            }
        }
    }

    @Test func bayerDesignation() {
        let object = expectObject("alpha Ori", catalog: .ybs)
        if case .ybs(let hr, _, _, _, _)? = object?.identity {
            #expect(hr == 2061)  // Betelgeuse
        }
        let genitive = expectObject("beta Ursae Majoris", catalog: .ybs)
        if case .ybs(let hr, _, _, _, _)? = genitive?.identity {
            #expect(hr == 4295)  // Merak
        }
    }

    @Test func commonNamePrefixNotCrowdedOutByBayerMatches() {
        // "Bet" is also a prefix of every "Beta <constellation>" bayer
        // designation, which used to fill the suggestion quota and push
        // Betelgeuse itself out of the results.
        let results = store.searchEngine.suggestions(for: "Bet")
        #expect(results.contains { $0.title == "Betelgeuse" })
    }

    @Test func flamsteedDesignation() {
        let object = expectObject("61 Cygni", catalog: .ybs)
        if case .ybs(let hr, _, _, _, _)? = object?.identity {
            #expect(hr == 8085 || hr == 8086)
        }
    }

    @Test func commonStarName() {
        let object = expectObject("Sirius", catalog: .ybs)
        if case .ybs(let hr, _, _, _, _)? = object?.identity {
            #expect(hr == 2491)
        }
        // case-insensitive
        #expect(firstResult("sirius") != nil)
    }

    @Test func messierAndNGCForms() {
        for q in ["M 31", "m31", "NGC 224", "RNGC 224"] {
            let object = expectObject(q, catalog: .rngc)
            if case .rngc(let n, _, _)? = object?.identity {
                #expect(n == 224, "\(q)")
            }
        }
        let helix = expectObject("NGC 7293", catalog: .rngc)
        #expect(helix?.kind == .planetaryNebula)
        _ = expectObject("RNGC 4565", catalog: .rngc)
    }

    @Test func ngcCommonName() {
        let object = expectObject("Andromeda Galaxy", catalog: .rngc)
        if case .rngc(let n, _, _)? = object?.identity {
            #expect(n == 224)
        }
    }

    @Test func qsoDesignation() {
        let object = expectObject("QSO 1317-277", catalog: .qso)
        if case .qso(let a, let b)? = object?.identity {
            #expect(a == 1317 && b == 277)
        }
    }

    @Test func constellationForms() {
        for q in ["Andromeda", "And", "Ursae Majoris", "UMa"] {
            guard let result = firstResult(q) else {
                Issue.record("no result for \(q)")
                continue
            }
            guard case .constellation = result.target else {
                Issue.record("\(q) did not resolve to a constellation")
                continue
            }
        }
    }

    @Test func rankingPrefersExactOverPrefix() {
        let results = store.searchEngine.suggestions(for: "M 3")
        let first = try! #require(results.first)
        #expect(first.rank == .exactDesignation)
        if case .object(let id) = first.target {
            let object = store.object(id)
            if case .rngc(let n, _, _)? = object?.identity {
                #expect(n == MessierTable.ngcNumbers[2])  // M 3 = NGC 5272
            }
        }
        // prefix results (M 31, M 32, ...) follow
        #expect(results.count > 1)
    }

    @Test func suggestionsAreFastEnough() {
        let engine = store.searchEngine
        let start = ContinuousClock.now
        var total = 0
        for q in ["si", "and", "M 3", "alpha", "NGC 72"] {
            total += engine.suggestions(for: q).count
        }
        let elapsed = ContinuousClock.now - start
        #expect(total > 0)
        // p95 target is 50ms per query; require the whole batch under 250ms
        #expect(elapsed < .milliseconds(250))
    }

    @Test func userCatalogSearch() {
        let parsed = UserCatalogParser.parse(
            data: try! CatalogTestSupport.data("usercat.example"),
            catalogID: .user("t"))
        var catalogs = store.catalogs
        catalogs[parsed.catalog.id] = parsed.catalog
        let engine = SearchEngine(
            catalogs: catalogs, starNames: store.starNames,
            ngcNames: store.ngcNames, centers: store.constellationCenters)
        let byNumber = engine.suggestions(for: "USER 1").first
        #expect(byNumber != nil)
        let byLabel = engine.suggestions(for: "Test Object").first
        if case .object(let id)? = byLabel?.target {
            #expect(id.catalog == parsed.catalog.id)
        } else {
            Issue.record("label search failed")
        }
    }
}
