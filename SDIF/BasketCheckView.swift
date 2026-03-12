import SwiftUI

struct BasketCheckView: View {
    @Binding var showSettings: Bool
    @State private var searchText = ""
    @State private var suggestions: [DrugResult] = []
    @State private var basket: [BasketDrug] = []
    @State private var interactions: [InteractionResult] = []
    @State private var isChecking = false
    @State private var showSuggestions = false
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar — always visible
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Medikament suchen (Markenname oder Wirkstoff)...", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onChange(of: searchText) { _, newValue in
                            debounceSearch(newValue)
                        }
                        .onSubmit {
                            if let first = suggestions.first {
                                addToBasket(first)
                            }
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            suggestions = []
                            showSuggestions = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 8)

                // Content below search bar
                if showSuggestions && !suggestions.isEmpty {
                    // Suggestions list
                    List(suggestions) { drug in
                        Button {
                            addToBasket(drug)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(drug.brandName)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Text("[\(drug.atcCode)] \(drug.substances)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                } else {
                    // Basket chips
                    if !basket.isEmpty {
                        basketView
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    // Results
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if isChecking {
                                ProgressView("Interaktionen werden geprüft...")
                                    .padding(.top, 40)
                            } else if basket.count >= 2 && interactions.isEmpty {
                                Text("Keine Interaktionen gefunden.")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 40)
                            } else {
                                ForEach(interactions) { ix in
                                    InteractionCardView(
                                        severityScore: ix.severityScore,
                                        drugLabel: "\(ix.drugA) [\(ix.drugAAtc)]\(routeBadge(ix.drugARoute)) \u{2194} \(ix.drugB) [\(ix.drugBAtc)]\(routeBadge(ix.drugBRoute))",
                                        severityIndicator: ix.severityIndicator,
                                        severityLabel: ix.severityLabel,
                                        interactionType: ix.interactionType,
                                        explanation: ix.explanation,
                                        description: ix.description,
                                        source: ix.source,
                                        fiHint: ix.fiHint,
                                        comboHint: ix.comboHint,
                                        drugARoute: ix.drugARoute,
                                        drugBRoute: ix.drugBRoute
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Interaktions-Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AppIconButton(showSettings: $showSettings)
                }
                if !basket.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Leeren") {
                            basket.removeAll()
                            interactions.removeAll()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Basket

    private var basketView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Medikamente im Warenkorb:")
                .font(.caption)
                .foregroundColor(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(basket) { drug in
                    HStack(spacing: 6) {
                        Text(drug.brand)
                            .fontWeight(.semibold)
                        Text("[\(drug.atcCode)]")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button {
                            removeFromBasket(drug)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.system(size: 14))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Actions

    private func debounceSearch(_ query: String) {
        debounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            suggestions = []
            showSuggestions = false
            return
        }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let q = trimmed
            let results = await Task.detached(priority: .userInitiated) {
                DatabaseManager.shared.searchDrugs(query: q)
            }.value
            guard !Task.isCancelled else { return }
            suggestions = results
            showSuggestions = !results.isEmpty
        }
    }

    private func addToBasket(_ drug: DrugResult) {
        guard !basket.contains(where: { $0.brand == drug.brandName }) else { return }
        if let resolved = DatabaseManager.shared.resolveDrug(input: drug.brandName) {
            basket.append(resolved)
        }
        searchText = ""
        suggestions = []
        showSuggestions = false
        if basket.count >= 2 {
            checkInteractions()
        }
    }

    private func removeFromBasket(_ drug: BasketDrug) {
        basket.removeAll { $0.id == drug.id }
        if basket.count >= 2 {
            checkInteractions()
        } else {
            interactions = []
        }
    }

    private func checkInteractions() {
        isChecking = true
        let drugs = basket
        Task.detached(priority: .userInitiated) {
            let result = InteractionChecker.shared.checkInteractions(basketDrugs: drugs)
            await MainActor.run {
                interactions = result
                isChecking = false
            }
        }
    }
}

// MARK: - Flow Layout for basket chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                  proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
