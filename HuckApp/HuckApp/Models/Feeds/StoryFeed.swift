//
//  StoryFeed.swift
//  HuckApp
//
//  Created by James Asbury on 8/23/26.
//

import SwiftUI

/// A feed of stories built on a pluggable source of story ids. Every story
/// surface — the main feed, a user's posts, their favorites, recently viewed —
/// is the same pipeline: fetch a page of ids, turn them into retained
/// `StoryModel`s, and warm the details of the rows just ahead so scrolling
/// stays smooth. Only *where the ids come from* differs, so that is the sole
/// injected dependency (`PageLoader`); the factories below supply it.
///
/// A one-page source (the main feed's full ranked list) is just a loader that
/// answers page 0 and reports `hasMore == false` — pagination with a single
/// page. Multi-page sources (Algolia, news.ycombinator) return `hasMore` until
/// exhausted.
@MainActor
@Observable
final class StoryFeed {
    /// The stories loaded so far, in order — the table's data.
    private(set) var stories: [StoryModel] = []
    /// Whether another page remains. Starts `true` so the first `loadMore()`
    /// fetches page 0.
    private(set) var hasMore = true
    /// True while a page fetch is in flight, guarding against overlapping loads.
    private(set) var isLoading = false

    /// Zero-based index of the next page to request.
    private var nextPage = 0

    /// The filters `visibleStories` applies, and the snapshot they judge
    /// against. Set together by `applyFilters(_:context:)`.
    private(set) var filters = FeedFilters()
    private var filterContext = FeedFilterContext()

    /// The stories to show: `stories`, less any the filters leave out.
    ///
    /// Filtering is a view over what's loaded rather than a change to it, so
    /// switching a filter off brings stories back without refetching them.
    var visibleStories: [StoryModel] {
        stories.filter { filters.includes($0, in: filterContext) }
    }

    /// Whether stories were loaded but the filters left none to show — the
    /// difference between an empty feed and one the reader has emptied.
    var isFilteredEmpty: Bool {
        !stories.isEmpty && visibleStories.isEmpty
    }

    /// Retained models keyed by id. Because a story reused across cell recycling
    /// — or one that survives a `reload()` — is read from here, it renders from
    /// its already-populated instance instead of flashing a placeholder.
    private var modelsByID: [Int: StoryModel] = [:]

    /// Fetches one page of story ids and reports whether any remain after it.
    typealias PageLoader = (_ page: Int) async -> (ids: [Int], hasMore: Bool)
    private let loadPage: PageLoader

    init(loadPage: @escaping PageLoader) {
        self.loadPage = loadPage
    }

    /// Loads the next page and appends it. The first call (page 0) is the initial
    /// load, so callers never need a separate first-page path. Re-entrant calls
    /// and calls past the end of the list are no-ops.
    func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }

        let result = await loadPage(nextPage)
        stories.append(contentsOf: models(for: result.ids))
        hasMore = result.hasMore
        nextPage += 1
    }

    /// Rebuilds the feed from its first page, reusing existing model instances by
    /// id so stories still on screen don't flash placeholders. For pull-to-refresh
    /// and switching a one-page source's parameters (e.g. the main feed's kind).
    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let result = await loadPage(0)
        stories = models(for: result.ids)
        hasMore = result.hasMore
        nextPage = 1
    }

    /// Sets the filters `visibleStories` applies, with a fresh snapshot of what
    /// they judge against. Call when they change, and after a load or refresh
    /// — not as the reader browses, or a story would vanish as it's read.
    func applyFilters(_ filters: FeedFilters, context: FeedFilterContext) {
        self.filters = filters
        filterContext = context
    }

    /// Updates which stories are hidden, and nothing else in the snapshot, so
    /// a story hidden (or brought back) changes the list at once without the
    /// stories read since the last refresh dropping out with it.
    func updateHiddenIDs(_ ids: Set<Int>) {
        filterContext.hiddenIDs = ids
    }

    /// Warms details and thumbnails for the window of stories following `id`.
    /// Called as each row appears; already-cached or in-flight work is skipped,
    /// so the overlapping windows from adjacent rows stay cheap. Follows the
    /// visible stories, so the window is the rows actually about to scroll in.
    func prefetchAhead(after id: Int) async {
        let stories = visibleStories
        guard let index = stories.firstIndex(where: { $0.id == id }) else { return }
        let start = index + 1
        guard start < stories.count else { return }
        let end = min(start + HackerNewsAPI.thumbnailPrefetchWindow, stories.count)
        let ids = stories[start..<end].map(\.id)
        await HackerNewsAPI.prefetchStories(ids: ids)
        await HackerNewsAPI.prefetchThumbnails(ids: ids)
    }

    /// Maps ids to retained models, creating one per id that doesn't have an
    /// instance yet and reusing the rest.
    private func models(for ids: [Int]) -> [StoryModel] {
        ids.map { id in
            if let existing = modelsByID[id] { return existing }
            let model = StoryModel(id: id)
            modelsByID[id] = model
            return model
        }
    }
}

