import Foundation

final class InteractionChecker: @unchecked Sendable {
    static let shared = InteractionChecker()
    private let db = DatabaseManager.shared

    func checkInteractions(basketDrugs: [BasketDrug]) -> [InteractionResult] {
        let classKeywords = db.loadClassKeywords()
        let cypRules = db.loadCypRules()
        let fiSource = "Swissmedic FI"

        var interactions: [InteractionResult] = []

        for i in 0..<basketDrugs.count {
            for j in (i + 1)..<basketDrugs.count {
                let a = basketDrugs[i]
                let b = basketDrugs[j]

                // Strategy 1: Substance match A->B
                for subst in b.substances {
                    let rows = db.findSubstanceInteractions(drugBrand: a.brand, substance: subst)
                    for (desc, sevScore, sevLabel) in rows {
                        interactions.append(InteractionResult(
                            drugA: a.brand, drugAAtc: a.atcCode, drugARoute: a.route,
                            drugB: b.brand, drugBAtc: b.atcCode, drugBRoute: b.route,
                            interactionType: "substance", severityScore: sevScore,
                            severityLabel: sevLabel, severityIndicator: sevScore.severityIndicator,
                            keyword: subst, description: desc,
                            explanation: "Wirkstoff \u{ab}\(subst)\u{bb} wird in der Fachinformation von \(a.brand) erwähnt",
                            source: fiSource, comboHint: ""
                        ))
                    }
                }

                // Substance match B->A
                for subst in a.substances {
                    let rows = db.findSubstanceInteractions(drugBrand: b.brand, substance: subst)
                    for (desc, sevScore, sevLabel) in rows {
                        interactions.append(InteractionResult(
                            drugA: b.brand, drugAAtc: b.atcCode, drugARoute: b.route,
                            drugB: a.brand, drugBAtc: a.atcCode, drugBRoute: a.route,
                            interactionType: "substance", severityScore: sevScore,
                            severityLabel: sevLabel, severityIndicator: sevScore.severityIndicator,
                            keyword: subst, description: desc,
                            explanation: "Wirkstoff \u{ab}\(subst)\u{bb} wird in der Fachinformation von \(b.brand) erwähnt",
                            source: fiSource, comboHint: ""
                        ))
                    }
                }

                // Strategy 2: Class-level A->B
                for hit in findClassInteractions(a.interactionsText, b.atcCode, classKeywords) {
                    let (sevScore, sevLabel) = scoreSeverity(hit.context)
                    let classDesc = DatabaseManager.atcClassDescriptionForCode(b.atcCode)
                    interactions.append(InteractionResult(
                        drugA: a.brand, drugAAtc: a.atcCode, drugARoute: a.route,
                        drugB: b.brand, drugBAtc: b.atcCode, drugBRoute: b.route,
                        interactionType: "class-level", severityScore: sevScore,
                        severityLabel: sevLabel, severityIndicator: sevScore.severityIndicator,
                        keyword: hit.classKeyword, description: hit.context,
                        explanation: "\(b.brand) [\(b.atcCode)] gehört zur Klasse \(classDesc) — Keyword \u{ab}\(hit.classKeyword)\u{bb} gefunden in Fachinformation von \(a.brand)",
                        source: fiSource, comboHint: ""
                    ))
                }
                // Class-level B->A
                for hit in findClassInteractions(b.interactionsText, a.atcCode, classKeywords) {
                    let (sevScore, sevLabel) = scoreSeverity(hit.context)
                    let classDesc = DatabaseManager.atcClassDescriptionForCode(a.atcCode)
                    interactions.append(InteractionResult(
                        drugA: b.brand, drugAAtc: b.atcCode, drugARoute: b.route,
                        drugB: a.brand, drugBAtc: a.atcCode, drugBRoute: a.route,
                        interactionType: "class-level", severityScore: sevScore,
                        severityLabel: sevLabel, severityIndicator: sevScore.severityIndicator,
                        keyword: hit.classKeyword, description: hit.context,
                        explanation: "\(a.brand) [\(a.atcCode)] gehört zur Klasse \(classDesc) — Keyword \u{ab}\(hit.classKeyword)\u{bb} gefunden in Fachinformation von \(b.brand)",
                        source: fiSource, comboHint: ""
                    ))
                }

                // Strategy 3: CYP A->B
                for hit in findCypInteractions(a.interactionsText, b.atcCode, b.substances, cypRules) {
                    let (sevScore, sevLabel) = scoreSeverity(hit.context)
                    interactions.append(InteractionResult(
                        drugA: a.brand, drugAAtc: a.atcCode, drugARoute: a.route,
                        drugB: b.brand, drugBAtc: b.atcCode, drugBRoute: b.route,
                        interactionType: "CYP", severityScore: sevScore,
                        severityLabel: sevLabel, severityIndicator: sevScore.severityIndicator,
                        keyword: hit.classKeyword, description: hit.context,
                        explanation: "\(b.brand) ist \(hit.classKeyword) — Fachinformation von \(a.brand) erwähnt dieses Enzym",
                        source: fiSource, comboHint: ""
                    ))
                }
                // CYP B->A
                for hit in findCypInteractions(b.interactionsText, a.atcCode, a.substances, cypRules) {
                    let (sevScore, sevLabel) = scoreSeverity(hit.context)
                    interactions.append(InteractionResult(
                        drugA: b.brand, drugAAtc: b.atcCode, drugARoute: b.route,
                        drugB: a.brand, drugBAtc: a.atcCode, drugBRoute: a.route,
                        interactionType: "CYP", severityScore: sevScore,
                        severityLabel: sevLabel, severityIndicator: sevScore.severityIndicator,
                        keyword: hit.classKeyword, description: hit.context,
                        explanation: "\(a.brand) ist \(hit.classKeyword) — Fachinformation von \(b.brand) erwähnt dieses Enzym",
                        source: fiSource, comboHint: ""
                    ))
                }

                // Strategy 4: EPha
                if let epha = db.findEphaInteraction(atc1: a.atcCode, atc2: b.atcCode) {
                    let (riskClass, riskLabel, effect, mechanism, measures, sevScore, _) = epha
                    let desc = mechanism.isEmpty ? effect : "\(effect)\n\nMechanismus: \(mechanism)\n\nMassnahmen: \(measures)"
                    interactions.append(InteractionResult(
                        drugA: a.brand, drugAAtc: a.atcCode, drugARoute: a.route,
                        drugB: b.brand, drugBAtc: b.atcCode, drugBRoute: b.route,
                        interactionType: "epha", severityScore: sevScore,
                        severityLabel: riskLabel, severityIndicator: sevScore.severityIndicator,
                        keyword: riskClass, description: desc,
                        explanation: "EPha Interaktionsdatenbank (ATC \(a.atcCode) \u{2194} \(b.atcCode))",
                        source: "EPha", comboHint: ""
                    ))
                }
            }
        }

        // Set combo hints
        let comboHints: [String: String] = Dictionary(
            basketDrugs.filter { !$0.comboHint.isEmpty }.map { ($0.brand, $0.comboHint) },
            uniquingKeysWith: { a, _ in a }
        )
        for i in 0..<interactions.count {
            if let hint = comboHints[interactions[i].drugA], !hint.isEmpty {
                interactions[i].comboHint = "\(interactions[i].drugA): \(hint)"
            } else if let hint = comboHints[interactions[i].drugB], !hint.isEmpty {
                interactions[i].comboHint = "\(interactions[i].drugB): \(hint)"
            }
        }

        // Sort by severity desc, then route priority
        interactions.sort { a, b in
            if a.severityScore != b.severityScore { return a.severityScore > b.severityScore }
            return routePriority(a.drugARoute, a.drugBRoute) < routePriority(b.drugARoute, b.drugBRoute)
        }

        // Add FI quality hints for asymmetric severity
        var pairMax: [String: Int] = [:]
        for ix in interactions {
            let key = [ix.drugA, ix.drugB].sorted().joined(separator: "||")
            pairMax[key] = max(pairMax[key] ?? 0, ix.severityScore)
        }
        for i in 0..<interactions.count {
            let key = [interactions[i].drugA, interactions[i].drugB].sorted().joined(separator: "||")
            if let maxSev = pairMax[key], interactions[i].severityScore < maxSev {
                interactions[i].fiHint = "Gegenrichtung hat höhere Einstufung — diese FI stuft die Interaktion tiefer ein"
            }
        }

        return interactions
    }

