//
//  Stories.swift
//  HuckApp
//
//  Created by James Asbury on 12/28/25.
//

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
