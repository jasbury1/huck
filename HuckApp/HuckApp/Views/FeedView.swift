//
//  ViewA.swift
//  HuckApp
//
//  Created by James Asbury on 12/23/25.
//

import SwiftUI

struct FeedView: View {
    var body: some View {
        NavigationStack {
            VStack {
                NavigationLink("Go to Stories", destination: StoriesView())
            }
        }
    }
}

struct StoryCellView: View {
    let storyId: Int
    private let observableStory: StoryCellViewData
    
    init(storyId: Int) {
        self.storyId = storyId
        self.observableStory = StoryCellViewData(storyId: storyId)
    }
    
    var body: some View {
        Text(observableStory.story?.title ?? "Title")
        .task {
            await observableStory.getStory()
        }
    }
}

struct StoriesView: View {
    let observableStories = StoriesViewObject()
    
    var body: some View {
        List {
            ForEach(observableStories.storyIds, id: \.self) {item in
                StoryCellView(storyId: item)
            }
        }
        .listStyle(.plain)
        .task {
            await self.observableStories.fetchStoryIds()
        }
    }
}

@Observable
class StoriesViewObject {
    var storyIds: [Int] = []
    
    func fetchStoryIds() async {
        let ids = await getStoryIdsAsync()
        self.storyIds = ids
    }
}

@Observable
class StoryCellViewData {
    let storyId: Int
    var story: Story? = nil
    
    init(storyId: Int) {
        self.storyId = storyId
    }
    
    func getStory() async {
        self.story = await getStoryAsync(id: self.storyId)
    }
}

// TODO: eventually needs an enum for if we are sorting by top, best, or new
func getStoryIdsAsync() async -> [Int] {
    let url = "https://hacker-news.firebaseio.com/v0/topstories.json?print=pretty"
    guard let stories: [Int] = await WebService().downloadData(fromURL: url) else {
        return []
    }
    print("Stories: \(stories)")
    return stories
}

struct Story: Codable {
    let title: String
}

func getStoryAsync(id: Int) async -> Story? {
    let url = "https://hacker-news.firebaseio.com/v0/item/\(id).json?print=pretty"
    guard let story: Story = await WebService().downloadData(fromURL: url) else {
        return nil
    }
    print("Story: \(story)")
    return story
}
