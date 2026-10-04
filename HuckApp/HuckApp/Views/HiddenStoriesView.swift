//
//  HiddenStoriesView.swift
//  HuckApp
//
//  Created by James Asbury on 10/4/26.
//

import SwiftUI

/// The stories the reader has hidden from their feeds, reached from Settings:
/// the one place hiding can be undone after the moment has passed.
///
/// Laid out as a collection is — the same story cells, with the list's own
/// action on the trailing swipe and the action for the whole list in the
/// ellipsis menu. A swipe brings one story back; Unhide All, the lot.
struct HiddenStoriesView: View {
    @Binding var path: NavigationPath

    @Environment(InteractionStore.self) private var interactionStore

    /// A one-page feed over the hidden ids, reloaded as stories are unhidden.
    /// Kept as a single instance and only ever `reload()`ed — never rebuilt —
    /// to preserve its `StoryModel` cache, the same rule as a collection's.
    @State private var feed: StoryFeed?
    @State private var isConfirmingUnhideAll = false

    var body: some View {
        Group {
            if let feed {
                List {
                    ForEach(feed.stories) { story in
                        StoryCellView(model: story, path: $path)
                            .onAppear {
                                Task { await feed.prefetchAhead(after: story.id) }
                            }
                            // Where Hide sits on a feed's rows, so undoing it is
                            // the same gesture.
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    interactionStore.setHidden(false, for: story.id)
                                } label: {
                                    Label("Unhide", systemImage: "eye")
                                }
                                // Explicit, as every swipe action needs.
                                .tint(.gray)
                            }
                            // The feed's long-press menu, with Unhide where
                            // the feed offers Hide.
                            .contextMenu {
                                Group {
                                    StoryOptions(story: story)
                                    Section {
                                        Button("Unhide", systemImage: "eye") {
                                            interactionStore.setHidden(false, for: story.id)
                                        }
                                    }
                                }
                                // Icons match their text, not the app's orange
                                // tint.
                                .tint(.primary)
                            }
                    }
                }
                .listStyle(.plain)
                .overlay {
                    if feed.stories.isEmpty && !feed.hasMore {
                        EmptyFeedView(
                            title: "No Hidden Stories",
                            systemImage: "eye.slash",
                            description: "Swipe left on a story in a feed to hide it."
                        )
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Hidden Stories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Group {
                        Button("Unhide All", systemImage: "eye") {
                            isConfirmingUnhideAll = true
                        }
                        .disabled(interactionStore.hiddenIDs.isEmpty)
                    }
                    // Icons match their text, not the app's orange tint. Set on
                    // the content, so the ellipsis button itself keeps it.
                    .tint(.primary)
                } label: {
                    Label("Hidden Stories Options", systemImage: "ellipsis")
                }
            }
        }
        .alert("Unhide All Stories?", isPresented: $isConfirmingUnhideAll) {
            Button("Unhide All") {
                interactionStore.unhideAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll appear in your feeds again.")
        }
        .task {
            let feed = feed ?? StoryFeed.hidden(in: interactionStore)
            self.feed = feed
            await feed.reload()
        }
        // Every way a story is unhidden — a swipe, Unhide All — lands here.
        .onChange(of: interactionStore.hiddenIDs) {
            Task {
                await feed?.reload()
            }
        }
    }
}
