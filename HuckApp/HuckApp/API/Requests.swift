//
//  Requests.swift
//  HuckApp
//
//  Created by James Asbury on 12/25/25.
//

enum StoryFilter {
    case topStories
    case bestStories
    case newStories
    case askStories
    case showStories
    case jobStories
    
}

// TODO: Finish using this class
struct FirebaseRequestHandler {
    static let baseUri = "https://hacker-news.firebaseio.com"
    
    static let topStoriesRequest = "\(baseUri)/v0/topstories.json?print=pretty"
}

// TODO: eventually needs an enum for if we are sorting by top, best, or new
func getStoryIdsAsync(filter: StoryFilter) async -> [Int] {
    let url = switch filter {
    case .topStories:
        "https://hacker-news.firebaseio.com/v0/topstories.json?print=pretty"
    case .bestStories:
        "https://hacker-news.firebaseio.com/v0/beststories.json?print=pretty"
    case .newStories:
        "https://hacker-news.firebaseio.com/v0/newstories.json?print=pretty"
    case .askStories:
        "https://hacker-news.firebaseio.com/v0/askstories.json?print=pretty"
    case .showStories:
        "https://hacker-news.firebaseio.com/v0/showstories.json?print=pretty"
    case .jobStories:
        "https://hacker-news.firebaseio.com/v0/jobstories.json?print=pretty"
    }
    guard let stories: [Int] = await WebService().downloadData(fromURL: url) else {
        return []
    }
    return stories
}

func getStoryAsync(id: Int) async -> Story? {
    let url = "https://hacker-news.firebaseio.com/v0/item/\(id).json?print=pretty"
    guard let story: Story = await WebService().downloadData(fromURL: url) else {
        return nil
    }
    return story
}

func getCommentAsync(id: Int) async -> Comment? {
    let url = "https://hacker-news.firebaseio.com/v0/item/\(id).json?print=pretty"
    guard let comment: Comment = await WebService().downloadData(fromURL: url) else {
        return nil
    }
    return comment
}
