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

    /// The filters to show as tokens. Not the same as `filters.isActive`: a
    /// minimum-comment count is set but inapplicable on the Comments tab, and
    /// the strip shouldn't appear empty because of it.
    private var activeFilters: [SearchFilters.ActiveFilter] {
        filters.activeFilters(for: currentTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                PillTabBar(tabs: SearchTab.allCases, selection: $currentTab)
                    .padding(.top, 8)
                if !activeFilters.isEmpty {
                    activeFilterSummary
                }
            }
            .background(cardBackgroundColor)
            Divider()
            results
        }
        .navigationTitle("Search")
        // Inline, not large: a large title would be a second "Search" under the
        // one in the bar, and the field below already dominates the screen.
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            // Pinned so the filter button stays in the bar while the search
            // field is active, rather than collapsing into the overflow menu
            // exactly when it's most likely to be wanted. Absent entirely on
            // the Users tab, where a username lookup has nothing to narrow.
            if currentTab.supportsFilters {
                ToolbarItem(placement: .topBarPinnedTrailing) {
                    Button {
                        isShowingFilters = true
                    } label: {
                        // Filled from the tokens rather than from
                        // `filters.isActive` so the button and the strip can't
                        // disagree: a minimum comment count that doesn't apply
                        // to this tab is still remembered, but it isn't
                        // narrowing anything here.
                        Label(
                            "Filters",
                            systemImage: activeFilters.isEmpty
                                ? "line.3.horizontal.decrease.circle"
                                : "line.3.horizontal.decrease.circle.fill"
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingFilters) {
            SearchFiltersView(filters: $filters, tab: currentTab)
        }
    }

    /// A quiet strip under the tabs, one token per active filter, since the
    /// toolbar button alone doesn't say *which* filters are on. Tapping a token
    /// reopens the sheet; its x drops that one filter and leaves the rest.
    ///
    /// Scrolls only when the tokens don't fit, like the tab strip above it.
    private var activeFilterSummary: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(activeFilters) { filter in
                    filterToken(filter)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// One filter as a removable token: a neutral capsule, deliberately quieter
    /// than the colored tab pills above it, since this reports state rather than
    /// offering a choice.
    private func filterToken(_ filter: SearchFilters.ActiveFilter) -> some View {
        HStack(spacing: 6) {
            Button {
                isShowingFilters = true
            } label: {
                Text(filter.label)
                    .lineLimit(1)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit filters")

            Button {
                withAnimation(.snappy(duration: 0.2)) { filters.clear(filter.kind) }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove filter: \(filter.label)")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .padding(.horizontal, 11)
        .background {
            Capsule(style: .continuous)
                .fill(Color(.secondarySystemFill))
        }
        // Removing one token should slide the others over rather than snap.
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    /// The results area. Empty for now — the query, paging, and result cells
    /// come next; this is the surrounding appearance.
    private var results: some View {
        ScrollView {
            if trimmedQuery.isEmpty {
                EmptyFeedView(
                    title: "Search Hacker News",
                    systemImage: "magnifyingglass",
                    description: "Find stories, comments, polls, Show and Ask HN posts, and users."
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
