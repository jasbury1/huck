//
//  SearchView.swift
//  HuckApp
//
//  Created by James Asbury on 12/23/25.
//

import SwiftUI

/// The search tab: one query, run against whichever Algolia category the
/// selected pill names, refined by the filters sheet in the toolbar.
///
/// The query text lives on the tab view — the search field belongs to the
/// search-role `Tab` — so it arrives here as a binding. Everything downstream
/// of it (when to actually send a request, and what to do with the results) is
/// `SearchModel`'s.
struct SearchView: View {
    @Binding var searchText: String

    /// The category being searched. Unlike the profile and likes screens, the
    /// categories aren't a swipeable pager: each tab is a separate query, and
    /// paging between six of them would run six searches to show one.
    @State private var currentTab: SearchTab = .stories

    @State private var filters = SearchFilters()
    @State private var isShowingFilters = false

    /// Runs the queries and keeps their results. Owned here so results survive
    /// tab switches and trips into a story and back.
    @State private var model = SearchModel()

    /// This tab's own navigation, so opening a result pushes within search
    /// rather than reaching into the feed tab's stack.
    @State private var path = NavigationPath()

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
        NavigationStack(path: $path) {
            searchContent
                .searchable(text: $searchText)
                // Search activates the moment this tab is selected, and by
                // default that collapses the navigation bar to focus on the
                // field — taking the title and the filter button with it. Keep
                // them on screen instead.
                .searchPresentationToolbarBehavior(.avoidHidingContent)
                .navigationTitle("Search")
                // Inline, not large: a large title would be a second "Search"
                // under the one in the bar, and the field below already
                // dominates the screen.
                .toolbarTitleDisplayMode(.inline)
                .toolbar { filterButton }
                .sheet(isPresented: $isShowingFilters) {
                    SearchFiltersView(filters: $filters, tab: currentTab)
                }
                .navigationDestination(for: ItemNavigation.self) { navigation in
                    StoryDetailsView(from: navigation, path: $path)
                }
        }
        // Results are story cells and profiles, so this stack needs the same
        // link handling and upvote/favorite gating as the feed's.
        .inAppBrowser()
        .storyActionsEnabled()
    }

    private var searchContent: some View {
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
        // One funnel for every way a search can change — the text, the
        // category, the refinements — since the model treats them as one value
        // and only spends a request when that value is new.
        .task { runSearch() }
        .onChange(of: trimmedQuery) { runSearch() }
        .onChange(of: currentTab) { runSearch() }
        .onChange(of: filters) { runSearch() }
    }

    private func runSearch() {
        model.search(text: trimmedQuery, tab: currentTab, filters: filters)
    }

    @ToolbarContentBuilder
    private var filterButton: some ToolbarContent {
        // Pinned so the filter button stays in the bar while the search field
        // is active, rather than collapsing into the overflow menu exactly when
        // it's most likely to be wanted. Absent entirely on the Users tab,
        // where a username lookup has nothing to narrow.
        if currentTab.supportsFilters {
            ToolbarItem(placement: .topBarPinnedTrailing) {
                Button {
                    isShowingFilters = true
                } label: {
                    // Filled from the tokens rather than from `filters.isActive`
                    // so the button and the strip can't disagree: a minimum
                    // comment count that doesn't apply to this tab is still
                    // remembered, but it isn't narrowing anything here.
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

    /// The results, or the prompt when there's nothing to show yet. Each
    /// category renders through the same list types as the rest of the app —
    /// story cells, the profile's comment row — so a result looks the same
    /// wherever it's found.
    @ViewBuilder
    private var results: some View {
        ScrollView {
            switch model.results {
            case nil:
                prompt
            case let .stories(feed):
                StoryList(feed: feed, path: $path, emptyState: noResults)
            case let .comments(feed):
                PaginatedList(feed: feed, emptyState: noResults) { comment in
                    UserCommentRow(comment: comment, path: $path)
                }
            case let .users(feed):
                PaginatedList(feed: feed, emptyState: noResults) { user in
                    UserResultRow(user: user, path: $path)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var prompt: EmptyFeedView {
        EmptyFeedView(
            title: "Search Hacker News",
            systemImage: "magnifyingglass",
            description: "Find stories, comments, polls, Show and Ask HN posts, and users."
        )
    }

    private var noResults: EmptyFeedView {
        EmptyFeedView(
            title: "No Results",
            systemImage: currentTab.systemImage,
            description: currentTab == .users
                // The Users tab resolves a name exactly — there's no user index
                // to match loosely — so a near miss is worth explaining.
                ? "No user named “\(trimmedQuery)”. Usernames are case-sensitive."
                : "No \(currentTab.resultNoun) match “\(trimmedQuery)”."
        )
    }
}

#Preview {
    @Previewable @State var searchText = ""
    let session = UserSession()
    SearchView(searchText: $searchText)
        .environment(session)
        .environment(InteractionStore(session: session))
        .environment(RecentlyViewedStore(session: session))
        .environment(CollectionsStore(session: session))
}
