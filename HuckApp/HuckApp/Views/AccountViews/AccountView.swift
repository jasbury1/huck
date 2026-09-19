//
//  ViewA.swift
//  HuckApp
//
//  Created by James Asbury on 12/23/25.
//

import SwiftUI
import Foundation

struct AccountView: View {
    @Environment(UserSession.self) private var session
    @State private var path = NavigationPath()

    var body: some View {
        // Reading `session.account` here is what ties this branch to the auth
        // state: it's observable, so signing in or out re-evaluates the view.
        NavigationStack(path: $path) {
            Group {
                if let account = session.account {
                    UserView(username: account.username, path: $path)
                } else {
                    LoginView()
                }
            }
            .navigationDestination(for: ItemNavigation.self) { navigation in
                StoryDetailsView(from: navigation, path: $path)
            }
            .toolbar {
                // Only meaningful once there's an account to act on; signed out,
                // the tab is just the login form.
                if session.isSignedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        accountMenu
                    }
                }
            }
        }
        .inAppBrowser()
        .storyActionsEnabled()
    }

    /// The account tab's overflow menu. Signing out is its only entry today, but
    /// it's a menu rather than a bare button so further account-level actions
    /// have somewhere to go.
    private var accountMenu: some View {
        Menu {
            Button(role: .destructive) {
                // Clearing the session cascades: `ContentView` observes the
                // account and re-points every per-user store, and this view
                // falls back to the login form.
                session.signOut()
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Label("Account Options", systemImage: "ellipsis")
        }
    }
}

#Preview {
    //AccountView(authenticatedUser: "jasbury")
}

