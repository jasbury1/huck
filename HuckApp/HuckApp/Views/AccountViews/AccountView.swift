//
//  ViewA.swift
//  HuckApp
//
//  Created by James Asbury on 12/23/25.
//

import SwiftUI
import Foundation

struct AccountView: View {
    @State var session = UserSession.shared
    // TODO: Eventually some more advanced observable user state needs to be shared for the app
    @State var currentUsername: String = ""
    
    var body: some View {
        if !currentUsername.isEmpty {
            VStack {
                Text("Hello \(currentUsername)")
                Button("Logout") {
                    logout(username: currentUsername)
                    currentUsername = ""
                }
            }
            .task {
                session = UserSession.shared
                currentUsername = session?.username ?? ""
            }
        } else {
            LoginView(authenticatedUser: $currentUsername)
        }
    }
}

#Preview {
    AccountView(session: nil, currentUsername: "kasabali")
}