    // MARK: - Severity Scoring

    func scoreSeverity(_ text: String) -> (Int, String) {
        let lower = text.lowercased()
        let stripped = stripSectionReferences(lower)

        let contraindicated = [
            "kontraindiziert", "kontraindikation", "darf nicht",
            "nicht angewendet werden", "nicht verabreicht werden",
            "nicht kombiniert werden", "nicht gleichzeitig",
            "ist verboten", "absolut kontraindiziert", "streng kontraindiziert",
            "nicht zusammen", "nicht eingenommen werden", "nicht anwenden"
        ]
        for kw in contraindicated {
            if stripped.contains(kw) { return (3, "Kontraindiziert") }
        }

        let serious = [
            "erhöhtes risiko", "erhöhte gefahr", "schwerwiegend", "schwere",
            "lebensbedrohlich", "lebensgefährlich", "gefährlich",
            "stark erhöht", "stark verstärkt", "toxisch", "toxizität",
            "nephrotoxisch", "hepatotoxisch", "ototoxisch", "neurotoxisch", "kardiotoxisch",
            "tödlich", "fatale", "blutungsrisiko", "blutungsgefahr",
            "serotoninsyndrom", "serotonin-syndrom", "qt-verlängerung", "qt-zeit-verlängerung",
            "torsade", "rhabdomyolyse", "nierenversagen", "niereninsuffizienz",
            "nierenfunktionsstörung", "leberversagen", "atemdepression", "herzstillstand",
            "arrhythmie", "hyperkaliämie", "agranulozytos", "stevens-johnson", "anaphyla",
            "lymphoproliferation", "immundepression", "immunsuppression", "panzytopenie",
            "abgeraten", "wird nicht empfohlen"
        ]
        for kw in serious {
            if lower.contains(kw) { return (2, "Schwerwiegend") }
        }

        let caution = [
            "vorsicht", "überwach", "monitor", "kontroll", "engmaschig",
            "dosisanpassung", "dosis reduz", "dosis anpassen", "dosisreduktion",
            "sorgfältig", "regelmässig", "regelmäßig", "aufmerksam", "cave", "beobacht",
            "verstärkt", "vermindert", "abgeschwächt", "erhöh", "erniedrigt", "beeinflusst",
            "wechselwirkung", "plasmaspiegel", "plasmakonzentration", "serumkonzentration",
            "bioverfügbarkeit", "subtherapeutisch", "supratherapeutisch",
            "therapieversagen", "wirkungsverlust", "wirkverlust"
        ]
        for kw in caution {
            if lower.contains(kw) { return (1, "Vorsicht") }
        }

        return (0, "Keine Einstufung")
    }

