//
//  StoryActions.swift
//  HuckApp
//
//  Created by James Asbury on 8/16/26.
//

import SwiftUI

/// Requests an upvote toggle for a story. Injected into the environment by
/// `storyActionsEnabled()` and called from any story view's arrow, so the login
/// gate and the dispatch to `InteractionStore` live in one place, not at each site.
struct UpvoteAction {
    let handler: (StoryModel) -> Void
    func callAsFunction(_ story: StoryModel) { handler(story) }
}

/// Requests a favorite toggle for a story. The favorites counterpart to
/// `UpvoteAction`, sharing the same login gate.
struct FavoriteAction {
    let handler: (StoryModel) -> Void
    func callAsFunction(_ story: StoryModel) { handler(story) }
}

extension EnvironmentValues {
    @Entry var upvote = UpvoteAction { _ in }
    @Entry var favorite = FavoriteAction { _ in }
}

/// Wires the story action environment values for its subtree: logged-in taps toggle
/// the upvote/favorite through the shared `InteractionStore`; logged-out taps present
/// the login screen, and a successful login reloads the store for the now-current
/// user. One login gate is shared by both actions.
private struct StoryActionsModifier: ViewModifier {
    @Environment(InteractionStore.self) private var store
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore
    @State private var loginTimestamp: Date?
    @State private var isPresentingLogin = false

    func body(content: Content) -> some View {
        content
            .environment(\.upvote, UpvoteAction { story in
                perform { await store.toggleUpvote(story) }
            })
            .environment(\.favorite, FavoriteAction { story in
                perform { await store.toggleFavorite(story) }
            })
            .sheet(isPresented: $isPresentingLogin) {
                LoginView(authenticationTimestamp: $loginTimestamp)
            }
            .onChange(of: loginTimestamp) {
                // A successful login refreshes the cookie-derived session; reload
                // the store for the current user, carry any signed-out browsing
                // into the account, and dismiss the login sheet.
                store.loadForCurrentUser()
                recentlyViewedStore.adoptGuestHistory()
                isPresentingLogin = false
            }
    }

    /// Runs a store action when signed in, or routes to login when signed out.
    private func perform(_ action: @escaping () async -> Void) {
        if UserSession.shared != nil {
            Task { await action() }
        } else {
            isPresentingLogin = true
        }
    }
}

extension View {
    /// Enables `@Environment(\.upvote)` and `@Environment(\.favorite)` for this
    /// view's subtree, routing taps through the interaction store and presenting
    /// login when signed out. Apply it once per navigation stack, above the story
    /// views that show these actions.
    func storyActionsEnabled() -> some View {
        modifier(StoryActionsModifier())
    }
}