// MARK: - Sources

extension StoryFeed {
    /// The main feed of a kind (Top/Best/New/…). Firebase returns the whole
    /// ranked list at once, so this is a single page with no more to follow.
    static func topStories(kind: FeedKind) -> StoryFeed {
        StoryFeed { page in
            guard page == 0 else { return ([], false) }
            return (await HackerNewsAPI.getStoryIds(kind: kind), false)
        }
    }

    /// Stories submitted by a user, paged via Algolia.
    static func userStories(username: String) -> StoryFeed {
        StoryFeed { page in
            await HackerNewsAPI.getUserStories(username: username, page: page)
        }
    }

    /// A user's favorited stories, paged via news.ycombinator. Routed through
    /// `InteractionStore` rather than the API directly so that, when the list is
    /// the current user's own, each page also reconciles their favorite state —
    /// otherwise rows would show an empty heart for anything favorited outside
    /// this install.
    static func favorites(username: String, in store: InteractionStore) -> StoryFeed {
        StoryFeed { page in
            await store.favoriteStories(username: username, page: page)
        }
    }

    /// A user's liked (upvoted) stories, paged via news.ycombinator. Hacker News
    /// exposes `/upvoted` only to its owner, so in practice `username` is always
    /// the signed-in user. Routed through `InteractionStore` so each page
    /// reconciles upvote state, as `favorites` does for hearts.
    static func liked(username: String, in store: InteractionStore) -> StoryFeed {
        StoryFeed { page in
            await store.likedStories(username: username, page: page)
        }
    }

    /// The current user's recently-viewed stories, most-recent first. A one-page
    /// feed whose id list is re-read from the store on each `reload()`, so this
    /// must stay a *single* instance that is reloaded — never rebuilt — to keep
    /// its `StoryModel` cache. Rebuilding would hand each row a fresh blank model
    /// under the same id, and since the cell's fetch `.task` is keyed to that
    /// (unchanged) identity it wouldn't re-run, leaving placeholder cards.
    static func recentlyViewed(_ store: RecentlyViewedStore) -> StoryFeed {
        StoryFeed { page in
            page == 0 ? (store.viewedIDs, false) : ([], false)
        }
    }

    /// The stories in a user collection, in the order they were added. A one-page
    /// feed whose id list is re-read from the store on each `reload()`, so adding
    /// or removing a story is reflected on the next reload. Like `recentlyViewed`,
    /// keep a single instance and reload it — never rebuild — to preserve its
    /// `StoryModel` cache.
    static func collection(_ collectionID: StoryCollection.ID, in store: CollectionsStore) -> StoryFeed {
        StoryFeed { page in
            guard page == 0 else { return ([], false) }
            let ids = store.collections.first { $0.id == collectionID }?.storyIDs ?? []
            return (ids, false)
        }
    }

    /// The stories the reader has hidden, newest first: hiding keeps no order
    /// of its own, and a story's id rises with its age. Like `collection`,
    /// keep a single instance and reload it as stories are unhidden.
    static func hidden(in store: InteractionStore) -> StoryFeed {
        StoryFeed { page in
            page == 0 ? (store.hiddenIDs.sorted(by: >), false) : ([], false)
        }
    }

    /// Search results for a story-shaped category — stories, polls, Show HN,
    /// Ask HN — paged via Algolia.
    ///
    /// Algolia returns only ids here, so each story's details are then read
    /// through `StoryCache` exactly as the main feed's are. That keeps the
    /// cells, thumbnails, and prefetch-ahead identical to every other story
    /// list, and puts the per-story requests on Firebase rather than on
    /// Algolia's hourly allowance.
    static func search(_ query: SearchQuery) -> StoryFeed {
        StoryFeed { page in
            await HackerNewsAPI.searchStoryIds(
                query: query.text,
                tags: query.tags,
                numericFilters: query.numericFilters,
                page: page
            )
        }
    }

    /// A one-page feed over a fixed list of story ids — for curated, static
    /// sources such as a Huck collection.
    static func fixed(_ ids: [Int]) -> StoryFeed {
        StoryFeed { page in
            page == 0 ? (ids, false) : ([], false)
        }
    }
}
