import SwiftUI

struct ATCClassView: View {
    @State private var classes: [ClassInteractionRow] = []
    @State private var totalPairs = 0
    @State private var isLoading = true
    @State private var sortColumn: SortColumn = .potentialPairs
    @State private var sortAscending = false

    enum SortColumn: String {
        case atcPrefix, description, drugsInClass, drugsMentioning, potentialPairs, topKeyword
    }

    var sortedClasses: [ClassInteractionRow] {
        classes.sorted { a, b in
            let result: Bool
            switch sortColumn {
            case .atcPrefix: result = a.atcPrefix.localizedCompare(b.atcPrefix) == .orderedAscending
            case .description: result = a.description.localizedCompare(b.description) == .orderedAscending
            case .drugsInClass: result = a.drugsInClass < b.drugsInClass
            case .drugsMentioning: result = a.drugsMentioning < b.drugsMentioning
            case .potentialPairs: result = a.potentialPairs < b.potentialPairs
            case .topKeyword: result = a.topKeyword.localizedCompare(b.topKeyword) == .orderedAscending
            }
            return sortAscending ? result : !result
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack {
                        ProgressView("ATC-Klassen werden analysiert...")
                        Text("Kann einige Sekunden dauern")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                } else {
                    classTable
                }
            }
            .navigationTitle("ATC-Klassen")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadData()
            }
        }
    }

    private var classTable: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    headerCell("ATC-Code", column: .atcPrefix, width: 80)
                    headerCell("Klasse", column: .description, width: 180)
                    headerCell("Medikamente", column: .drugsInClass, width: 110)
                    headerCell("Erwähnungen", column: .drugsMentioning, width: 110)
                    headerCell("Pot. Paare", column: .potentialPairs, width: 110)
                    headerCell("Top-Keyword", column: .topKeyword, width: 160)
                }
                .background(Color(.systemGray5))

                Divider()

                // Rows
                ForEach(sortedClasses) { row in
                    HStack(spacing: 0) {
                        Text(row.atcPrefix)
                            .fontWeight(.semibold)
                            .frame(width: 80, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        Text(row.description)
                            .frame(width: 180, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        Text(formatted(row.drugsInClass))
                            .frame(width: 110, alignment: .trailing)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .monospacedDigit()
                        Text(formatted(row.drugsMentioning))
                            .frame(width: 110, alignment: .trailing)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .monospacedDigit()
                        Text(formatted(row.potentialPairs))
                            .fontWeight(.semibold)
                            .frame(width: 110, alignment: .trailing)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .monospacedDigit()
                        Text(row.topKeyword)
                            .frame(width: 160, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    .font(.callout)
                    Divider()
                }

                // Total
                HStack {
                    Text("Total: \(formatted(totalPairs)) potenzielle Klassen-Interaktionspaare in \(classes.count) ATC-Klassen")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .padding()
                }
            }
        }
    }

    private func headerCell(_ title: String, column: SortColumn, width: CGFloat) -> some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = (column == .atcPrefix || column == .description || column == .topKeyword)
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .foregroundColor(.primary)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
    }

    private func formatted(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{2019}"
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func loadData() async {
        let (total, classList) = await Task.detached(priority: .userInitiated) {
            DatabaseManager.shared.loadClassInteractions()
        }.value
        totalPairs = total
        classes = classList
        isLoading = false
    }
}