    private func stripSectionReferences(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\u{ab}", with: "")
            .replacingOccurrences(of: "\u{bb}", with: "")

        if result.hasPrefix("kontraindiziert!") {
            result = String(result.dropFirst("kontraindiziert!".count)).trimmingCharacters(in: .whitespaces)
        }

        let patterns = [
            "siehe kontraindikation", "siehe rubrik kontraindikation",
            "siehe abschnitt kontraindikation", "siehe auch kontraindikation",
            "siehe auch rubrik kontraindikation", "siehe kapitel kontraindikation"
        ]
        for pat in patterns {
            while let range = result.range(of: pat) {
                var start = range.lowerBound
                if start > result.startIndex {
                    let prev = result.index(before: start)
                    if result[prev] == "(" { start = prev }
                }
                let rest = result[range.lowerBound...]
                var end = rest.endIndex
                for (idx, ch) in rest.enumerated() {
                    if ".;)\n".contains(ch) {
                        end = rest.index(rest.startIndex, offsetBy: idx + 1)
                        break
                    }
                }
                result.replaceSubrange(start..<end, with: " ")
            }
        }
        return result
    }

    // MARK: - Class Interaction Detection

    func findClassInteractions(_ interactionText: String, _ otherAtc: String, _ classKeywords: [(String, [String])]) -> [ClassHit] {
        let textLower = interactionText.lowercased()
        var hits: [ClassHit] = []

        for (atcPrefix, keywords) in classKeywords {
            guard otherAtc.hasPrefix(atcPrefix) else { continue }
            for keyword in keywords {
                if textLower.contains(keyword) {
                    let context = extractContext(interactionText, keyword)
                    if !context.isEmpty {
                        hits.append(ClassHit(classKeyword: keyword, context: context))
                        break
                    }
                }
            }
        }
        return hits
    }

