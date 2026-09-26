//
//  SearchQuery.swift
//  HuckApp
//
//  Created by James Asbury on 9/26/26.
//

import Foundation

/// One search as the app poses it — what to look for, in which category, with
/// which refinements — and its translation into the `tags` and `numericFilters`
/// Algolia expects.
///
/// Having a single value stand for a whole search is what lets results be
/// cached and reused: two identical queries are the same request, so the second
/// one needn't be sent. See `SearchModel`.
struct SearchQuery: Hashable {
    /// The text typed into the search field, trimmed.
    let text: String
    let tab: SearchTab
    let filters: SearchFilters

    /// Lower bound on `created_at_i`, frozen when the query was created.
    ///
    /// Deriving it per page instead would move the window between requests —
    /// "last week" meaning something slightly different for page 2 than page 1,
    /// which shifts results across the page boundary and can duplicate or skip
    /// items at the seam.
    private let earliestTimestamp: Int?

    init(text: String, tab: SearchTab, filters: SearchFilters, now: Date = .now) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tab = tab
        self.filters = filters
        self.earliestTimestamp = filters.dateRange
            .earliestDate(relativeTo: now)
            .map { Int($0.timeIntervalSince1970) }
    }

    /// Whether this is worth sending. An empty query would match everything,
    /// which is the front page, not a search.
    var isRunnable: Bool {
        !text.isEmpty
    }

    /// Algolia's `tags`, which it combines as AND: the category, plus the author
    /// filter when one is set.
    var tags: [String] {
        var tags: [String] = []
        if let tag = tab.tag {
            tags.append(tag)
        }
        if !filters.trimmedAuthor.isEmpty {
            tags.append("author_\(filters.trimmedAuthor)")
        }
        return tags
    }

    /// Algolia's `numericFilters` for the comment-count and date refinements.
    var numericFilters: [String] {
        var numeric: [String] = []
        if tab.supportsCommentCountFilter, let minimum = filters.minimumComments {
            numeric.append("num_comments>=\(minimum)")
        }
        if let earliestTimestamp {
            numeric.append("created_at_i>\(earliestTimestamp)")
        }
        return numeric
    }

    // Identity is *what* was asked, not when. `earliestTimestamp` is derived
    // from `filters.dateRange`, so equal filters already mean an equivalent
    // window — including it would make the same search typed a second later
    // miss its own cached results.
    static func == (lhs: SearchQuery, rhs: SearchQuery) -> Bool {
        lhs.text == rhs.text && lhs.tab == rhs.tab && lhs.filters == rhs.filters
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(tab)
        hasher.combine(filters)
    }
}
