//
//  ViewA.swift
//  HuckApp
//
//  Created by James Asbury on 12/23/25.
//

import SwiftUI

struct FeedView: View {
    let temp = ["post 1", "post 2", "post 3"]
    var body: some View {
        NavigationStack {
            VStack {
                List {
                    Section(header: Text("Feeds")) {
                        HStack {
                            Image(systemName: "book.pages.fill")
                                .foregroundColor(.white)
                            NavigationLink("Top Stories", destination: StoryFeedView(filter: .topStories))
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
                            NavigationLink("Ask", destination: StoryFeedView(filter: .askStories))
                        }
                        HStack {
                            Image(systemName: "eye.fill")
                                .foregroundColor(.orange)
                            NavigationLink("Show", destination: StoryFeedView(filter: .showStories))
                        }
                        HStack {
                            Image(systemName: "briefcase.fill")
                                .foregroundColor(.orange)
                            NavigationLink("Jobs", destination: StoryFeedView(filter: .jobStories))
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
        }
    }
}

