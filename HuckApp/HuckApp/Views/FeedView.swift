//
//  ViewA.swift
//  HuckApp
//
//  Created by James Asbury on 12/23/25.
//

import SwiftUI

struct FeedView: View {
    @State private var path = NavigationPath()

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
                    HuckCollectionsSection(path: $path)
                    CollectionsSection(path: $path)
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
                StoryDetailsView(from: navigation, path: $path)
            }
        }
        .inAppBrowser()
        .storyActionsEnabled()
    }
}

/// The home screen's "Huck's Collections" section: app-curated, read-only
/// collections. A static catalog for now (see `HuckCollections`), shown above the
/// user's own collections.
private struct HuckCollectionsSection: View {
    @Binding var path: NavigationPath

    var body: some View {
        Section(header: Text("Huck's Collections")) {
            ForEach(HuckCollections.all) { collection in
                NavigationLink(value: ItemNavigation.huckCollection(id: collection.id)) {
                    Label {
                        Text(collection.name)
                    } icon: {
                        collection.symbol.image
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .headerProminence(.increased)
    }
}

/// The home screen's "Your Collections" section: the current user's collections
/// as navigable rows, with a trailing "New Collection" button that's hidden once
/// the five-collection cap is reached. Lives inside the feed's
/// `storyActionsEnabled` subtree so creating can be gated behind login via
/// `@Environment(\.requireLogin)`.
private struct CollectionsSection: View {
    @Binding var path: NavigationPath

    @Environment(CollectionsStore.self) private var collectionsStore
    @Environment(\.requireLogin) private var requireLogin

    @State private var isNamingNewCollection = false
    @State private var newCollectionName = ""

    var body: some View {
        Section(header: Text("Your Collections")) {
            ForEach(collectionsStore.collections) { collection in
                NavigationLink(value: ItemNavigation.collection(id: collection.id)) {
                    Label {
                        Text(collection.name)
                    } icon: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            if collectionsStore.canCreateCollection {
                Button {
                    // Collections are per-user, so require sign-in before naming one.
                    requireLogin { isNamingNewCollection = true }
                } label: {
                    Label {
                        Text("New Collection")
                    } icon: {
                        Image(systemName: "plus")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .headerProminence(.increased)
        .alert("New Collection", isPresented: $isNamingNewCollection) {
            TextField("Name", text: $newCollectionName)
            Button("Cancel", role: .cancel) { newCollectionName = "" }
            Button("Create") {
                collectionsStore.createCollection(named: newCollectionName)
                newCollectionName = ""
            }
        } message: {
            Text("Choose a name for your collection.")
        }
    }
}
