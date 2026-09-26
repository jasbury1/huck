//
//  SearchModel.swift
//  HuckApp
//
//  Created by James Asbury on 9/26/26.
//

import SwiftUI

/// Runs the search tab's queries and holds their results.
///
/// The Algolia search API allows 10,000 requests an hour, which sounds
/// generous until you notice that the obvious implementation — search on every
/// keystroke — spends one request per character. "rust async runtime" would
/// cost twenty requests to answer one question, and a minute of browsing could
/// plausibly spend a few hundred. Three things keep that in check, in
/// descending order of how much they save:
///
///  - **Nothing is sent while the reader is still typing.** A query waits for a
///    short pause first (`typingDelay`), so the twenty-request example becomes
///    one. Deliberate changes — switching tabs, applying a filter — skip the
///    wait, since those aren't mid-thought.
///  - **Identical searches are never re-sent.** Results are kept per query, so
///    flicking between tabs, deleting a word and retyping it, or coming back
///    from a story costs nothing. Each entry keeps the pages it had already
///    loaded, so a long scroll isn't re-fetched either.
///  - **Pages are large** (see `AlgoliaAPIService.defaultHitsPerPage`), so
///    scrolling spends requests slowly.
///
/// Story results deliberately hydrate through Firebase rather than Algolia's
/// hits — see `StoryFeed.search(_:)` — so the per-story fetches behind a page
/// of results don't draw on this allowance at all.
@MainActor
@Observable
final class SearchModel {
    /// The results on screen, as the list that knows how to render them. Each
    /// case owns its own paging, so switching between them preserves both.
    enum Results {
        /// Stories, polls, Show HN, Ask HN — anything rendered as a story cell.
        case stories(StoryFeed)
        case comments(PaginatedFeed<UserComment>)
        /// At most one user: the Users tab is an exact username lookup.
        case users(PaginatedFeed<User>)
    }

    /// What to show, or `nil` when there's nothing to search for yet.
    private(set) var results: Results?

    /// The query `results` belong to. Also the guard against re-running a
    /// search that is already on screen.
    private(set) var activeQuery: SearchQuery?

    /// How long the reader has to stop typing before a request is spent.
    /// Short enough to feel immediate, long enough that a word typed at speed
    /// is one request rather than five.
    private static let typingDelay = Duration.milliseconds(300)

    /// How many searches to keep results for. Small on purpose: each entry
    /// retains every page it loaded, so this is bounded by memory, not by the
    /// request budget it protects.
    private static let cacheCapacity = 8

    private var cached: [SearchQuery: Results] = [:]
    /// `cached` keys in use order, least-recent first.
    private var recency: [SearchQuery] = []

    /// The debounced search waiting to run, cancelled whenever the query moves
    /// on. Cancellation happens before the delay elapses, so an abandoned
    /// query costs no request at all.
    private var pending: Task<Void, Never>?

    /// Points the results at `text`/`tab`/`filters`, sending a request only if
    /// that combination hasn't already been answered. Safe to call on every
    /// keystroke — that's what it's for.
    func search(text: String, tab: SearchTab, filters: SearchFilters) {
        pending?.cancel()

        let query = SearchQuery(text: text, tab: tab, filters: filters)
        guard query.isRunnable else {
            results = nil
            activeQuery = nil
            return
        }
        // Already showing exactly this.
        guard query != activeQuery else { return }

        if let hit = cached[query] {
            show(hit, for: query)
            return
        }

        // Only typing waits. A tab switch or a filter change is a decision
        // already made, and pausing on it would just feel slow.
        let isStillTyping = query.text != activeQuery?.text
        pending = Task { [weak self] in
            if isStillTyping {
                try? await Task.sleep(for: Self.typingDelay)
                guard !Task.isCancelled else { return }
            }
            guard let self else { return }
            let fresh = Self.makeResults(for: query)
            self.store(fresh, for: query)
            self.show(fresh, for: query)
        }
    }

    /// Discards everything loaded. For leaving the tab, or any point where
    /// holding a pile of results stops being worth the memory.
    func clear() {
        pending?.cancel()
        results = nil
        activeQuery = nil
        cached.removeAll()
        recency.removeAll()
    }

    /// Builds the right kind of feed for the query's category. Note that no
    /// request is made here: each feed fetches its first page when the list
    /// showing it appears, which is also what pages in the rest.
    private static func makeResults(for query: SearchQuery) -> Results {
        switch query.tab {
        case .stories, .polls, .showHN, .askHN:
            .stories(.search(query))
        case .comments:
            .comments(.searchComments(query))
        case .users:
            .users(.user(named: query.text))
        }
    }

    private func show(_ results: Results, for query: SearchQuery) {
        self.results = results
        self.activeQuery = query
        touch(query)
    }

    private func store(_ results: Results, for query: SearchQuery) {
        cached[query] = results
        touch(query)
        while cached.count > Self.cacheCapacity, let oldest = recency.first {
            recency.removeFirst()
            cached[oldest] = nil
        }
    }

    /// Marks `query` as the most recently used, so eviction drops the searches
    /// the reader is least likely to return to.
    private func touch(_ query: SearchQuery) {
        recency.removeAll { $0 == query }
        recency.append(query)
    }
}
