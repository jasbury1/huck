//
//  SearchTabs.swift
//  HuckApp
//
//  Created by James Asbury on 9/23/26.
//

import SwiftUI

/// The categories of the search page.
///
/// Most tabs mirror the API rather than being an invention of our own: Algolia
/// filters a query with `tags=`, so a tab *is* a tag, and switching tabs re-runs
/// the same query against a different one. `users` is the exception — see `tag`.
/// See https://hn.algolia.com/api
enum SearchTab: CaseIterable, Hashable, Identifiable {
    case stories
    case comments
    case polls
    case showHN
    case askHN
    case users

    var id: Self { self }

    /// The value handed to Algolia's `tags` parameter for this category, or
    /// `nil` for a category that isn't a tag at all.
    ///
    /// There is no tag — or index — for people: Algolia exposes users only as
    /// `/users/:username`, an exact lookup. So the Users tab will resolve a
    /// username rather than run a search, which is why this is optional.
    var tag: String? {
        switch self {
        case .stories: "story"
        case .comments: "comment"
        case .polls: "poll"
        case .showHN: "show_hn"
        case .askHN: "ask_hn"
        case .users: nil
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .stories: "Stories"
        case .comments: "Comments"
        case .polls: "Polls"
        case .showHN: "Show HN"
        case .askHN: "Ask HN"
        case .users: "Users"
        }
    }

    var systemImage: String {
        switch self {
        case .stories: "newspaper.fill"
        case .comments: "bubble.left.and.bubble.right.fill"
        case .polls: "chart.bar.fill"
        // The same symbols the home feed uses for its Show and Ask rows, so a
        // category reads the same wherever it appears.
        case .showHN: "eye.fill"
        case .askHN: "questionmark.message.fill"
        case .users: "person.fill"
        }
    }

    var color: Color {
        switch self {
        case .stories: .orange
        case .comments: .blue
        case .polls: .purple
        case .showHN: .pink
        case .askHN: .teal
        case .users: .indigo
        }
    }

    /// Whether the filters sheet has anything to offer this category. A username
    /// lookup can't be narrowed by author, comment count, or date, so the filter
    /// button is hidden on the Users tab rather than opening an empty sheet.
    var supportsFilters: Bool {
        self != .users
    }

    /// Whether results in this category have a comment count to filter on. A
    /// comment doesn't, so that filter is hidden for it rather than shown and
    /// silently ignored.
    var supportsCommentCountFilter: Bool {
        self != .comments && supportsFilters
    }

    /// The plural noun for this category, interpolated into empty-state copy
    /// such as "No stories match …" — a plain `String` because it's a fragment
    /// of a sentence, not a key of its own.
    var resultNoun: String {
        switch self {
        case .stories: "stories"
        case .comments: "comments"
        case .polls: "polls"
        case .showHN: "Show HN posts"
        case .askHN: "Ask HN posts"
        case .users: "users"
        }
    }
}

extension SearchTab: PillTab {}
