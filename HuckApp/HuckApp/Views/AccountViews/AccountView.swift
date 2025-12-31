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
    
    var body: some View {
        let session = UserSession.shared
        let currentUsername = session?.username ?? ""
        if !currentUsername.isEmpty {
            UserView(username: currentUsername)
        } else {
            LoginView(authenticationTimestamp: $authenticationTimestamp)
        }
    }
}

#Preview {
    //AccountView(authenticatedUser: "jasbury")
}

