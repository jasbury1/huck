//
//  ViewA.swift
//  HuckApp
//
//  Created by James Asbury on 12/23/25.
//

import SwiftUI
import Foundation

struct AccountView: View {
    //@State var session = UserSession.shared
    // TODO: Eventually some more advanced observable user state needs to be shared for the app
    @State var authenticationTimestamp: Date? = nil
    @State private var path = NavigationPath()

    var body: some View {
        // Derive the signed-in user from the stored auth cookie. We pass
        // `authenticationTimestamp` (which login/logout updates) so that reading
        // it here creates a body dependency — otherwise SwiftUI never re-runs
        // this branch when the auth state changes and the login screen sticks.
        let currentUsername = sessionUsername(after: authenticationTimestamp)
        NavigationStack(path: $path) {
            Group {
                if !currentUsername.isEmpty {
                    UserView(username: currentUsername, path: $path)
                } else {
                    LoginView(authenticationTimestamp: $authenticationTimestamp)
                }
            }
            .navigationDestination(for: ItemNavigation.self) { navigation in
                StoryDetailsView(from: navigation, path: $path)
            }
        }
    }

    /// The signed-in user's name, derived from the stored auth cookie via
    /// `UserSession`. The `timestamp` parameter isn't used for the lookup — it
    /// exists so `body` reads `authenticationTimestamp` and re-evaluates when
    /// login/logout changes it.
    private func sessionUsername(after timestamp: Date?) -> String {
        UserSession.shared?.username ?? ""
    }
}

#Preview {
    //AccountView(authenticatedUser: "jasbury")
}

