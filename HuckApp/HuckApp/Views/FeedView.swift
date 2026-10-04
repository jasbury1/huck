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
                            NavigationLink("Top Stories", value: FeedKind.topStories)
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                        .listRowBackground(Color.orange)
                    }
                    .headerProminence(.increased)
                    // The other front-page rankings, in their own group as plain
                    // rows: only Top Stories, the default way in, is highlighted.
                    Section() {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(.orange)
                            NavigationLink("Best", value: FeedKind.bestStories)
                        }
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.orange)
                            NavigationLink("New", value: FeedKind.newStories)
                        }
                    }
                    .listSectionSpacing(.custom(14))
                    Section() {
                        HStack {
                            Image(systemName: "questionmark.message.fill")
                                .foregroundColor(.orange)
                            NavigationLink("Ask", value: FeedKind.askStories)
                        }
                        HStack {
                            Image(systemName: "eye.fill")
                                .foregroundColor(.orange)
                            NavigationLink("Show", value: FeedKind.showStories)
                        }
                        HStack {
                            Image(systemName: "briefcase.fill")
                                .foregroundColor(.orange)
                            NavigationLink("Jobs", value: FeedKind.jobStories)
                        }
                    }
                    .listSectionSpacing(.custom(14))
                    HuckCollectionsSection(path: $path)
                    CollectionsSection(path: $path)
                }
            }
            .navigationTitle("Hacker News")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NewPostButton(path: $path)
                }
            }
            .navigationDestination(for: FeedKind.self) { input in
                StoryFeedView(feedKind: input, path: $path)
            }
            .navigationDestination(for: ItemNavigation.self) { navigation in
                StoryDetailsView(from: navigation, path: $path)
            }
        }
        .inAppBrowser(path: $path)
        .storyActionsEnabled()
    }
}

/// Opens the new-post page, signing in first if need be. Its own view so it
/// can read `composeNewPost`, which `storyActionsEnabled()` supplies only to
/// the views inside the navigation stack.
private struct NewPostButton: View {
    @Binding var path: NavigationPath
    @Environment(\.composeNewPost) private var composeNewPost

    var body: some View {
        Button {
            composeNewPost { path.append(ItemNavigation.textStory(id: $0)) }
        } label: {
            Label("New Post", systemImage: "square.and.pencil")
        }
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
    /// The collection awaiting confirmation of its deletion.
    @State private var collectionToDelete: StoryCollection?

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
                // Swipe to delete, as with any list row. Not a full swipe: the
                // confirmation would interrupt the gesture's own commit.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        collectionToDelete = collection
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    // Explicit, or the app's orange tint wins over the
                    // destructive role's red and the action stops reading as
                    // destructive.
                    .tint(.red)
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
        .confirmsCollectionDeletion(of: $collectionToDelete)
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
