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

struct StoriesView: View {
    let observableStories = StoriesViewObject()
    
    var body: some View {
        List {
            ForEach(observableStories.storyIds, id: \.self) {item in
                Text("\(item)")
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

func getStoryIdsAsync() async -> [Int]{
    let url = "https://hacker-news.firebaseio.com/v0/topstories.json?print=pretty"
    guard let stories: [Int] = await WebService().downloadData(fromURL: url) else {return []}
    print("Stories: \(stories)")
    return stories
}
