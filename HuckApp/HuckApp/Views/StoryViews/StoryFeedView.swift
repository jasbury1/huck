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
            ForEach(observableStories.storyIds, id: \.self) { id in
                StoryCellView(model: observableStories.model(for: id), path: $path)
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
    private(set) var storyIds: [Int] = []

    /// Populated view models, retained across cell recycling and keyed by story
    /// id. Because a recycled row reads its already-populated model from here
    /// (synchronously) rather than rebuilding an empty one and awaiting the
    /// cache, scrolling back to a story shows its content immediately instead
    /// of flashing the placeholder.
    private var models: [Int: StoryModel] = [:]

    /// The retained model for a story id. Every id in `storyIds` has an entry,
    /// created in `fetchStoryIds`, so this is a pure synchronous read.
    func model(for id: Int) -> StoryModel {
        models[id] ?? StoryModel(id: id)
    }

    func fetchStoryIds(filter: StoryFilter) async {
        let ids = await HackerNewsAPI.getStoryIds(filter: filter)

        // Create a model per id up front (reusing any we already hold), so rows
        // always find a retained instance. Set models before storyIds so the
        // list never reads an id that has no model yet.
        var updated: [Int: StoryModel] = [:]
        for id in ids {
            updated[id] = models[id] ?? StoryModel(id: id)
        }
        models = updated
        storyIds = ids

        // Warm the raw story cache ahead of display so the per-cell fetch is a
        // fast cache hit rather than a network round-trip.
        await HackerNewsAPI.prefetchStories(ids: ids)
    }
}
