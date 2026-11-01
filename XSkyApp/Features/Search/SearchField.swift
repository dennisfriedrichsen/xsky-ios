import SwiftUI
import XSkyCore

/// The toolbar search field with grouped, ranked live suggestions.
struct SearchField: View {
    @Environment(WorkspaceModel.self) private var workspace
    var focused: FocusState<Bool>.Binding

    var body: some View {
        @Bindable var workspace = workspace
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                "Search stars, objects, constellations",
                text: $workspace.searchText
            )
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused(focused)
            .onSubmit {
                if let first = workspace.searchResults.first {
                    // drop focus so the keyboard does not return when
                    // the inspector sheet is dismissed
                    focused.wrappedValue = false
                    workspace.activate(result: first)
                }
            }
            .onChange(of: workspace.searchText) {
                workspace.updateSearchResults()
            }
            .accessibilityLabel("Search")
            .accessibilityIdentifier("search.field")

            if !workspace.searchText.isEmpty {
                Button {
                    workspace.searchText = ""
                    workspace.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.14)))
        .overlay {
            // Command-F focuses search from anywhere
            Button("") { focused.wrappedValue = true }
                .keyboardShortcut("f")
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

/// Grouped suggestion list shown over the chart while searching.
struct SearchResultsList: View {
    @Environment(WorkspaceModel.self) private var workspace
    var focused: FocusState<Bool>.Binding

    private var grouped: [(SearchResult.Rank, [SearchResult])] {
        let groups = Dictionary(
            grouping: workspace.searchResults, by: \.rank)
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.0) { rank, results in
                Section(sectionTitle(rank)) {
                    ForEach(
                        Array(results.enumerated()), id: \.offset
                    ) { _, result in
                        Button {
                            focused.wrappedValue = false
                            workspace.activate(result: result)
                        } label: {
                            HStack {
                                Text(result.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(result.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel(
                            "\(result.title), \(result.subtitle)")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.1).opacity(0.97)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(white: 0.25), lineWidth: 1))
        .accessibilityIdentifier("search.results")
    }

    private func sectionTitle(_ rank: SearchResult.Rank) -> String {
        switch rank {
        case .exactDesignation: "Designations"
        case .exactName: "Names"
        case .prefix: "Starting With"
        case .token: "Containing"
        }
    }
}