    // MARK: - CYP Interaction Detection

    func findCypInteractions(_ interactionText: String, _ otherAtc: String, _ otherSubstances: [String], _ cypRules: [CypRule]) -> [ClassHit] {
        let textLower = interactionText.lowercased()
        let otherSubstLower = otherSubstances.map { $0.lowercased() }
        var hits: [ClassHit] = []

        for rule in cypRules {
            let mentioned = rule.textPatterns.contains { textLower.contains($0) }
            guard mentioned else { continue }

            let isInhibitor = rule.inhibitorAtc.contains { otherAtc.hasPrefix($0) }
                || rule.inhibitorSubstances.contains { s in otherSubstLower.contains(s) }
            let isInducer = rule.inducerAtc.contains { otherAtc.hasPrefix($0) }
                || rule.inducerSubstances.contains { s in otherSubstLower.contains(s) }

            if isInhibitor || isInducer {
                let role = isInhibitor ? "Hemmer" : "Induktor"
                let pattern = rule.textPatterns[0]
                let context = extractContext(interactionText, pattern)
                if !context.isEmpty {
                    hits.append(ClassHit(classKeyword: "\(rule.enzyme)-\(role)", context: context))
                }
            }
        }
        return hits
    }

    // MARK: - Context Extraction

    func extractContext(_ text: String, _ substance: String) -> String {
        let lower = text.lowercased()
        var bestSnippet = ""
        var bestSeverity = 0
        var bestIsAnimal = false
        var searchFrom = lower.startIndex

        while let range = lower.range(of: substance, range: searchFrom..<lower.endIndex) {
            let pos = range.lowerBound

            // Find sentence start
            var start = lower.startIndex
            if let dotRange = lower[lower.startIndex..<pos].range(of: ".", options: .backwards) {
                start = lower.index(after: dotRange.lowerBound)
            } else if let colonRange = lower[lower.startIndex..<pos].range(of: ":", options: .backwards) {
                start = lower.index(after: colonRange.lowerBound)
            }

            // Find sentence end
            var end = lower.endIndex
            if let dotRange = lower[pos...].range(of: ".") {
                end = lower.index(after: dotRange.lowerBound)
            }

            let snippet = String(text[start..<end]).trimmingCharacters(in: .whitespaces)
            let (sev, _) = scoreSeverity(snippet)

            let prefixLower = String(lower[start..<pos])
            let isAnimalModel = prefixLower.contains("tiermodell")
                || prefixLower.contains("tierstudie")
                || prefixLower.contains("tierversuch")
            let effectiveSev = isAnimalModel ? 0 : sev

            let dominated = effectiveSev > bestSeverity
                || (effectiveSev == bestSeverity && bestIsAnimal && !isAnimalModel)
                || bestSnippet.isEmpty

            if dominated {
                bestSeverity = effectiveSev
                bestIsAnimal = isAnimalModel
                if snippet.count > 500 {
                    let idx = snippet.index(snippet.startIndex, offsetBy: 497, limitedBy: snippet.endIndex) ?? snippet.endIndex
                    bestSnippet = String(snippet[..<idx]) + "..."
                } else {
                    bestSnippet = snippet
                }
                if bestSeverity >= 3 { break }
            }

            searchFrom = range.upperBound
        }

        return bestSnippet
    }
}
