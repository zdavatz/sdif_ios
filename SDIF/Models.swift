import SwiftUI

struct DrugResult: Identifiable, Equatable {
    let id = UUID()
    let brandName: String
    let atcCode: String
    let substances: String
}

struct BasketDrug: Identifiable, Equatable {
    let id = UUID()
    let brand: String
    let atcCode: String
    let substances: [String]
    let interactionsText: String
    let route: String
    let comboHint: String
}

struct InteractionResult: Identifiable {
    let id = UUID()
    let drugA: String
    let drugAAtc: String
    let drugARoute: String
    let drugB: String
    let drugBAtc: String
    let drugBRoute: String
    let interactionType: String
    let severityScore: Int
    let severityLabel: String
    let severityIndicator: String
    let keyword: String
    let description: String
    let explanation: String
    let source: String
    var comboHint: String
    var fiHint: String = ""
}

struct SearchResultItem: Identifiable {
    let id = UUID()
    let drugBrand: String
    let drugRoute: String
    let interactingSubstance: String
    let interactingBrand: String
    let interactingRoute: String
    let severityScore: Int
    let severityLabel: String
    let severityIndicator: String
    let description: String
    let source: String
}

struct TermSuggestion: Identifiable {
    let id = UUID()
    let term: String
    let count: Int
}

struct ClassInteractionRow: Identifiable {
    let id = UUID()
    let atcPrefix: String
    let description: String
    let drugsInClass: Int
    let drugsMentioning: Int
    let potentialPairs: Int
    let topKeyword: String
}

struct ClassHit {
    let classKeyword: String
    let context: String
}

struct CypRule {
    let enzyme: String
    let textPatterns: [String]
    let inhibitorAtc: [String]
    let inhibitorSubstances: [String]
    let inducerAtc: [String]
    let inducerSubstances: [String]
}

extension Int {
    var severityIndicator: String {
        switch self {
        case 3: return "###"
        case 2: return "##"
        case 1: return "#"
        default: return "-"
        }
    }

    var severityLabel: String {
        switch self {
        case 3: return "Kontraindiziert"
        case 2: return "Schwerwiegend"
        case 1: return "Vorsicht"
        default: return "Keine Einstufung"
        }
    }

    var severityColor: Color {
        switch self {
        case 3: return .red
        case 2: return .orange
        case 1: return .blue
        default: return .gray
        }
    }
}
