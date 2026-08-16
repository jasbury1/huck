//
//  UpvoteAction.swift
//  HuckApp
//
//  Created by James Asbury on 8/16/26.
//

import SwiftUI

/// Requests an upvote toggle for a story. Injected into the environment by
/// `upvoteEnabled()` and called from any story view's arrow, so the login gate and
/// the dispatch to `InteractionStore` live in one place rather than at each site.
struct UpvoteAction {
    let handler: (StoryModel) -> Void
    func callAsFunction(_ story: StoryModel) { handler(story) }
}

extension EnvironmentValues {
    @Entry var upvote = UpvoteAction { _ in }
}

/// Wires `@Environment(\.upvote)` for its subtree: logged-in taps toggle the vote
/// through the shared `InteractionStore`; logged-out taps present the login screen,
/// and a successful login reloads the store for the now-current user.
private struct UpvoteModifier: ViewModifier {
    @Environment(InteractionStore.self) private var store
    @State private var loginTimestamp: Date?
    @State private var isPresentingLogin = false

    func body(content: Content) -> some View {
        content
            .environment(\.upvote, UpvoteAction { story in
                if UserSession.shared != nil {
                    Task { await store.toggleUpvote(story) }
                } else {
                    isPresentingLogin = true
                }
            })
            .sheet(isPresented: $isPresentingLogin) {
                LoginView(authenticationTimestamp: $loginTimestamp)
            }
            .onChange(of: loginTimestamp) {
                // A successful login refreshes the cookie-derived session; reload
                // the store for the current user and dismiss the login sheet.
                store.loadForCurrentUser()
                isPresentingLogin = false
            }
    }
}

extension View {
    /// Enables `@Environment(\.upvote)` for this view's subtree, routing arrow taps
    /// through the interaction store and presenting login when signed out. Apply it
    /// once per navigation stack, above the story views that show upvote arrows.
    func upvoteEnabled() -> some View {
        modifier(UpvoteModifier())
    }
}
