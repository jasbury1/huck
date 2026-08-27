//
//  PaginatedFeed.swift
//  HuckApp
//
//  Created by James Asbury on 8/23/26.
//

import SwiftUI

/// A generic, append-only list that pages in more content until the source is
/// exhausted. It owns the paging state — the accumulated `items`, whether more
/// remain, and whether a fetch is in flight — and defers only the "fetch one
/// page" step to an injected closure, so each new feed is just a different
/// `PageLoader` added via a factory extension.
///
/// This is the engine for lists whose elements arrive fully-formed in the page
/// (a user's comments). Story lists — where each id must be materialized into a
/// retained `StoryModel` and its details warmed ahead of the scroll — use
/// `StoryFeed` instead.
@MainActor
@Observable
final class PaginatedFeed<Element> {
    /// Everything loaded so far, in order.
    private(set) var items: [Element] = []
    /// Whether another page remains after the ones already loaded. Starts `true`
    /// so the first `loadMore()` fetches the first page.
    private(set) var hasMore = true
    /// True while a page fetch is in flight, guarding against overlapping loads.
    private(set) var isLoading = false

    /// Zero-based index of the next page to request.
    private var nextPage = 0

    /// Fetches one page and reports whether any remain after it.
    typealias PageLoader = (_ page: Int) async -> (elements: [Element], hasMore: Bool)
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
        items.append(contentsOf: result.elements)
        hasMore = result.hasMore
        nextPage += 1
    }
}

// MARK: - Comment feeds

extension PaginatedFeed where Element == UserComment {
    /// Comments authored by a user.
    static func userComments(username: String) -> PaginatedFeed {
        PaginatedFeed { page in
            let result = await HackerNewsAPI.getUserComments(username: username, page: page)
            return (result.comments, result.hasMore)
        }
    }
}
