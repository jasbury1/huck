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
        // Side by side when there's room: feeds on the left, the comments of
        // the story opened from them on the right.
        ThreadSplitNavigation(path: $path) {
            VStack {
                List {
                    Section(header: Text("Feeds")) {
                        TopStoriesRow()
                    }
                    .headerProminence(.increased)
                    // The other front-page rankings, in their own group as plain
                    // rows: only Top Stories, the default way in, is highlighted.
                    Section() {
                        FeedRow("Best", systemImage: "trophy.fill", feed: .bestStories)
                        FeedRow("New", systemImage: "clock.fill", feed: .newStories)
                    }
                    .listSectionSpacing(.custom(14))
                    Section() {
                        FeedRow("Ask", systemImage: "questionmark.message.fill", feed: .askStories)
                        FeedRow("Show", systemImage: "eye.fill", feed: .showStories)
                        FeedRow("Jobs", systemImage: "briefcase.fill", feed: .jobStories)
                    }
                    .listSectionSpacing(.custom(14))
                    HuckCollectionsSection(path: $path)
                    CollectionsSection(path: $path)
                }
                .sidebarColumnBackground()
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
        .storyActionsEnabled()
    }
}

/// A link to one of the front-page feeds. In a split view's sidebar it's a
/// `Label`, which lines every title up on one edge however wide its icon is; on
/// the single-column home screen it keeps its original icon-and-link layout.
private struct FeedRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let feed: FeedKind
    var iconColor: Color = .orange
    /// Applied to the title alone, since the sidebar's row style overrides a
    /// font set on the row as a whole.
    var titleFont: Font?

    @Environment(\.isSidebarColumnRoot) private var isInSidebar

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        feed: FeedKind,
        iconColor: Color = .orange,
        titleFont: Font? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.feed = feed
        self.iconColor = iconColor
        self.titleFont = titleFont
    }

    var body: some View {
        if isInSidebar {
            NavigationLink(value: feed) {
                Label {
                    Text(title)
                        .font(titleFont)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundColor(iconColor)
                }
            }
        } else {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(iconColor)
                NavigationLink(title, value: feed)
            }
        }
    }
}

/// The home screen's highlighted way in. Filled orange: as the whole card when
/// the list is inset grouped, or as a rounded highlight when it's the sidebar of
/// a split view, where there's no card to fill and a full-width band would run
/// edge to edge.
private struct TopStoriesRow: View {
    @Environment(\.isSidebarColumnRoot) private var isInSidebar

    var body: some View {
        Group {
            if isInSidebar {
                FeedRow(
                    "Top Stories",
                    systemImage: "book.pages.fill",
                    feed: .topStories,
                    iconColor: .white,
                    titleFont: .headline
                )
                .foregroundColor(.white)
            } else {
                HStack {
                    Image(systemName: "book.pages.fill")
                        .foregroundColor(.white)
                    NavigationLink("Top Stories", value: FeedKind.topStories)
                        .foregroundColor(.white)
                        .font(.headline)
                }
            }
        }
        .listRowBackground(background)
    }

    @ViewBuilder
    private var background: some View {
        if isInSidebar {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.orange)
                .padding(.horizontal, 10)
        } else {
            Color.orange
        }
    }
}

/// Opens the new-post page, signing in first if need be. Its own view so it
/// can read `composeNewPost`, which `storyActionsEnabled()` supplies only to
/// the views inside the navigation stack.
private struct NewPostButton: View {
    @Binding var path: NavigationPath
    @Environment(\.composeNewPost) private var composeNewPost
    @Environment(\.openThread) private var openThread

    var body: some View {
        Button {
            composeNewPost { openThread(.textStory(id: $0), from: $path) }
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

/// The home screen's "Your Collections" section: the device's collections as
/// navigable rows, with a trailing "New Collection" button that's hidden once
/// the five-collection cap is reached. The header's info button explains how
/// collections are stored, since they're the one list here that isn't tied to
/// the Hacker News account.
private struct CollectionsSection: View {
    @Binding var path: NavigationPath

    @Environment(CollectionsStore.self) private var collectionsStore

    @State private var isShowingInfo = false
    @State private var isNamingNewCollection = false
    @State private var newCollectionName = ""
    /// The collection awaiting confirmation of its deletion.
    @State private var collectionToDelete: StoryCollection?

    var body: some View {
        Section {
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
                    isNamingNewCollection = true
                } label: {
                    Label {
                        Text("New Collection")
                    } icon: {
                        Image(systemName: "plus")
                            .foregroundStyle(.orange)
                    }
                }
            }
        } header: {
            HStack {
                Text("Your Collections")
                Spacer()
                Button {
                    isShowingInfo = true
                } label: {
                    Label("About Collections", systemImage: "info.circle")
                        .labelStyle(.iconOnly)
                }
                .foregroundStyle(.orange)
                .popover(isPresented: $isShowingInfo) {
                    CollectionsInfoView()
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
