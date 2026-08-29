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
    /// and switching a one-page source's parameters (e.g. the main feed's filter).
    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let result = await loadPage(0)
        stories = models(for: result.ids)
        hasMore = result.hasMore
        nextPage = 1
    }

    /// Warms details and thumbnails for the window of stories following `id`.
    /// Called as each row appears; already-cached or in-flight work is skipped,
    /// so the overlapping windows from adjacent rows stay cheap.
    func prefetchAhead(after id: Int) async {
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
    /// The main feed for a filter (Top/Best/New/…). Firebase returns the whole
    /// ranked list at once, so this is a single page with no more to follow.
    static func topStories(filter: StoryFilter) -> StoryFeed {
        StoryFeed { page in
            guard page == 0 else { return ([], false) }
            return (await HackerNewsAPI.getStoryIds(filter: filter), false)
        }
    }

    /// Stories submitted by a user, paged via Algolia.
    static func userStories(username: String) -> StoryFeed {
        StoryFeed { page in
            await HackerNewsAPI.getUserStories(username: username, page: page)
        }
    }

    /// A user's favorited stories, paged via news.ycombinator.
    static func favorites(username: String) -> StoryFeed {
        StoryFeed { page in
            await HackerNewsAPI.getFavoriteStories(username: username, page: page)
        }
    }

    /// A one-page feed over an explicit, already-ordered list of story ids. Used
    /// by the recently-viewed list, whose order is decided locally (most-recent
    /// first) rather than fetched from an API.
    static func fromIDs(_ ids: [Int]) -> StoryFeed {
        StoryFeed { page in
            page == 0 ? (ids, false) : ([], false)
        }
    }
}
