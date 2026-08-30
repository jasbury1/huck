//
//  Stories.swift
//  HuckApp
//
//  Created by James Asbury on 12/28/25.
//

import SwiftUI

enum StoryFilter {
    case topStories
    case bestStories
    case newStories
    case askStories
    case showStories
    case jobStories
    
    func displayName() -> String {
        switch self {
        case .topStories:
            return "Top Stories"
        case .bestStories:
            return "Best Stories"
        case .newStories:
            return "New Stories"
        case .askStories:
            return "Ask Hacker News"
        case .showStories:
            return "Show Hacker News"
        case .jobStories:
            return "Job Listings"
        }
    }

    /// Short name used in the feed's search field prompt, e.g. "Search Jobs".
    var searchName: String {
        switch self {
        case .topStories:
            return "Top Stories"
        case .bestStories:
            return "Best Stories"
        case .newStories:
            return "New Stories"
        case .askStories:
            return "Ask HN"
        case .showStories:
            return "Show HN"
        case .jobStories:
            return "Jobs"
        }
    }
}

enum StoryType {
    case link
    case text
    case unknown
}

enum ThumbnailType {
    case loading
    case image(Image)
    case failed
    case text
}

/// An immutable, write-once snapshot of a story's server-fetched content.
///
/// A `StoryModel` is populated exactly once by `fetchData()` and never mutated
/// afterward, so the same story shown by multiple instances (feed row, comments
/// view, profile) always reads identically. All *mutable*, user-derived state —
/// upvotes and their optimistic effect on the score, saves, hides — lives in
/// `InteractionStore`, keyed by story id, rather than on these per-view instances.
///
/// This is a deliberate design rule; see `docs/story-state-ownership.md`. The
/// fetched properties are `private(set)` to enforce it: mutating one instance's
/// content would silently desync the others (this is what caused the upvote score
/// drift bug). If a field ever needs to change over time (e.g. a live-refreshing
/// score), route it through an id-keyed store overlay — do not make it settable.
@Observable
class StoryModel : Equatable, Identifiable {
    let id: Int
    private(set) var storyType: StoryType
    private(set) var title: String
    private(set) var by: String
    private(set) var timestamp: Date
    private(set) var score: Int
    private(set) var url: URL?
    private(set) var commentCount: Int
    private(set) var thumbnailStatus: ThumbnailType
    private(set) var text: String?

    /// Whether `fetchData()` has fully populated this model (story + thumbnail).
    /// A `StoryModel` instance is retained by its `StoryFeed` across cell
    /// recycling, so this guard keeps a row that scrolls back into view from
    /// re-fetching and, crucially, from briefly rendering as an empty placeholder.
    private var isLoaded = false

    init(id: Int) {
        self.id = id
        self.storyType = .unknown
        self.title = ""
        self.by = ""
        self.timestamp = Date()
        self.score = 0
        self.commentCount = 0
        self.url = nil
        self.thumbnailStatus = .loading
        self.text = nil
    }

    func fetchData() async {
        // Already populated (e.g. a recycled row) — nothing to do, and the
        // existing values stay on screen with no placeholder flash.
        guard !isLoaded else { return }
        guard let story = await HackerNewsAPI.getStory(id: id) else { return }

        if let url = story.url {
            storyType = .link
            self.url = URL(string: url)
        }
        else {
            storyType = .text
            self.url = nil
            self.text = story.text?.normalizeHtmlText() ?? ""
        }
        self.title = story.title
        self.by = story.by
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(story.time))
        self.score = story.score
        // `descendants` is the whole-thread comment total; `kids` is only the
        // top-level replies. Fall back to the top-level count if it's absent.
        self.commentCount = story.descendants ?? story.kids?.count ?? 0

        await fetchThumbnail()
        isLoaded = true
    }

    /// Resolves the cell's thumbnail from the shared cache. Text posts and
    /// missing-URL posts get their placeholder state directly.
    private func fetchThumbnail() async {
        guard storyType == .link else {
            thumbnailStatus = .text
            return
        }
        guard let url else {
            thumbnailStatus = .failed
            return
        }
        if let image = await ThumbnailCache.shared.thumbnail(for: url) {
            thumbnailStatus = .image(Image(uiImage: image))
        } else {
            thumbnailStatus = .failed
        }
    }

    /// The link's host with a leading "www." stripped, e.g. "github.com". Nil for
    /// text posts or links without a host. Shown after the title in the feed when
    /// the "Display story domain" setting is on.
    var displayDomain: String? {
        guard let host = url?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func ==(lhs: StoryModel, rhs: StoryModel) -> Bool {
        return lhs.title == rhs.title && lhs.id == rhs.id
    }
}
