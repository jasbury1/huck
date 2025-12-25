//
//  StoryCache.swift
//  HuckApp
//
//  Created by James Asbury on 12/24/25.
//

// TODO: https://stackoverflow.com/questions/26742138/singleton-in-swift
// Make thread safe and respond to memory pressure
final class StoryCache {
    static let shared = StoryCache()
    
    private var storyIds = [Int]()
    private var cache = [Int: Story]()
    
    private init(){}
    
    static func setIds(from ids: [Int]) async {
        print("Setting up the cache from ids")
        let instance = StoryCache.shared
        let oldCache = instance.cache
        
        instance.cache = [Int: Story]()
        instance.storyIds = ids
        for id in ids {
            if let story = oldCache[id] {
                instance.cache[id] = story
            }
            else {
                let story = await fetchStory(id: id)
                print("Fetched new story for id \(id)")
                instance.cache[id] = story
            }
        }
        print("Done setting up the cache")
    }
    
    static func getStory(id: Int) -> Story? {
        print("Requested story for id \(id). Result: \(String(describing: StoryCache.shared.cache[id]))")
        return StoryCache.shared.cache[id]
    }
}

// TODO: Move this
func fetchStory(id: Int) async -> Story? {
    let url = "https://hacker-news.firebaseio.com/v0/item/\(id).json?print=pretty"
    guard let story: Story = await WebService().downloadData(fromURL: url) else {
        return nil
    }
    return story
}
