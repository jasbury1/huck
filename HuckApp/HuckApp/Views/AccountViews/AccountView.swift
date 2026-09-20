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

    /// Whether the Settings sheet is presented. Settings lives here rather than
    /// in its own tab, so this is the app's only way in.
    @State private var showingSettings = false

    /// Whether the login sheet is presented. Owned here rather than in
    /// `UserView` because both the signed-out profile's "Sign In" card and the
    /// account menu open the same sheet.
    @State private var showingLogin = false

    var body: some View {
        // Reading `session.username` here is what ties this tab to the auth
        // state: it's observable, so signing in or out re-evaluates the view.
        // The profile is shown either way — signed out it drops to the tabs and
        // actions that work without an account, and offers its own login sheet.
        NavigationStack(path: $path) {
            UserView(username: session.username, path: $path, onSignIn: { showingLogin = true })
                .navigationDestination(for: ItemNavigation.self) { navigation in
                    StoryDetailsView(from: navigation, path: $path)
                }
                // Both items are always present, signed in or out, so the pair
                // never shifts position underneath a tap.
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        accountMenu
                    }
                }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingLogin) {
            LoginView()
                .presentationDragIndicator(.visible)
        }
        // Signing in is the login sheet's whole purpose, so it's done the moment
        // an account appears; the page behind it fills in on its own.
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn { showingLogin = false }
        }
        .inAppBrowser()
        .storyActionsEnabled()
    }

    /// The account tab's overflow menu: the session action that applies right
    /// now. It's a menu rather than a bare button so further account-level
    /// actions have somewhere to go.
    private var accountMenu: some View {
        Menu {
            if session.isSignedIn {
                Button(role: .destructive) {
                    // Clearing the session cascades: `ContentView` observes the
                    // account and re-points every per-user store, and the
                    // profile below falls back to its signed-out state.
                    session.signOut()
                } label: {
                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                Button {
                    showingLogin = true
                } label: {
                    Label("Sign In", systemImage: "person.crop.circle")
                }
            }
        } label: {
            Label("Account Options", systemImage: "ellipsis")
        }
    }
}

#Preview {
    //AccountView(authenticatedUser: "jasbury")
}

