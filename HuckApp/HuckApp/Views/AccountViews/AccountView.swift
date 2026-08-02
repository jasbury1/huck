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
        let session = UserSession.shared
        let currentUsername = session?.username ?? ""
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
}

#Preview {
    //AccountView(authenticatedUser: "jasbury")
}

