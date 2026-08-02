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
    private var cache = [Int: FirebaseStoryData]()
    
    private init(){}
    
    static func setIds(from ids: [Int]) async {
        print("Setting up the cache from ids")
        let instance = StoryCache.shared
        let oldCache = instance.cache
        
        instance.cache = [Int: FirebaseStoryData]()
        instance.storyIds = ids
        for id in ids {
            if let story = oldCache[id] {
                instance.cache[id] = story
            }
            else {
                let story = await FirebaseAPIService.getStoryAsync(id: id)
                if story != nil {
                    instance.cache[id] = story
                }
            }
        }
        print("Done setting up the cache")
    }
    
    static func getStory(id: Int) async -> FirebaseStoryData? {
        let instance = StoryCache.shared
        if let story = StoryCache.shared.cache[id] {
            return story
        }
        else {
            let story = await FirebaseAPIService.getStoryAsync(id: id)
            if story != nil {
                instance.cache[id] = story
                return story
            }
        }
        return nil
    }
}
