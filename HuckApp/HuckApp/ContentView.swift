//
//  ContentView.swift
//  HuckApp
//
//  Created by James Asbury on 12/22/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Feed", systemImage: "newspaper.fill") {
                FeedView()
            }
            Tab("Account", systemImage: "person.circle") {
                AccountView()
            }
            
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView()
            }
            Tab(role: .search) {
                SearchView()
            }
        }
        .tint(.orange)
    }
}

#Preview {
    ContentView()
}
