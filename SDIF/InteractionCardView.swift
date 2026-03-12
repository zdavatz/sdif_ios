import SwiftUI

struct InteractionCardView: View {
    let severityScore: Int
    let drugLabel: String
    let severityIndicator: String
    let severityLabel: String
    let interactionType: String?
    let explanation: String?
    let description: String
    let source: String
    let fiHint: String?
    let comboHint: String?
    let drugARoute: String?
    let drugBRoute: String?

    @State private var isExpanded = false

    private var copyableText: String {
        var parts: [String] = [drugLabel]
        if !source.isEmpty { parts.append("Quelle: \(source)") }
        parts.append("Einstufung: \(severityLabel)")
        if let type = interactionType { parts.append("Typ: \(type)") }
        if let explanation = explanation, !explanation.isEmpty { parts.append(explanation) }
        parts.append(description)
        if let hint = fiHint, !hint.isEmpty { parts.append(hint) }
        if let combo = comboHint, !combo.isEmpty { parts.append(combo) }
        return parts.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(drugLabel)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if !source.isEmpty {
                        Text(source)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(source == "EPha" ? Color.pink.opacity(0.15) : Color.blue.opacity(0.15))
                            .foregroundColor(source == "EPha" ? .pink : .blue)
                            .cornerRadius(4)
                    }
                    Text(severityLabel)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(severityScore.severityColor)
                        .clipShape(Capsule())
                }
            }

            // Interaction type
            if let type = interactionType {
                let typeLabel: String = {
                    switch type {
                    case "substance": return "Substanz-Match"
                    case "class-level": return "ATC-Klasse"
                    case "epha": return "EPha"
                    case "CYP": return "CYP-Enzym"
                    default: return type
                    }
                }()
                Text(typeLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Explanation
            if let explanation = explanation, !explanation.isEmpty {
                Text(explanation)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }

            // Description
            Text(description)
                .font(.callout)
                .foregroundColor(.primary.opacity(0.8))
                .lineLimit(isExpanded ? nil : 3)

            if description.count > 150 {
                Button(isExpanded ? "weniger" : "mehr anzeigen") {
                    withAnimation { isExpanded.toggle() }
                }
                .font(.caption)
                .foregroundColor(.blue)
            }

            // FI quality hint
            if let hint = fiHint, !hint.isEmpty {
                Text(hint)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.yellow.opacity(0.15))
                    .cornerRadius(4)
            }

            // Combo hint
            if let combo = comboHint, !combo.isEmpty {
                Text(combo)
                    .font(.caption2)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .textSelection(.enabled)
        .contextMenu {
            Button {
                UIPasteboard.general.string = copyableText
            } label: {
                Label("Alles kopieren", systemImage: "doc.on.doc")
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(severityScore.severityColor)
                .frame(width: 4),
            alignment: .leading
        )
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

// Helper to format route badge
func routeBadge(_ route: String) -> String {
    route.isEmpty ? "" : " (\(route))"
}
