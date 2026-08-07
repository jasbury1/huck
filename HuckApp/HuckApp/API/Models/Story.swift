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

@Observable
class StoryModel : Equatable {
    let id: Int
    var storyType: StoryType
    var title: String
    var by: String
    var timestamp: Date
    var score: Int
    var url: URL?
    var commentCount: Int
    var thumbnailStatus: ThumbnailType
    var text: String?

    /// Whether `fetchData()` has fully populated this model (story + thumbnail).
    /// A `StoryModel` instance is retained by `StoriesFeedData` across cell
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
        self.commentCount = story.kids?.count ?? 0

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

    static func ==(lhs: StoryModel, rhs: StoryModel) -> Bool {
        return lhs.title == rhs.title && lhs.id == rhs.id
    }
}
