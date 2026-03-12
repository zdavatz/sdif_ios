import Foundation
import SQLite3

final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "org.oddb.sdif.db", qos: .userInitiated)

    private init() {
        openDatabase()
    }

    deinit {
        sqlite3_close(db)
    }

    private func openDatabase() {
        guard let dbPath = Bundle.main.path(forResource: "interactions", ofType: "db") else {
            print("interactions.db not found in bundle")
            return
        }
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
            db = nil
        }
    }

    // MARK: - Drug Search

    func searchDrugs(query: String) -> [DrugResult] {
        guard let db = db, query.count >= 2 else { return [] }
        let pattern = "%\(query)%"
        let sql = """
            SELECT DISTINCT brand_name, atc_code, active_substances FROM drugs
            WHERE brand_name LIKE ?1 OR active_substances LIKE ?1
            ORDER BY brand_name LIMIT 20
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)

        var results: [DrugResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let brand = String(cString: sqlite3_column_text(stmt, 0))
            let atc = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let substances = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            results.append(DrugResult(brandName: brand, atcCode: atc, substances: substances))
        }
        return results
    }

    func searchDrugByATC(atc: String) -> DrugResult? {
        guard let db = db, !atc.isEmpty else { return nil }
        let sql = """
            SELECT brand_name, atc_code, active_substances FROM drugs
            WHERE atc_code = ?1 ORDER BY length(interactions_text) DESC LIMIT 1
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (atc as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) == SQLITE_ROW {
            let brand = String(cString: sqlite3_column_text(stmt, 0))
            let atcCode = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let substances = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            return DrugResult(brandName: brand, atcCode: atcCode, substances: substances)
        }
        return nil
    }

    // MARK: - Resolve Drug for Basket

    func resolveDrug(input: String) -> BasketDrug? {
        guard let db = db else { return nil }
        let pattern = "%\(input)%"

        // Try brand name first
        let sql1 = """
            SELECT brand_name, active_substances, atc_code, interactions_text, COALESCE(route, ''), COALESCE(combo_hint, '')
            FROM drugs WHERE brand_name LIKE ?1 ORDER BY length(interactions_text) DESC
            """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql1, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                let result = basketDrugFromRow(stmt)
                sqlite3_finalize(stmt)
                return result
            }
            sqlite3_finalize(stmt)
        }

        // Try substance name
        let sql2 = """
            SELECT DISTINCT d.brand_name, d.active_substances, d.atc_code, d.interactions_text,
                   COALESCE(d.route, ''), COALESCE(d.combo_hint, '')
            FROM substance_brand_map s JOIN drugs d ON d.brand_name = s.brand_name
            WHERE s.substance LIKE ?1 ORDER BY length(d.interactions_text) DESC LIMIT 1
            """
        let patternLower = "%\(input.lowercased())%"
        if sqlite3_prepare_v2(db, sql2, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (patternLower as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                let result = basketDrugFromRow(stmt)
                sqlite3_finalize(stmt)
                return result
            }
            sqlite3_finalize(stmt)
        }

        return nil
    }

    private func basketDrugFromRow(_ stmt: OpaquePointer?) -> BasketDrug {
        let brand = String(cString: sqlite3_column_text(stmt, 0))
        let substancesStr = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
        let atcCode = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
        let interactionsText = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
        let route = String(cString: sqlite3_column_text(stmt, 4))
        let comboHint = String(cString: sqlite3_column_text(stmt, 5))
        let substances = substancesStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        return BasketDrug(brand: brand, atcCode: atcCode, substances: substances,
                         interactionsText: interactionsText, route: route, comboHint: comboHint)
    }

    // MARK: - Substance Match Interactions

    func findSubstanceInteractions(drugBrand: String, substance: String) -> [(String, Int, String)] {
        guard let db = db else { return [] }
        let sql = "SELECT description, severity_score, severity_label FROM interactions WHERE drug_brand = ?1 AND interacting_substance = ?2"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (drugBrand as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (substance as NSString).utf8String, -1, nil)

        var results: [(String, Int, String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let desc = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let score = Int(sqlite3_column_int(stmt, 1))
            let label = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            results.append((desc, score, label))
        }
        return results
    }

    // MARK: - EPha Interactions

    func findEphaInteraction(atc1: String, atc2: String) -> (String, String, String, String, String, Int, String)? {
        guard let db = db else { return nil }
        let sql = """
            SELECT risk_class, risk_label, effect, mechanism, measures, severity_score, title
            FROM epha_interactions WHERE (atc1 = ?1 AND atc2 = ?2) OR (atc1 = ?2 AND atc2 = ?1) LIMIT 1
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (atc1 as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (atc2 as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) == SQLITE_ROW {
            let riskClass = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let riskLabel = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let effect = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let mechanism = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            let measures = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            let score = Int(sqlite3_column_int(stmt, 5))
            let title = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
            return (riskClass, riskLabel, effect, mechanism, measures, score, title)
        }
        return nil
    }

    // MARK: - Class Keywords

    func loadClassKeywords() -> [(String, [String])] {
        guard let db = db else { return [] }
        let sql = "SELECT atc_prefix, keyword FROM class_keywords ORDER BY atc_prefix"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var result: [(String, [String])] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let prefix = String(cString: sqlite3_column_text(stmt, 0))
            let keyword = String(cString: sqlite3_column_text(stmt, 1))
            if let last = result.last, last.0 == prefix {
                result[result.count - 1].1.append(keyword)
            } else {
                result.append((prefix, [keyword]))
            }
        }
        return result
    }

    // MARK: - CYP Rules

    func loadCypRules() -> [CypRule] {
        guard let db = db else { return [] }
        let sql = "SELECT enzyme, text_pattern, role, atc_prefix, substance FROM cyp_rules ORDER BY enzyme"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var map: [String: CypRule] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let enzyme = String(cString: sqlite3_column_text(stmt, 0))
            let textPattern = String(cString: sqlite3_column_text(stmt, 1))
            let role = String(cString: sqlite3_column_text(stmt, 2))
            let atcPrefix = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            let substance = sqlite3_column_text(stmt, 4).map { String(cString: $0) }

            let rule = map[enzyme] ?? CypRule(enzyme: enzyme, textPatterns: [], inhibitorAtc: [], inhibitorSubstances: [], inducerAtc: [], inducerSubstances: [])

            var patterns = rule.textPatterns
            if !patterns.contains(textPattern) { patterns.append(textPattern) }

            var iAtc = rule.inhibitorAtc
            var iSubst = rule.inhibitorSubstances
            var dAtc = rule.inducerAtc
            var dSubst = rule.inducerSubstances

            if role == "inhibitor" {
                if let atc = atcPrefix, !iAtc.contains(atc) { iAtc.append(atc) }
                if let s = substance, !iSubst.contains(s) { iSubst.append(s) }
            } else if role == "inducer" {
                if let atc = atcPrefix, !dAtc.contains(atc) { dAtc.append(atc) }
                if let s = substance, !dSubst.contains(s) { dSubst.append(s) }
            }

            map[enzyme] = CypRule(enzyme: enzyme, textPatterns: patterns,
                                  inhibitorAtc: iAtc, inhibitorSubstances: iSubst,
                                  inducerAtc: dAtc, inducerSubstances: dSubst)
        }
        return Array(map.values)
    }

    // MARK: - Clinical Search

    func searchInteractions(term: String, limit: Int, offset: Int) -> (total: Int, results: [SearchResultItem]) {
        guard let db = db else { return (0, []) }
        let pattern = "%\(term)%"

        // Count total
        var countStmt: OpaquePointer?
        let countSql = "SELECT COUNT(*) FROM interactions WHERE description LIKE ?1"
        var total = 0
        if sqlite3_prepare_v2(db, countSql, -1, &countStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(countStmt, 1, (pattern as NSString).utf8String, -1, nil)
            if sqlite3_step(countStmt) == SQLITE_ROW {
                total = Int(sqlite3_column_int(countStmt, 0))
            }
        }
        sqlite3_finalize(countStmt)

        // Also count EPha
        var ephaCountStmt: OpaquePointer?
        let ephaCountSql = "SELECT COUNT(*) FROM epha_interactions WHERE effect LIKE ?1 OR mechanism LIKE ?1 OR measures LIKE ?1"
        var ephaTotal = 0
        if sqlite3_prepare_v2(db, ephaCountSql, -1, &ephaCountStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(ephaCountStmt, 1, (pattern as NSString).utf8String, -1, nil)
            if sqlite3_step(ephaCountStmt) == SQLITE_ROW {
                ephaTotal = Int(sqlite3_column_int(ephaCountStmt, 0))
            }
        }
        sqlite3_finalize(ephaCountStmt)

        // Fetch FI results
        let fetchLimit = limit + offset
        let sql = """
            SELECT i.drug_brand, i.drug_substance, i.interacting_substance, i.interacting_brands,
                   i.description, i.severity_score, i.severity_label, COALESCE(d.route, '')
            FROM interactions i LEFT JOIN drugs d ON d.brand_name = i.drug_brand
            WHERE i.description LIKE ?1 ORDER BY i.severity_score DESC LIMIT ?2
            """
        var stmt: OpaquePointer?
        var fiResults: [SearchResultItem] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(fetchLimit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let drugBrand = String(cString: sqlite3_column_text(stmt, 0))
                let interactingSubstance = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let sevScore = Int(sqlite3_column_int(stmt, 5))
                let sevLabel = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
                let drugRoute = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""

                let (interactingBrand, interactingRoute) = bestBrandForSubstance(interactingSubstance.lowercased())

                fiResults.append(SearchResultItem(
                    drugBrand: drugBrand, drugRoute: drugRoute,
                    interactingSubstance: interactingSubstance,
                    interactingBrand: interactingBrand, interactingRoute: interactingRoute,
                    severityScore: sevScore, severityLabel: sevLabel,
                    severityIndicator: sevScore.severityIndicator,
                    description: sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "",
                    source: "Swissmedic FI"
                ))
            }
        }
        sqlite3_finalize(stmt)

        // Fetch EPha results
        let ephaSql = """
            SELECT title, effect, mechanism, measures, risk_class, risk_label, severity_score
            FROM epha_interactions WHERE effect LIKE ?1 OR mechanism LIKE ?1 OR measures LIKE ?1
            ORDER BY severity_score DESC LIMIT ?2
            """
        var ephaStmt: OpaquePointer?
        var ephaResults: [SearchResultItem] = []
        if sqlite3_prepare_v2(db, ephaSql, -1, &ephaStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(ephaStmt, 1, (pattern as NSString).utf8String, -1, nil)
            sqlite3_bind_int(ephaStmt, 2, Int32(fetchLimit))
            while sqlite3_step(ephaStmt) == SQLITE_ROW {
                let title = sqlite3_column_text(ephaStmt, 0).map { String(cString: $0) } ?? ""
                let effect = sqlite3_column_text(ephaStmt, 1).map { String(cString: $0) } ?? ""
                let mechanism = sqlite3_column_text(ephaStmt, 2).map { String(cString: $0) } ?? ""
                let measures = sqlite3_column_text(ephaStmt, 3).map { String(cString: $0) } ?? ""
                let sevScore = Int(sqlite3_column_int(ephaStmt, 6))
                let sevLabel = sqlite3_column_text(ephaStmt, 5).map { String(cString: $0) } ?? ""

                let desc = mechanism.isEmpty ? effect : "\(effect)\n\nMechanismus: \(mechanism)\n\nMassnahmen: \(measures)"

                ephaResults.append(SearchResultItem(
                    drugBrand: title, drugRoute: "",
                    interactingSubstance: "", interactingBrand: "", interactingRoute: "",
                    severityScore: sevScore, severityLabel: sevLabel,
                    severityIndicator: sevScore.severityIndicator,
                    description: desc, source: "EPha"
                ))
            }
        }
        sqlite3_finalize(ephaStmt)

        // Merge, sort, paginate
        var allResults = fiResults + ephaResults
        allResults.sort { a, b in
            if a.severityScore != b.severityScore { return a.severityScore > b.severityScore }
            return routePriority(a.drugRoute, a.interactingRoute) < routePriority(b.drugRoute, b.interactingRoute)
        }

        let paged = Array(allResults.dropFirst(offset).prefix(limit))
        return (total + ephaTotal, paged)
    }

    private func bestBrandForSubstance(_ substance: String) -> (String, String) {
        guard let db = db else { return ("", "") }
        let sql = """
            SELECT brand_name, route FROM substance_brand_map WHERE substance = ?1
            ORDER BY CASE WHEN route = '' THEN 0 WHEN route = 'p.o.' THEN 1 WHEN route = 'i.v.' THEN 2
            WHEN route = 's.c.' THEN 3 WHEN route = 'i.m.' THEN 4 ELSE 9 END LIMIT 1
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return ("", "") }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (substance as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) == SQLITE_ROW {
            let brand = String(cString: sqlite3_column_text(stmt, 0))
            let route = String(cString: sqlite3_column_text(stmt, 1))
            return (brand, route)
        }
        return ("", "")
    }

    // MARK: - Term Suggestions

    func suggestTerms(query: String) -> [TermSuggestion] {
        guard let db = db, query.count >= 2 else { return [] }
        let q = query.lowercased()
        let pattern = "%\(q)%"

        // Fetch descriptions
        var descriptions: [String] = []
        var stmt: OpaquePointer?
        let sql = "SELECT description FROM interactions WHERE description LIKE ?1 LIMIT 500"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let text = sqlite3_column_text(stmt, 0) {
                    descriptions.append(String(cString: text))
                }
            }
        }
        sqlite3_finalize(stmt)

        // EPha descriptions
        let ephaSql = """
            SELECT effect || ' ' || mechanism || ' ' || measures FROM epha_interactions
            WHERE effect LIKE ?1 OR mechanism LIKE ?1 OR measures LIKE ?1 LIMIT 500
            """
        if sqlite3_prepare_v2(db, ephaSql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let text = sqlite3_column_text(stmt, 0) {
                    descriptions.append(String(cString: text))
                }
            }
        }
        sqlite3_finalize(stmt)

        // Extract terms
        var termCounts: [String: Int] = [:]
        var formCounts: [String: [String: Int]] = [:]
        let wordBoundary = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "(),.;"))

        for desc in descriptions {
            let descLower = desc.lowercased()
            var pos = descLower.startIndex
            while let range = descLower.range(of: q, range: pos..<descLower.endIndex) {
                let absIdx = range.lowerBound
                // Expand to word boundaries
                var start = absIdx
                while start > descLower.startIndex {
                    let prev = descLower.index(before: start)
                    if wordBoundary.contains(descLower.unicodeScalars[prev]) { break }
                    start = prev
                }
                var end = range.upperBound
                while end < descLower.endIndex {
                    if wordBoundary.contains(descLower.unicodeScalars[end]) { break }
                    end = descLower.index(after: end)
                }

                let word = String(desc[start..<end]).trimmingCharacters(in: .whitespaces)
                if word.count >= q.count + 1 && word.count <= 40 {
                    let key = word.lowercased()
                    termCounts[key, default: 0] += 1
                    formCounts[key, default: [:]][word, default: 0] += 1
                }

                // Bigram: next word
                if end < desc.endIndex {
                    var nextStart = end
                    while nextStart < desc.endIndex && wordBoundary.contains(desc.unicodeScalars[nextStart]) {
                        nextStart = desc.index(after: nextStart)
                    }
                    let separator = desc[end..<nextStart]
                    if !separator.isEmpty && separator.allSatisfy({ $0.isWhitespace }) {
                        var nextEnd = nextStart
                        while nextEnd < desc.endIndex && !wordBoundary.contains(desc.unicodeScalars[nextEnd]) {
                            nextEnd = desc.index(after: nextEnd)
                        }
                        let bigram = String(desc[start..<nextEnd]).trimmingCharacters(in: .whitespaces)
                        if bigram.count > word.count + 1 && bigram.count <= 60 {
                            let key = bigram.lowercased()
                            termCounts[key, default: 0] += 1
                            formCounts[key, default: [:]][bigram, default: 0] += 1
                        }
                    }
                }

                pos = range.upperBound
            }
        }

        var suggestions = termCounts.filter { $0.value >= 2 }.map { (key, count) -> TermSuggestion in
            let display = formCounts[key]?.max(by: { $0.value < $1.value })?.key ?? key
            return TermSuggestion(term: display, count: count)
        }
        suggestions.sort { $0.count > $1.count }
        return Array(suggestions.prefix(15))
    }

    // MARK: - ATC Class Overview

    func loadClassInteractions() -> (totalPairs: Int, classes: [ClassInteractionRow]) {
        guard let db = db else { return (0, []) }

        // Load drugs with interactions
        struct DrugRow {
            let atc: String
            let substances: String
            let text: String
        }
        let sql = """
            SELECT brand_name, atc_code, active_substances, interactions_text FROM drugs
            WHERE length(interactions_text) > 0 AND atc_code IS NOT NULL AND atc_code != ''
            """
        var stmt: OpaquePointer?
        var drugs: [DrugRow] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let atc = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let substances = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let text = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
                if !atc.isEmpty && !text.isEmpty {
                    drugs.append(DrugRow(atc: atc, substances: substances, text: text))
                }
            }
        }
        sqlite3_finalize(stmt)

        let classKeywords = loadClassKeywords()

        var drugsInClass: [String: Int] = [:]
        for (prefix, _) in classKeywords {
            drugsInClass[prefix] = drugs.filter { $0.atc.hasPrefix(prefix) }.count
        }

        var totalPairs = 0
        var classes: [ClassInteractionRow] = []

        for (prefix, keywords) in classKeywords {
            let nInClass = drugsInClass[prefix] ?? 0
            if nInClass == 0 { continue }

            var mentioningSubstances = Set<String>()
            var bestKeyword = ""
            var bestCount = 0

            for kw in keywords {
                var count = 0
                for drug in drugs {
                    if drug.atc.hasPrefix(prefix) { continue }
                    if drug.text.localizedCaseInsensitiveContains(kw) {
                        mentioningSubstances.insert(drug.substances)
                        count += 1
                    }
                }
                if count > bestCount {
                    bestCount = count
                    bestKeyword = kw
                }
            }

            let nMentioning = mentioningSubstances.count
            let pairCount = nMentioning * nInClass
            totalPairs += pairCount
            classes.append(ClassInteractionRow(
                atcPrefix: prefix,
                description: Self.atcClassDescription(prefix),
                drugsInClass: nInClass,
                drugsMentioning: nMentioning,
                potentialPairs: pairCount,
                topKeyword: bestKeyword
            ))
        }

        classes.sort { $0.potentialPairs > $1.potentialPairs }
        return (totalPairs, classes)
    }

    // MARK: - Helpers

    static func atcClassDescription(_ prefix: String) -> String {
        switch prefix {
        case "B01A": return "Antikoagulantien"
        case "B01AC": return "Thrombozytenaggregationshemmer"
        case "M01A": return "NSAR (NSAIDs)"
        case "N02B": return "Analgetika / Antipyretika"
        case "N02A": return "Opioide"
        case "C09A": return "ACE-Hemmer"
        case "C09B": return "ACE-Hemmer (Kombination)"
        case "C09C": return "Sartane (AT1-Antagonisten)"
        case "C09D": return "Sartane (Kombination)"
        case "C07": return "Beta-Blocker"
        case "C08": return "Calciumkanalblocker"
        case "C03": return "Diuretika"
        case "C03C": return "Schleifendiuretika"
        case "C03A": return "Thiazide"
        case "C01A": return "Herzglykoside"
        case "C01B": return "Antiarrhythmika"
        case "C10A": return "Statine"
        case "N06AB": return "SSRIs"
        case "N06A": return "Antidepressiva"
        case "A10": return "Antidiabetika"
        case "H02": return "Corticosteroide"
        case "L04": return "Immunsuppressiva"
        case "L01": return "Antineoplastika"
        case "N03": return "Antiepileptika"
        case "N05A": return "Antipsychotika"
        case "N05B": return "Anxiolytika"
        case "N05C": return "Sedativa / Hypnotika"
        case "J01": return "Antibiotika"
        case "J01FA": return "Makrolide"
        case "J01MA": return "Fluorchinolone"
        case "J02A": return "Antimykotika"
        case "J05A": return "Antivirale"
        case "A02BC": return "PPI (Protonenpumpenhemmer)"
        case "A02B": return "Ulkusmittel"
        case "G03A": return "Hormonale Kontrazeptiva"
        case "N07": return "Nervensystem (andere)"
        case "R03": return "Bronchodilatatoren"
        case "M04": return "Gichtmittel"
        case "B03": return "Eisenpräparate"
        case "L02BA": return "SERMs (Tamoxifen)"
        case "L02B": return "Hormonantagonisten"
        case "V03AB": return "Antidota"
        case "M03A": return "Muskelrelaxantien"
        default: return ""
        }
    }

    static func atcClassDescriptionForCode(_ atcCode: String) -> String {
        let prefixes = [
            "B01AC", "B01A", "M01A", "N02B", "N02A", "C09A", "C09B", "C09C", "C09D",
            "C07", "C08", "C03C", "C03A", "C03", "C01A", "C01B", "C10A", "N06AB", "N06A",
            "A10", "H02", "L04", "L01", "N03", "N05A", "N05B", "N05C",
            "J01FA", "J01MA", "J01", "J02A", "J05A", "A02BC", "A02B", "G03A", "N07", "R03",
            "M04", "B03", "L02BA", "L02B", "V03AB", "M03A"
        ]
        for prefix in prefixes {
            if atcCode.hasPrefix(prefix) {
                return atcClassDescription(prefix)
            }
        }
        return ""
    }
}

func routePriority(_ routeA: String, _ routeB: String) -> Int {
    func single(_ r: String) -> Int {
        switch r {
        case "": return 0
        case "p.o.": return 0
        case "i.v.": return 0
        case "s.c.": return 1
        case "i.m.": return 1
        case "inhalativ": return 2
        case "nasal": return 3
        case "rektal": return 3
        case "ophthalm.": return 4
        case "otisch": return 4
        case "topisch": return 5
        default: return 3
        }
    }
    return max(single(routeA), single(routeB))
}
