//
//  StoryOptionsMenu.swift
//  HuckApp
//
//  Created by James Asbury on 8/7/26.
//

import SwiftUI
import UIKit

/// A story's options, as menu rows. Shared by the story text view's toolbar
/// ellipsis and the long-press menu on feed rows, so both offer the same set.
struct StoryOptions: View {
    let story: StoryModel

    @Environment(InteractionStore.self) private var interactionStore
    @Environment(\.favorite) private var favorite
    @Environment(\.addToCollection) private var addToCollection

    private var isFavorited: Bool { interactionStore.interaction(for: story.id).isFavorited }

    var body: some View {
        // Copy actions. A link post has two distinct URLs — the article and the
        // Hacker News discussion — so it offers both; a text post's only link is
        // the Hacker News page, so it shows a single "Copy Link".
        Section {
            if let contentURL = story.contentURL {
                Button {
                    UIPasteboard.general.url = contentURL
                } label: {
                    Label("Copy Page Link", systemImage: "link")
                }
                Button {
                    UIPasteboard.general.url = story.hackerNewsURL
                } label: {
                    Label("Copy HN Link", systemImage: "text.bubble")
                }
            } else {
                Button {
                    UIPasteboard.general.url = story.hackerNewsURL
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            }
        }
        Section {
            Button {
                favorite(story)
            } label: {
                Label(
                    isFavorited ? "Unfavorite" : "Favorite",
                    systemImage: isFavorited ? "heart.slash" : "heart"
                )
            }
            Button {
                addToCollection(story)
            } label: {
                Label("Add to...", systemImage: "plus.rectangle.on.rectangle")
            }
        }
    }
}
