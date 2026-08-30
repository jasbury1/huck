//
//  StoryOptionsMenu.swift
//  HuckApp
//
//  Created by James Asbury on 8/7/26.
//

import SwiftUI
import UIKit

/// The "More" options pop-up for a story, shared by the story feed's swipe
/// action and the story text view's toolbar button. Options are laid out as
/// capsule rows — a leading label and a trailing SF Symbol — with related
/// actions grouped into a single rounded card divided by separators, mirroring
/// the action rows in Apple's Mail app.
struct StoryOptionsMenu: View {
    let story: StoryModel

    /// Dismisses the presenting popover once an option has run.
    let dismiss: () -> Void

    @Environment(InteractionStore.self) private var interactionStore
    @Environment(\.favorite) private var favorite
    @Environment(\.requireLogin) private var requireLogin

    /// Presents the collection picker; gated behind login, since collections are
    /// per-user.
    @State private var isPresentingCollections = false

    private var isFavorited: Bool { interactionStore.interaction(for: story.id).isFavorited }

    var body: some View {
        VStack(spacing: 12) {
            // Copy Link stands on its own.
            group {
                row("Copy Link", systemImage: "link") {
                    // Link posts copy the article URL; text posts (no URL) fall
                    // back to the story's Hacker News discussion page.
                    UIPasteboard.general.url = story.url
                        ?? URL(string: "https://news.ycombinator.com/item?id=\(story.id)")
                }
            }
            // Favorite and Add to Collection are grouped as one card.
            group {
                row(
                    isFavorited ? "Unfavorite" : "Favorite",
                    systemImage: isFavorited ? "heart.slash" : "heart"
                ) {
                    favorite(story)
                }
                Divider()
                // Opens the collection picker rather than dismissing the menu, so
                // the picker has a presenter to attach to.
                row(
                    "Add to Collection...",
                    systemImage: "plus.rectangle.on.rectangle",
                    dismissesMenu: false
                ) {
                    requireLogin { isPresentingCollections = true }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .top)
        .presentationDetents([.height(240)])
        .sheet(isPresented: $isPresentingCollections) {
            AddToCollectionView(story: story)
        }
    }

    /// Wraps one or more option rows in a single rounded card, so grouped rows
    /// share a background with dividers between them (like Mail's action group).
    private func group<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// A single option row: leading label, trailing icon. Running the action also
    /// dismisses the popover, unless `dismissesMenu` is false — used by rows that
    /// present their own sheet, which needs this menu to stay as its presenter.
    /// Meant to sit inside a `group`.
    private func row(
        _ title: LocalizedStringKey,
        systemImage: String,
        dismissesMenu: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            if dismissesMenu { dismiss() }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: systemImage)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

extension View {
    /// Presents the shared `StoryOptionsMenu` for the bound story. The popover
    /// renders as a floating popover on iPad and adapts to a sheet on iPhone;
    /// setting the binding to a story presents it, and clearing it dismisses.
    func storyOptionsPopover(for story: Binding<StoryModel?>) -> some View {
        popover(
            isPresented: Binding(
                get: { story.wrappedValue != nil },
                set: { if !$0 { story.wrappedValue = nil } }
            )
        ) {
            if let model = story.wrappedValue {
                StoryOptionsMenu(story: model) { story.wrappedValue = nil }
            }
        }
    }
}
