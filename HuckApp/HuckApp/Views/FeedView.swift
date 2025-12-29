//
//  ViewA.swift
//  HuckApp
//
//  Created by James Asbury on 12/23/25.
//

import SwiftUI

struct FeedView: View {
    @State private var path = NavigationPath()
    
    let temp = ["post 1", "post 2", "post 3"]
    
    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                List {
                    Section(header: Text("Feeds")) {
                        HStack {
                            Image(systemName: "book.pages.fill")
                                .foregroundColor(.white)
                            NavigationLink("Top Stories", value: StoryFilter.topStories)
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                        .listRowBackground(Color.orange)
                    }
                    .headerProminence(.increased)
                    Section() {
                        HStack {
                            Image(systemName: "questionmark.message.fill")
                                .foregroundColor(.orange)
                            NavigationLink("Ask", value: StoryFilter.askStories)
                        }
                        HStack {
                            Image(systemName: "eye.fill")
                                .foregroundColor(.orange)
                            NavigationLink("Show", value: StoryFilter.showStories)
                        }
                        HStack {
                            Image(systemName: "briefcase.fill")
                                .foregroundColor(.orange)
                            NavigationLink("Jobs", value: StoryFilter.jobStories)
                        }
                    }
                    .listSectionSpacing(.custom(14))
                    Section(header: Text("Pinned")) {
                        ForEach(temp, id: \.self) {entry in
                            Text(entry)
                        }
                    }
                    .headerProminence(.increased)
                }
            }
            .navigationTitle("Hacker News")
            .toolbar() {
                Image(systemName: "plus")
            }
            .navigationDestination(for: StoryFilter.self) { input in
                StoryFeedView(storyFilter: input, path: $path)
            }
            .navigationDestination(for: ItemNavigation.self) { navigation in
                StoryDetailsView(from: navigation)
            }
        }
    }
}
