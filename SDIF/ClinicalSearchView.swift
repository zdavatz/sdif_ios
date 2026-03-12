import SwiftUI

struct ClinicalSearchView: View {
    @State private var searchText = ""
    @State private var suggestions: [TermSuggestion] = []
    @State private var results: [SearchResultItem] = []
    @State private var totalCount = 0
    @State private var shownCount = 0
    @State private var isSearching = false
    @State private var isLoadingMore = false
    @State private var showSuggestions = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var skipNextSuggest = false

    private let pageSize = 50

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar — always visible
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Klinischer Suchbegriff (z.B. QT-Verlängerung, Blutungsrisiko)...", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onChange(of: searchText) { _, newValue in
                            if skipNextSuggest {
                                skipNextSuggest = false
                            } else {
                                debounceSuggest(newValue)
                            }
                        }
                        .onSubmit {
                            performSearch()
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            results = []
                            totalCount = 0
                            shownCount = 0
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
                    List(suggestions) { suggestion in
                        Button {
                            skipNextSuggest = true
                            searchText = suggestion.term
                            showSuggestions = false
                            suggestions = []
                            performSearch()
                        } label: {
                            HStack {
                                Text(suggestion.term)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(suggestion.count) Treffer")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                } else {
                    // Results
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if isSearching {
                                ProgressView("Suche...")
                                    .padding(.top, 40)
                            } else if !searchText.isEmpty && results.isEmpty && shownCount == 0 {
                                Text("Keine Ergebnisse für \"\(searchText)\".")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 40)
                            } else {
                                if totalCount > 0 {
                                    HStack {
                                        Text("\(totalCount) Interaktionen gefunden\(totalCount > shownCount ? " (\(shownCount) angezeigt)" : "")")
                                            .font(.callout)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                }

                                ForEach(results) { r in
                                    let brandInfo = r.interactingBrand.isEmpty ? "" : " (\(r.interactingBrand))"
                                    InteractionCardView(
                                        severityScore: r.severityScore,
                                        drugLabel: "\(r.drugBrand)\(routeBadge(r.drugRoute)) \u{2194} \(r.interactingSubstance)\(brandInfo)\(routeBadge(r.interactingRoute))",
                                        severityIndicator: r.severityIndicator,
                                        severityLabel: r.severityLabel,
                                        interactionType: nil,
                                        explanation: nil,
                                        description: r.description,
                                        source: r.source,
                                        fiHint: nil,
                                        comboHint: nil,
                                        drugARoute: r.drugRoute,
                                        drugBRoute: r.interactingRoute
                                    )
                                }

                                if shownCount < totalCount {
                                    Button {
                                        loadMore()
                                    } label: {
                                        if isLoadingMore {
                                            ProgressView()
                                        } else {
                                            Text("mehr anzeigen")
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Klinische Suche")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Actions

    private func debounceSuggest(_ query: String) {
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
            let result = await Task.detached(priority: .userInitiated) {
                DatabaseManager.shared.suggestTerms(query: q)
            }.value
            guard !Task.isCancelled else { return }
            suggestions = result
            showSuggestions = !result.isEmpty
        }
    }

    private func performSearch() {
        let term = searchText.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else { return }
        showSuggestions = false
        isSearching = true
        shownCount = 0
        let ps = pageSize

        Task {
            let (total, items) = await Task.detached(priority: .userInitiated) {
                DatabaseManager.shared.searchInteractions(term: term, limit: ps, offset: 0)
            }.value
            totalCount = total
            results = items
            shownCount = items.count
            isSearching = false
        }
    }

    private func loadMore() {
        let term = searchText.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        isLoadingMore = true
        let ps = pageSize
        let currentOffset = shownCount

        Task {
            let (_, items) = await Task.detached(priority: .userInitiated) {
                DatabaseManager.shared.searchInteractions(term: term, limit: ps, offset: currentOffset)
            }.value
            results.append(contentsOf: items)
            shownCount += items.count
            isLoadingMore = false
        }
    }
}
