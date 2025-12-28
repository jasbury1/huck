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
}

enum StoryType {
    case link
    case text
    case unknown
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
    // TODO: Thumbnail handling
    var thumbnail: Image?
    var text: String?
    
    init(id: Int) {
        self.id = id
        self.storyType = .unknown
        self.title = ""
        self.by = ""
        self.timestamp = Date()
        self.score = 0
        self.commentCount = 0
        self.url = nil
        self.text = nil
    }
    
    func fetchData() async {
        if let story = await StoryCache.getStory(id: id) {
            if let url = story.url {
                storyType = .link
                self.url = URL(string: url)
            }
            else {
                storyType = .text
                self.url = nil
                self.text = story.text
            }
            self.title = story.title
            self.by = story.by
            self.timestamp = Date(timeIntervalSince1970: TimeInterval(story.time))
            self.score = story.score
            self.commentCount = story.kids?.count ?? 0
        }
    }
    
    static func ==(lhs: StoryModel, rhs: StoryModel) -> Bool {
        return lhs.title == rhs.title && lhs.id == rhs.id
    }
}
