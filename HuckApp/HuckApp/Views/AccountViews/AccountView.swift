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
    
    var body: some View {
        if session != nil {
            Text("Hello \(session!.username)")
        } else {
            LoginView()
        }
        
    }
}
