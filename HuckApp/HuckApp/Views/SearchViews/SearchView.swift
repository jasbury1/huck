//
//  SearchView.swift
//  HuckApp
//
//  Created by James Asbury on 12/23/25.
//

import SwiftUI

/// The search tab: one query, run against whichever Algolia tag the selected
/// pill names, refined by the filters sheet in the toolbar.
///
/// The query itself lives on the tab view — the search field belongs to the
/// search-role `Tab` — so it arrives here as a binding.
struct SearchView: View {
    @Binding var searchText: String

    /// The Algolia tag being searched. Unlike the profile and likes screens,
    /// the categories aren't a swipeable pager: each tab is a separate query,
    /// and paging between five of them would fire five searches to show one.
    @State private var currentTab: SearchTab = .stories

    @State private var filters = SearchFilters()
    @State private var isShowingFilters = false

    private let cardBackgroundColor = Color(UIColor.systemBackground)

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                PillTabBar(tabs: SearchTab.allCases, selection: $currentTab)
                    .padding(.top, 8)
                if filters.isActive {
                    activeFilterSummary
                }
            }
            .background(cardBackgroundColor)
            Divider()
            results
        }
        .navigationTitle("Search")
        .toolbar {
            // The navigation title itself is suppressed while search is active,
            // so the title is supplied as a toolbar item — which survives the
            // search presentation — rather than by `navigationTitle` alone.
            ToolbarItem(placement: .title) {
                Text("Search")
                    .font(.headline)
            }
            // Pinned so the filter button stays in the bar while the search
            // field is active, rather than collapsing into the overflow menu
            // exactly when it's most likely to be wanted.
            ToolbarItem(placement: .topBarPinnedTrailing) {
                Button {
                    isShowingFilters = true
                } label: {
                    Label(
                        "Filters",
                        systemImage: filters.isActive
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                }
            }
        }
        .sheet(isPresented: $isShowingFilters) {
            SearchFiltersView(filters: $filters, tab: currentTab)
        }
    }

    /// A quiet strip under the tabs listing what's narrowing the results, since
    /// the toolbar button alone doesn't say *which* filters are on. Tapping it
    /// reopens the sheet; the x clears everything.
    private var activeFilterSummary: some View {
        HStack(spacing: 8) {
            Button {
                isShowingFilters = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text(filters.summaryPhrases(for: currentTab).joined(separator: " · "))
                        .lineLimit(1)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                withAnimation(.snappy(duration: 0.2)) { filters = SearchFilters() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear filters")
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    /// The results area. Empty for now — the query, paging, and result cells
    /// come next; this is the surrounding appearance.
    private var results: some View {
        ScrollView {
            if trimmedQuery.isEmpty {
                EmptyFeedView(
                    title: "Search Hacker News",
                    systemImage: "magnifyingglass",
                    description: "Find stories, comments, polls, and Show or Ask HN posts."
                )
            } else {
                // TODO: Replace with the tag's result list once search is wired up.
                EmptyFeedView(
                    title: "No Results",
                    systemImage: currentTab.systemImage,
                    description: "No \(currentTab.resultNoun) match “\(trimmedQuery)”."
                )
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

#Preview {
    @Previewable @State var searchText = ""
    NavigationStack {
        SearchView(searchText: $searchText)
            .searchable(text: $searchText)
    }
}
