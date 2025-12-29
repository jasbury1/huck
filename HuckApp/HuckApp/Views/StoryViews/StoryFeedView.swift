//
//  StoryFeedView.swift
//  HuckApp
//
//  Created by James Asbury on 12/24/25.
//

import SwiftUI
import LinkPresentation
import UniformTypeIdentifiers

struct StoryFeedView: View {
    @State var storyFilter: StoryFilter
    @State var observableStories = StoriesFeedData()
    
    @Binding var path: NavigationPath
    
    var body: some View {
        List {
            ForEach(observableStories.storyIds, id: \.self) {item in
                StoryCellView(storyId: item, path: $path)
            }
        }
        .listStyle(.plain)
        .task (id: storyFilter) {
            await self.observableStories.fetchStoryIds(filter: storyFilter)
        }
        .toolbar {
            if storyFilter == .topStories || storyFilter == .bestStories || storyFilter == .newStories {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu(content: {
                        Picker(selection: $storyFilter,
                               label: Text("Sorting options")) {
                            Text("Top").tag(StoryFilter.topStories)
                            Text("Best").tag(StoryFilter.bestStories)
                            Text("New").tag(StoryFilter.newStories)
                            
                        }
                    }, label: {
                        switch storyFilter {
                        case .topStories: Image(systemName: "arrow.up")
                                .foregroundColor(.yellow)
                        case .bestStories: Image(systemName: "trophy")
                                .foregroundColor(.yellow)
                        case .newStories: Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .foregroundColor(.yellow)
                        default:
                            EmptyView()
                        }
                        
                    })
                }
            }
        }
        .navigationTitle(storyFilter.displayName())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu {
            Button("Stories", systemImage: "newspaper") {
                // Changing the view to stories only applies if we are not on some type of story view
                // If we are not on a story view, default to top stories
                if storyFilter != .topStories && storyFilter != .bestStories && storyFilter != .newStories {
                    storyFilter = .topStories
                }
            }
            Button("Ask Hacker News", systemImage: "questionmark.bubble") {
                storyFilter = .askStories
            }
            Button("Show Hacker News", systemImage: "eye") {
                storyFilter = .showStories
            }
            Button("Job Listings", systemImage: "briefcase") {
                storyFilter = .jobStories
            }
        }
    }
}

@Observable
class StoriesFeedData {
    var storyIds: [Int] = []
    
    func fetchStoryIds(filter: StoryFilter) async {
        let ids = await getStoryIdsAsync(filter: filter)
        self.storyIds = ids
    }
}
